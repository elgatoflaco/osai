import Foundation

// MARK: - Advanced Error Recovery System
// Classifies errors, applies automatic recovery strategies, and maintains
// fallback chains for graceful degradation.

final class ErrorRecovery {

    // MARK: - Error Classification

    enum ErrorCategory {
        case transientNetwork      // Timeout, DNS, connection reset
        case rateLimited           // 429, quota exceeded
        case authFailure           // 401, 403, invalid key
        case toolNotFound          // Unknown tool name
        case toolExecFailure       // Tool ran but returned error
        case permissionDenied      // macOS permission (accessibility, screen recording)
        case resourceNotFound      // File/app/window not found
        case timeout               // Tool execution timeout
        case contextOverflow       // Context window exceeded
        case unknown
    }

    struct ClassifiedError {
        let category: ErrorCategory
        let message: String
        let isRetryable: Bool
        let suggestedAction: RecoveryAction
        let originalError: Error?
    }

    enum RecoveryAction {
        case retry(delayMs: Int, maxAttempts: Int)
        case fallbackTool(name: String, input: [String: AnyCodable])
        case reduceContext
        case requestPermission(String)
        case reportToUser(String)
        case skipAndContinue
    }

    /// Fallback chains: when tool X fails, try tool Y instead
    struct FallbackChain {
        let fromTool: String
        let toTool: String
        let condition: String  // Description of when to use
        let transformInput: ([String: AnyCodable]) -> [String: AnyCodable]
    }

    // MARK: - State

    private var recentErrors: [(Date, ClassifiedError)] = []
    private var retryCount: [String: Int] = [:]  // tool:inputHash → retry count
    private(set) var errorsRecovered: Int = 0
    private(set) var errorsFailed: Int = 0
    private(set) var fallbacksUsed: Int = 0

    // MARK: - Fallback Chains

