import Foundation
import AppKit

// MARK: - Context Detector
// Detects the execution context (terminal, chat gateway, GUI task, piped input)
// and adjusts response formatting automatically.

final class ContextDetector {

    // MARK: - Types

    /// The detected execution context
    enum ExecutionContext: String, Codable {
        case terminal       // Interactive CLI session
        case gateway        // Discord/Telegram/Slack/WhatsApp
        case singleCommand  // Piped input or `osai "command"`
        case guiTask        // Agent is performing GUI automation
        case subAgent       // Running as a sub-agent
        case desktopApp     // Desktop app via --app-mode (NDJSON protocol)
    }

    /// Output format matching the context
    enum OutputFormat: String, Codable {
        case richTerminal   // ANSI colors, unicode, full width
        case markdown       // Markdown for chat platforms
        case plainText      // No formatting, for pipes/scripts
        case structured     // JSON-like structured output for programmatic use
    }

    /// Detected context with metadata
    struct ContextInfo {
        let context: ExecutionContext
        let format: OutputFormat
        let platform: String?          // "discord", "telegram", etc.
        let frontmostApp: String?      // Current foreground app
        let isInteractive: Bool        // Has a live TTY
        let maxResponseLength: Int     // Character limit for output
        let supportsImages: Bool       // Can embed screenshots
    }

    // MARK: - Platform Limits

    /// Max message lengths per platform
    private static let platformLimits: [String: Int] = [
        "discord": 2000,
        "telegram": 4096,
        "slack": 40000,
        "whatsapp": 65536,
        "terminal": 100_000,
    ]

    /// Platforms that support image embedding
    private static let imageCapablePlatforms: Set<String> = [
        "discord", "telegram", "slack", "terminal"
    ]

    // MARK: - State

    private var cachedContext: ContextInfo?
    private var lastDetectionTime: Date?
    private let cacheTTL: TimeInterval = 5.0  // Re-detect every 5s

    // MARK: - Detection

    /// Detect the current execution context
    func detect(gatewayContext: GatewayDeliveryContext? = nil, isSubAgent: Bool = false) -> ContextInfo {
        // Return cache if fresh
        if let cached = cachedContext, let lastTime = lastDetectionTime,
           Date().timeIntervalSince(lastTime) < cacheTTL {
            return cached
        }

        let context: ExecutionContext
        let format: OutputFormat
        let platform: String?
        let maxLen: Int
        let supportsImages: Bool

        if ProcessInfo.processInfo.arguments.contains("--app-mode") {
            context = .desktopApp
            format = .structured
            platform = nil
            maxLen = 100_000
            supportsImages = false
        } else if isSubAgent {
            context = .subAgent
            format = .plainText
            platform = nil
            maxLen = 50_000
            supportsImages = false
        } else if let gw = gatewayContext {
            context = .gateway
            format = .markdown
            platform = gw.platform
            maxLen = Self.platformLimits[gw.platform] ?? 4096
            supportsImages = Self.imageCapablePlatforms.contains(gw.platform)
        } else if isatty(STDIN_FILENO) == 0 || ProcessInfo.processInfo.environment["OSAI_PIPE"] != nil {
            // Piped input or single command mode
            context = .singleCommand
            format = .plainText
            platform = nil
            maxLen = 100_000
            supportsImages = false
        } else {
            context = .terminal
            format = .richTerminal
            platform = "terminal"
            maxLen = 100_000
            supportsImages = true
        }

        let frontApp = detectFrontmostApp()

        let info = ContextInfo(
            context: context,
            format: format,
            platform: platform,
            frontmostApp: frontApp,
            isInteractive: isatty(STDIN_FILENO) != 0,
            maxResponseLength: maxLen,
            supportsImages: supportsImages
        )

        cachedContext = info
        lastDetectionTime = Date()
        return info
    }

    /// Force a re-detection on next access
    func invalidate() {
        cachedContext = nil
        lastDetectionTime = nil
    }

