import Foundation

// MARK: - Adaptive Response System
// Coordinates context detection, UI intelligence, and intent analysis
// to provide context-aware tool selection and response formatting.

final class AdaptiveResponseSystem {

    // MARK: - Components

    let contextDetector: ContextDetector
    let uiIntelligence: UIIntelligence
    let intentAnalyzer: IntentAnalyzer

    // MARK: - State

    private var lastContextInfo: ContextDetector.ContextInfo?
    private var sessionInteractions: Int = 0

    // MARK: - Init

    init() {
        self.contextDetector = ContextDetector()
        self.uiIntelligence = UIIntelligence()
        self.intentAnalyzer = IntentAnalyzer()
    }

    // MARK: - Pre-Processing (before AI call)

    /// Build adaptive system prompt additions based on context, intent, and UI state.
    /// Called before each API call to enrich the system prompt.
    func buildAdaptiveContext(
        userInput: String,
        gatewayContext: GatewayDeliveryContext?,
        isSubAgent: Bool
    ) -> String {
        // 1. Detect execution context
        let contextInfo = contextDetector.detect(
            gatewayContext: gatewayContext,
            isSubAgent: isSubAgent
        )
        lastContextInfo = contextInfo

        var additions = ""

        // 2. Add context-specific formatting instructions
        additions += contextDetector.systemPromptAdditions(for: contextInfo)

        // 3. Analyze user intent and add tool recommendations
        additions += intentAnalyzer.buildIntentContext(
            input: userInput,
            frontmostApp: contextInfo.frontmostApp
        )

        // 4. Add UI intelligence hints if we have cached layout for the active app
        if let app = contextInfo.frontmostApp,
           let layout = uiIntelligence.getCachedLayout(appName: app) {
            additions += buildUIHints(layout: layout, app: app)
        }

        return additions
    }

    /// Get the recommended tools based on current context and intent.
    /// Returns tools sorted by relevance (most preferred first).
    func recommendTools(userInput: String) -> [String] {
        let context = lastContextInfo ?? contextDetector.detect()
        let intent = intentAnalyzer.analyze(input: userInput, frontmostApp: context.frontmostApp)
        return intent.suggestedTools
    }

    // MARK: - Post-Processing (after tool execution)

    /// Record a UI interaction for learning.
    /// Called after get_ui_elements completes to cache the layout.
    func recordUIElements(appName: String, bundleId: String?, elements: [UIElement], windowBounds: CGRect?) {
        uiIntelligence.recordElements(
            appName: appName, bundleId: bundleId,
            elements: elements, windowBounds: windowBounds
        )
    }

    /// Record a click interaction for learning.
    func recordClick(appName: String, elementRole: String, elementTitle: String?, x: Int, y: Int, success: Bool) {
        uiIntelligence.recordInteraction(
            appName: appName, elementRole: elementRole,
            elementTitle: elementTitle, x: x, y: y, success: success
        )
        sessionInteractions += 1
    }

    /// Record a completed workflow for learning.
    func recordWorkflow(appName: String, name: String, steps: [UIIntelligence.WorkflowStep], durationMs: Int, success: Bool) {
        uiIntelligence.recordWorkflow(
            appName: appName, name: name,
            steps: steps, durationMs: durationMs, success: success
        )
    }

    /// Format a response for the current context.
    func formatResponse(_ text: String) -> String {
        guard let context = lastContextInfo else { return text }
        return contextDetector.formatResponse(text, context: context)
    }

    /// Format tool output for the current context.
    func formatToolOutput(toolName: String, result: ToolResult) -> String {
        guard let context = lastContextInfo else {
            let icon = result.success ? "✓" : "✗"
            return "  \(icon) \(toolName): \(String(result.output.prefix(300)))"
        }
        return contextDetector.formatToolOutput(toolName, result, context: context)
    }

    // MARK: - Context Queries

    /// Get the current execution context
    var currentContext: ContextDetector.ContextInfo? { lastContextInfo }

    /// Whether the current context supports image responses
    var supportsImages: Bool {
        lastContextInfo?.supportsImages ?? true
    }

    /// Max response length for current context
    var maxResponseLength: Int {
        lastContextInfo?.maxResponseLength ?? 100_000
    }

    /// Current output format
    var outputFormat: ContextDetector.OutputFormat {
        lastContextInfo?.format ?? .richTerminal
    }

    // MARK: - Session Management

    /// Save all learned data to disk
    func saveSession() {
        uiIntelligence.saveCache()
    }

    /// Reset ephemeral state (keep learned data)
    func resetSession() {
        contextDetector.invalidate()
        sessionInteractions = 0
    }

    /// Clear all caches and learned data
    func clearAll() {
        uiIntelligence.clearCache()
        contextDetector.invalidate()
        sessionInteractions = 0
    }

    /// Get adaptive system stats
    var stats: String {
        var lines: [String] = []
        lines.append("Adaptive Response System")

        if let ctx = lastContextInfo {
            lines.append("  Context: \(ctx.context.rawValue) (\(ctx.format.rawValue))")
            if let platform = ctx.platform { lines.append("  Platform: \(platform)") }
            if let app = ctx.frontmostApp { lines.append("  Active app: \(app)") }
            lines.append("  Max response: \(ctx.maxResponseLength) chars, Images: \(ctx.supportsImages)")
        }

        lines.append("  Session interactions: \(sessionInteractions)")
        lines.append("  \(uiIntelligence.stats)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func buildUIHints(layout: UIIntelligence.AppLayout, app: String) -> String {
        var hints = "\n\n## UI INTELLIGENCE — \(app):"

        // Show hot elements (frequently used)
        let hot = uiIntelligence.getHotElements(appName: app, limit: 5)
        if !hot.isEmpty {
            hints += "\nFrequently used elements:"
            for elem in hot {
                let title = elem.title ?? elem.role
                hints += "\n  • \(title) at (\(elem.centerX),\(elem.centerY)) — used \(elem.hitCount)x"
            }
        }

        // Show known workflows
        let workflows = layout.workflows.filter { $0.reliability > 0.7 }.prefix(3)
        if !workflows.isEmpty {
            hints += "\nKnown workflows:"
            for wf in workflows {
                hints += "\n  • \(wf.name) (\(wf.steps.count) steps, \(Int(wf.reliability * 100))% reliable, ~\(wf.avgDurationMs)ms)"
            }
        }

        return hints
    }
}