    /// Built-in fallback chains for common tool failures
    static let fallbackChains: [FallbackChain] = [
        // Shell fails → try AppleScript
        FallbackChain(
            fromTool: "run_shell",
            toTool: "run_applescript",
            condition: "Shell command fails for app interaction",
            transformInput: { input in
                let cmd = input["command"]?.stringValue ?? ""
                // Convert common shell→applescript patterns
                if cmd.hasPrefix("open -a") {
                    let app = cmd.replacingOccurrences(of: "open -a '", with: "")
                        .replacingOccurrences(of: "'", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return ["script": AnyCodable("tell application \"\(app)\" to activate")]
                }
                return input  // Can't convert, pass through
            }
        ),
        // AppleScript fails → try shell open
        FallbackChain(
            fromTool: "run_applescript",
            toTool: "run_shell",
            condition: "AppleScript fails for app launch",
            transformInput: { input in
                let script = input["script"]?.stringValue ?? ""
                // Extract app name from "tell application X to activate"
                if let range = script.range(of: "tell application \""),
                   let endRange = script.range(of: "\"", range: range.upperBound..<script.endIndex) {
                    let app = String(script[range.upperBound..<endRange.lowerBound])
                    return ["command": AnyCodable("open -a '\(app)'"), "timeout": AnyCodable(10)]
                }
                return input
            }
        ),
        // get_ui_elements fails → try screenshot as fallback
        FallbackChain(
            fromTool: "get_ui_elements",
            toTool: "take_screenshot",
            condition: "UI element inspection fails — fall back to visual",
            transformInput: { _ in [:] }
        ),
        // click_element fails → try AppleScript click
        FallbackChain(
            fromTool: "click_element",
            toTool: "run_applescript",
            condition: "Direct click fails — try AppleScript System Events click",
            transformInput: { input in
                let x = input["x"]?.intValue ?? 0
                let y = input["y"]?.intValue ?? 0
                let script = """
                tell application "System Events"
                    click at {\(x), \(y)}
                end tell
                """
                return ["script": AnyCodable(script)]
            }
        ),
    ]

    // MARK: - Error Classification

    /// Classify an error into a category with recovery suggestion
    func classify(error: Error, toolName: String? = nil, httpStatus: Int? = nil) -> ClassifiedError {
        let msg = "\(error)"

        // API errors
        if let status = httpStatus {
            switch status {
            case 429:
                return ClassifiedError(
                    category: .rateLimited, message: msg, isRetryable: true,
                    suggestedAction: .retry(delayMs: 2000, maxAttempts: 3),
                    originalError: error
                )
            case 401, 403:
                return ClassifiedError(
                    category: .authFailure, message: msg, isRetryable: false,
                    suggestedAction: .reportToUser("Authentication failed. Check your API key with /config."),
                    originalError: error
                )
            case 500...599:
                return ClassifiedError(
                    category: .transientNetwork, message: msg, isRetryable: true,
                    suggestedAction: .retry(delayMs: 1000, maxAttempts: 2),
                    originalError: error
                )
            default:
                break
            }
        }

        // Agent errors
        if let agentError = error as? AgentError {
            switch agentError {
            case .networkError:
                return ClassifiedError(
                    category: .transientNetwork, message: msg, isRetryable: true,
                    suggestedAction: .retry(delayMs: 1000, maxAttempts: 3),
                    originalError: error
                )
            case .apiError(let code, _):
                // Avoid infinite recursion: only recurse if httpStatus wasn't already set
                if httpStatus == nil {
                    return classify(error: error, toolName: toolName, httpStatus: code)
                }
                return ClassifiedError(
                    category: .transientNetwork, message: msg, isRetryable: true,
                    suggestedAction: .retry(delayMs: 1000, maxAttempts: 2),
                    originalError: error
                )
            case .noAPIKey:
                return ClassifiedError(
                    category: .authFailure, message: msg, isRetryable: false,
                    suggestedAction: .reportToUser("No API key configured. Use /config set-key <provider> <key>."),
                    originalError: error
                )
            case .permissionDenied:
                return ClassifiedError(
                    category: .permissionDenied, message: msg, isRetryable: false,
                    suggestedAction: .reportToUser(msg),
                    originalError: error
                )
            case .toolError:
                return ClassifiedError(
                    category: .toolExecFailure, message: msg, isRetryable: false,
                    suggestedAction: .skipAndContinue,
                    originalError: error
                )
            }
        }

        // Pattern matching on error messages
        let lower = msg.lowercased()

        if lower.contains("timeout") || lower.contains("timed out") {
            return ClassifiedError(
                category: .timeout, message: msg, isRetryable: true,
                suggestedAction: .retry(delayMs: 500, maxAttempts: 2),
                originalError: error
            )
        }

        if lower.contains("permission") || lower.contains("not permitted") || lower.contains("accessibility") {
            let permission = lower.contains("accessibility") ? "Accessibility" :
                            lower.contains("screen") ? "Screen Recording" : "System"
            return ClassifiedError(
                category: .permissionDenied, message: msg, isRetryable: false,
                suggestedAction: .requestPermission(permission),
                originalError: error
            )
        }

        if lower.contains("not found") || lower.contains("no such file") || lower.contains("does not exist") {
            return ClassifiedError(
                category: .resourceNotFound, message: msg, isRetryable: false,
                suggestedAction: .reportToUser(msg),
                originalError: error
            )
        }

        if lower.contains("context") && (lower.contains("limit") || lower.contains("exceed") || lower.contains("too long")) {
            return ClassifiedError(
                category: .contextOverflow, message: msg, isRetryable: true,
                suggestedAction: .reduceContext,
                originalError: error
            )
        }

        // Default
        return ClassifiedError(
            category: .unknown, message: msg, isRetryable: false,
            suggestedAction: .reportToUser(msg),
            originalError: error
        )
    }

    /// Classify a tool result failure
    func classifyToolFailure(toolName: String, result: ToolResult) -> ClassifiedError? {
        guard !result.success else { return nil }

        let msg = result.output.lowercased()

        if msg.contains("not found") || msg.contains("no such") {
            return ClassifiedError(
                category: .resourceNotFound, message: result.output, isRetryable: false,
                suggestedAction: findFallback(for: toolName) ?? .reportToUser(result.output),
                originalError: nil
            )
        }

        if msg.contains("permission") || msg.contains("accessibility") {
            return ClassifiedError(
                category: .permissionDenied, message: result.output, isRetryable: false,
                suggestedAction: .requestPermission("macOS permissions"),
                originalError: nil
            )
        }

        if msg.contains("timeout") || msg.contains("timed out") {
            return ClassifiedError(
                category: .timeout, message: result.output, isRetryable: true,
                suggestedAction: .retry(delayMs: 500, maxAttempts: 1),
                originalError: nil
            )
        }

        // Check if we have a fallback chain for this tool
        if let fallback = findFallback(for: toolName) {
            return ClassifiedError(
                category: .toolExecFailure, message: result.output, isRetryable: true,
                suggestedAction: fallback,
                originalError: nil
            )
        }

        return nil
    }

    // MARK: - Recovery Execution

    /// Attempt recovery for a failed tool call
    func attemptRecovery(
        toolName: String,
        input: [String: AnyCodable],
        error: ClassifiedError,
        executor: ToolExecutor
    ) -> (ToolResult, String?)? {
        let key = "\(toolName):\(input.keys.sorted().joined())"

        switch error.suggestedAction {
        case .retry(let delayMs, let maxAttempts):
            let attempts = retryCount[key, default: 0]
            if attempts >= maxAttempts {
                errorsFailed += 1
                return nil
            }
            retryCount[key] = attempts + 1

            // Delay before retry
            Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)

            // Retry the tool
            let (result, screenshot) = executor.execute(toolName: toolName, input: input)
            if result.success {
                errorsRecovered += 1
                retryCount.removeValue(forKey: key)
                return (result, screenshot)
            }
            return nil

        case .fallbackTool(let fallbackName, let fallbackInput):
            fallbacksUsed += 1
            let (result, screenshot) = executor.execute(toolName: fallbackName, input: fallbackInput)
            if result.success {
                errorsRecovered += 1
                return (result, screenshot)
            }
            return nil

        case .reduceContext, .requestPermission, .reportToUser, .skipAndContinue:
            // These are handled at the AgentLoop level, not here
            return nil
        }
    }

