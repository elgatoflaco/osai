import Foundation

// MARK: - Response Optimizer
// Token-efficient tool result processing with smart truncation,
// compressed output formats, and incremental response building.

final class ResponseOptimizer {

    // MARK: - Configuration

    struct Config {
        /// Max chars for tool output before truncation
        var maxToolOutputChars: Int = 8000
        /// Max lines for file content
        var maxFileLines: Int = 200
        /// Max entries for directory listings
        var maxDirEntries: Int = 100
        /// Max chars for shell output
        var maxShellOutput: Int = 4000
        /// Whether to compress repetitive output
        var compressRepetitive: Bool = true
        /// Whether to summarize large outputs
        var summarizeLarge: Bool = true
    }

    private var config: Config

    // MARK: - Stats

    private(set) var totalInputChars: Int = 0
    private(set) var totalOutputChars: Int = 0
    private(set) var truncations: Int = 0

    var compressionRatio: Double {
        totalInputChars > 0 ? Double(totalOutputChars) / Double(totalInputChars) : 1.0
    }

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Tool Result Optimization

    /// Optimize a tool result to reduce token usage
    func optimize(toolName: String, result: ToolResult) -> ToolResult {
        let original = result.output
        totalInputChars += original.count

        let optimized: String
        switch toolName {
        case "read_file":
            optimized = optimizeFileContent(original)
        case "list_directory":
            optimized = optimizeDirectoryListing(original)
        case "run_shell":
            optimized = optimizeShellOutput(original)
        case "get_ui_elements":
            optimized = optimizeUIElements(original)
        case "list_apps":
            optimized = optimizeAppList(original)
        case "list_windows":
            optimized = optimizeWindowList(original)
        case "spotlight_search":
            optimized = optimizeSearchResults(original)
        default:
            optimized = genericOptimize(original)
        }

        totalOutputChars += optimized.count

        if optimized.count < original.count {
            truncations += 1
        }

        return ToolResult(success: result.success, output: optimized, screenshot: result.screenshot)
    }

    // MARK: - Tool-Specific Optimizers

    /// Truncate file content to max lines, keeping head + tail
    private func optimizeFileContent(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > config.maxFileLines else {
            return genericOptimize(content)
        }

        let headCount = config.maxFileLines * 2 / 3
        let tailCount = config.maxFileLines / 3
        let head = lines.prefix(headCount).joined(separator: "\n")
        let tail = lines.suffix(tailCount).joined(separator: "\n")
        let omitted = lines.count - headCount - tailCount

        return "\(head)\n\n... [\(omitted) lines omitted] ...\n\n\(tail)"
    }

    /// Limit directory entries and remove redundant info
    private func optimizeDirectoryListing(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > config.maxDirEntries else {
            return genericOptimize(content)
        }

        let kept = lines.prefix(config.maxDirEntries).joined(separator: "\n")
        let omitted = lines.count - config.maxDirEntries
        return "\(kept)\n... [\(omitted) more entries]"
    }

    /// Truncate shell output, keeping head + tail for context
    private func optimizeShellOutput(_ content: String) -> String {
        guard content.count > config.maxShellOutput else { return content }

        let headSize = config.maxShellOutput * 2 / 3
        let tailSize = config.maxShellOutput / 3

        let head = String(content.prefix(headSize))
        let tail = String(content.suffix(tailSize))
        let omittedChars = content.count - headSize - tailSize

        return "\(head)\n\n... [\(omittedChars) chars omitted] ...\n\n\(tail)"
    }

    /// Compress UI element trees by removing deep/repetitive nodes
    private func optimizeUIElements(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 150 else { return genericOptimize(content) }

        // Keep elements up to depth 3, summarize deeper
        var optimized: [String] = []
        var deepCount = 0

        for line in lines {
            let depth = line.prefix(while: { $0 == " " }).count / 2
            if depth <= 3 {
                if deepCount > 0 {
                    optimized.append("      ... [\(deepCount) deep elements omitted]")
                    deepCount = 0
                }
                optimized.append(String(line))
            } else {
                deepCount += 1
            }
        }

        if deepCount > 0 {
            optimized.append("      ... [\(deepCount) deep elements omitted]")
        }

        return optimized.joined(separator: "\n")
    }

    /// Remove redundant fields from app list
    private func optimizeAppList(_ content: String) -> String {
        genericOptimize(content)
    }

    /// Remove redundant window info
    private func optimizeWindowList(_ content: String) -> String {
        genericOptimize(content)
    }

    /// Limit search results
    private func optimizeSearchResults(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 50 else { return genericOptimize(content) }

        let kept = lines.prefix(50).joined(separator: "\n")
        return "\(kept)\n... [\(lines.count - 50) more results]"
    }

    /// Generic truncation for any output
    private func genericOptimize(_ content: String) -> String {
        guard content.count > config.maxToolOutputChars else { return content }

        let headSize = config.maxToolOutputChars * 3 / 4
        let tailSize = config.maxToolOutputChars / 4

        let head = String(content.prefix(headSize))
        let tail = String(content.suffix(tailSize))
        let omitted = content.count - headSize - tailSize

        return "\(head)\n\n... [\(omitted) chars truncated] ...\n\n\(tail)"
    }

    // MARK: - Batch Result Compression

    /// Compress multiple tool results into a more token-efficient format
    func compressBatchResults(_ results: [(name: String, output: String)]) -> String {
        guard results.count > 1 else {
            return results.first.map { "\($0.name): \($0.output)" } ?? ""
        }

        var compressed: [String] = []
        for (name, output) in results {
            let optimized = genericOptimize(output)
            compressed.append("### \(name)\n\(optimized)")
        }
        return compressed.joined(separator: "\n\n")
    }

    // MARK: - Analytics

    var statsDescription: String {
        let ratio = String(format: "%.0f", compressionRatio * 100)
        return "Optimizer: \(totalInputChars) → \(totalOutputChars) chars (\(ratio)%), \(truncations) truncations"
    }

    func reset() {
        totalInputChars = 0
        totalOutputChars = 0
        truncations = 0
    }
}