    // MARK: - Response Formatting

    /// Format a response string for the current context
    func formatResponse(_ text: String, context: ContextInfo) -> String {
        switch context.format {
        case .richTerminal:
            return text  // Already handles ANSI in AgentLoop

        case .markdown:
            return formatForChat(text, maxLen: context.maxResponseLength)

        case .plainText:
            return stripFormatting(text)

        case .structured:
            return text  // Caller handles structured output
        }
    }

    /// Format tool output for the current context
    func formatToolOutput(_ toolName: String, _ result: ToolResult, context: ContextInfo) -> String {
        switch context.format {
        case .richTerminal:
            let icon = result.success ? "✓" : "✗"
            return "  \(icon) \(toolName): \(String(result.output.prefix(500)))"

        case .markdown:
            let icon = result.success ? "✅" : "❌"
            let output = String(result.output.prefix(min(1500, context.maxResponseLength / 3)))
            return "\(icon) **\(toolName)**\n```\n\(output)\n```"

        case .plainText:
            let status = result.success ? "OK" : "FAIL"
            return "[\(status)] \(toolName): \(result.output)"

        case .structured:
            return "{\"\(toolName)\": {\"success\": \(result.success), \"output\": \"\(result.output.prefix(2000))\"}}"
        }
    }

    /// Build context-appropriate system prompt additions
    func systemPromptAdditions(for context: ContextInfo) -> String {
        var additions = ""

        switch context.context {
        case .gateway:
            let platform = context.platform ?? "chat"
            let limit = context.maxResponseLength
            additions += """

            ## RESPONSE FORMAT — \(platform.uppercased()) GATEWAY:
            - Keep responses under \(limit) characters (platform limit)
            - Use markdown formatting (bold, code blocks, lists)
            - Be concise — chat users prefer short, actionable responses
            - Use emoji sparingly for status indicators
            - Split very long outputs across multiple messages if needed
            - Don't include raw terminal output unless specifically asked
            """

        case .terminal:
            additions += """

            ## RESPONSE FORMAT — TERMINAL:
            - Full-length responses are fine
            - Use structured output with clear sections
            - Include technical details when relevant
            """

        case .singleCommand:
            additions += """

            ## RESPONSE FORMAT — SINGLE COMMAND:
            - Output only the result, no conversational filler
            - Prefer machine-parseable output when possible
            - No greetings or sign-offs
            """

        case .guiTask:
            additions += """

            ## RESPONSE FORMAT — GUI TASK:
            - Focus on action confirmations
            - Brief status updates between actions
            - Report completion clearly
            """

        case .subAgent:
            additions += """

            ## RESPONSE FORMAT — SUB-AGENT:
            - Return structured results for the parent agent
            - No conversational text
            - Focus on data and findings
            """

        case .desktopApp:
            additions += """

            ## RESPONSE FORMAT — DESKTOP APP:
            - Use markdown formatting for rich display
            - Be concise and well-structured
            - No raw terminal output or ANSI codes
            """
        }

        // Add frontmost app context if available and doing GUI work
        if let app = context.frontmostApp, context.context == .terminal || context.context == .gateway {
            additions += "\n\nCurrently active app: \(app)"
        }

        return additions
    }

    // MARK: - Helpers

    private func detectFrontmostApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return app.localizedName
    }

    /// Truncate and format for chat platforms
    private func formatForChat(_ text: String, maxLen: Int) -> String {
        guard text.count > maxLen else { return text }

        // Try to cut at a sentence boundary
        let truncated = String(text.prefix(maxLen - 20))
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod]) + "\n\n_(truncated)_"
        }
        return truncated + "…\n\n_(truncated)_"
    }

    /// Strip ANSI codes and markdown formatting
    private func stripFormatting(_ text: String) -> String {
        // Strip ANSI escape codes
        var result = text.replacingOccurrences(
            of: "\\e\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
        // Also handle \u{001B} format
        result = result.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
        return result
    }
}