    // MARK: - Proactive Prevention

    /// Check for common failure conditions BEFORE executing a tool
    func preflightCheck(toolName: String, input: [String: AnyCodable]) -> String? {
        switch toolName {
        case "read_file", "write_file", "file_info":
            let path = input["path"]?.stringValue ?? ""
            if path.isEmpty { return "Error: path is empty" }
            let expanded = (path as NSString).expandingTildeInPath
            // Check if parent directory exists for writes
            if toolName == "write_file" {
                let parent = (expanded as NSString).deletingLastPathComponent
                if !FileManager.default.fileExists(atPath: parent) {
                    return "Warning: parent directory '\(parent)' does not exist"
                }
            }

        case "activate_app", "open_app":
            let name = input["name"]?.stringValue ?? ""
            if name.isEmpty { return "Error: app name is empty" }

        case "click_element":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            if x == 0 && y == 0 { return "Warning: clicking at (0,0) — likely unintended" }

        case "run_shell":
            let cmd = input["command"]?.stringValue ?? ""
            if cmd.isEmpty { return "Error: command is empty" }
            // Detect potentially dangerous commands
            let dangerous = ["rm -rf /", "mkfs", "dd if=", "> /dev/sd"]
            for d in dangerous {
                if cmd.contains(d) {
                    return "⚠ Dangerous command detected: '\(d)'"
                }
            }

        default:
            break
        }
        return nil
    }

    // MARK: - Analytics

    /// Recent error summary
    var errorSummary: String {
        let recent = recentErrors.suffix(10)
        if recent.isEmpty { return "No recent errors" }

        let byCat = Dictionary(grouping: recent) { $0.1.category }
        var lines = ["Recent errors (\(recent.count)):"]
        for (cat, errors) in byCat {
            lines.append("  \(cat): \(errors.count)")
        }
        lines.append("  Recovered: \(errorsRecovered), Failed: \(errorsFailed), Fallbacks: \(fallbacksUsed)")
        return lines.joined(separator: "\n")
    }

    /// Record an error for analytics
    func recordError(_ error: ClassifiedError) {
        recentErrors.append((Date(), error))
        // Keep last 50 errors
        if recentErrors.count > 50 {
            recentErrors = Array(recentErrors.suffix(50))
        }
    }

    // MARK: - Helpers

    private func findFallback(for toolName: String) -> RecoveryAction? {
        guard let chain = ErrorRecovery.fallbackChains.first(where: { $0.fromTool == toolName }) else {
            return nil
        }
        // Return a fallback action — actual input transformation happens at execution time
        return .fallbackTool(name: chain.toTool, input: [:])
    }

    /// Find and execute the best fallback for a failed tool
    func executeFallback(
        toolName: String,
        input: [String: AnyCodable],
        executor: ToolExecutor
    ) -> (ToolResult, String?)? {
        guard let chain = ErrorRecovery.fallbackChains.first(where: { $0.fromTool == toolName }) else {
            return nil
        }

        let transformedInput = chain.transformInput(input)
        fallbacksUsed += 1

        let (result, screenshot) = executor.execute(toolName: chain.toTool, input: transformedInput)
        if result.success {
            errorsRecovered += 1
        }
        return (result, screenshot)
    }
}
