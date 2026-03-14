import Foundation

// MARK: - Predictive Tool Orchestrator
// Tracks tool usage patterns across sessions, predicts next tools, caches results,
// and suggests batching opportunities to reduce iteration count.

final class ToolOrchestrator {

    // MARK: - Types

    /// A recorded tool invocation with timing and context
    struct ToolEvent {
        let name: String
        let timestamp: Date
        let durationMs: Int
        let success: Bool
        let hadScreenshot: Bool
    }

    /// Transition probability from one tool to another
    struct Transition: Codable {
        var count: Int
        var lastSeen: Date
    }

    /// Persisted pattern data (Markov chain + frequency stats)
    struct PatternData: Codable {
        /// Bigram transitions: "toolA" → ["toolB": count, "toolC": count]
        var bigrams: [String: [String: Transition]]
        /// Trigram transitions: "toolA→toolB" → ["toolC": count]
        var trigrams: [String: [String: Transition]]
        /// Total call counts per tool
        var frequency: [String: Int]
        /// Average duration per tool (ms)
        var avgDuration: [String: Int]
        /// Total sessions tracked
        var sessionsTracked: Int
        /// Tools that are always read-only (safe to cache)
        var readOnlyTools: Set<String>
    }

    /// Prediction result
    struct Prediction {
        let toolName: String
        let confidence: Double  // 0.0 - 1.0
        let source: String      // "bigram", "trigram", "frequency"
    }

    /// Cached tool result
    struct CachedResult {
        let result: ToolResult
        let screenshotBase64: String?
        let timestamp: Date
        let inputHash: String
    }

    /// Batching suggestion
    struct BatchHint {
        let tools: [String]
        let reason: String
        let confidence: Double
    }

    // MARK: - Constants

    /// Tools whose results are cacheable (read-only, deterministic)
    static let cacheableTools: Set<String> = [
        "list_apps", "get_frontmost_app", "list_windows", "get_screen_size",
        "read_clipboard", "read_file", "list_directory", "file_info",
        "read_memory", "read_program", "read_system_prompt", "read_improvement_log",
        "list_tasks", "spotlight_search"
    ]

    /// Tools that invalidate specific caches when called
    static let cacheInvalidators: [String: Set<String>] = [
        "write_file":       ["read_file", "list_directory", "file_info"],
        "write_clipboard":  ["read_clipboard"],
        "save_memory":      ["read_memory"],
        "edit_program":     ["read_program"],
        "edit_system_prompt": ["read_system_prompt"],
        "open_app":         ["list_apps", "get_frontmost_app", "list_windows"],
        "activate_app":     ["get_frontmost_app"],
        "click_element":    ["list_apps", "get_frontmost_app", "list_windows"],
        "schedule_task":    ["list_tasks"],
        "cancel_task":      ["list_tasks"],
    ]

    /// Common tool sequences that should be batched
    static let batchPatterns: [(pattern: [String], suggestion: [String], reason: String)] = [
        // Screenshot + UI elements should always be batched
        (["take_screenshot"], ["take_screenshot", "get_ui_elements"],
         "Batch screenshot + UI elements in one turn"),
        // Multiple file reads can be batched
        (["read_file"], ["read_file"],
         "Multiple file reads can be batched with run_subagents"),
        // App inspection pattern
        (["activate_app"], ["activate_app", "take_screenshot", "get_ui_elements"],
         "Batch app activation with screenshot + UI inspection"),
    ]

    /// Cache TTL by tool type (seconds)
    static let cacheTTL: [String: TimeInterval] = [
        "list_apps": 5,         // Apps change frequently
        "get_frontmost_app": 2, // Changes with every activation
        "list_windows": 5,
        "get_screen_size": 300, // Rarely changes
        "read_clipboard": 10,
        "read_file": 30,        // Files change less often
        "list_directory": 30,
        "file_info": 60,
        "read_memory": 60,
        "read_program": 120,
        "spotlight_search": 30,
    ]

    static let defaultTTL: TimeInterval = 15

    // MARK: - State

    private var patterns: PatternData
    private var currentSession: [ToolEvent] = []
    private var resultCache: [String: CachedResult] = [:]  // key: "toolName:inputHash"
    private var consecutiveSingleCalls: Int = 0  // Track single tool calls for batching hints
    private let persistPath: String

    // MARK: - Stats (current session)

    private(set) var cacheHits: Int = 0
    private(set) var cacheMisses: Int = 0
    private(set) var predictionsCorrect: Int = 0
    private(set) var predictionsMade: Int = 0
    private(set) var batchHintsGiven: Int = 0

    var cacheHitRate: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) * 100.0 : 0
    }

    var predictionAccuracy: Double {
        return predictionsMade > 0 ? Double(predictionsCorrect) / Double(predictionsMade) * 100.0 : 0
    }

    // MARK: - Init

    init() {
        let dir = NSHomeDirectory() + "/.desktop-agent"
        self.persistPath = dir + "/tool-patterns.json"
        self.patterns = ToolOrchestrator.loadPatterns(from: dir + "/tool-patterns.json")
    }

    // MARK: - Pattern Recording

    /// Record a tool execution event and update patterns
    func recordToolCall(name: String, input: [String: AnyCodable], durationMs: Int, success: Bool, hadScreenshot: Bool) {
        let event = ToolEvent(
            name: name, timestamp: Date(),
            durationMs: durationMs, success: success, hadScreenshot: hadScreenshot
        )
        currentSession.append(event)

        // Update frequency
        patterns.frequency[name, default: 0] += 1

        // Update average duration (running average, overflow-safe)
        let oldAvg = patterns.avgDuration[name] ?? durationMs
        let count = max(patterns.frequency[name] ?? 1, 1)
        patterns.avgDuration[name] = oldAvg &+ (durationMs &- oldAvg) / count

        // Update bigrams
        if currentSession.count >= 2 {
            let prev = currentSession[currentSession.count - 2].name
            if patterns.bigrams[prev] == nil { patterns.bigrams[prev] = [:] }
            let existing = patterns.bigrams[prev]?[name] ?? Transition(count: 0, lastSeen: Date())
            patterns.bigrams[prev]?[name] = Transition(count: existing.count + 1, lastSeen: Date())
        }

        // Update trigrams
        if currentSession.count >= 3 {
            let prev2 = currentSession[currentSession.count - 3].name
            let prev1 = currentSession[currentSession.count - 2].name
            let key = "\(prev2)→\(prev1)"
            if patterns.trigrams[key] == nil { patterns.trigrams[key] = [:] }
            let existing = patterns.trigrams[key]?[name] ?? Transition(count: 0, lastSeen: Date())
            patterns.trigrams[key]?[name] = Transition(count: existing.count + 1, lastSeen: Date())
        }

        // Invalidate caches when state-changing tools execute
        invalidateCaches(forTool: name)
    }

    // MARK: - Prediction

    /// Predict the next likely tools based on current sequence
    func predictNextTools(maxResults: Int = 3) -> [Prediction] {
        guard !currentSession.isEmpty else { return [] }

        var predictions: [Prediction] = []
        let last = currentSession.last!.name

        // Trigram prediction (highest confidence)
        if currentSession.count >= 2 {
            let prev = currentSession[currentSession.count - 2].name
            let key = "\(prev)→\(last)"
            if let transitions = patterns.trigrams[key] {
                let total = transitions.values.reduce(0) { $0 + $1.count }
                for (tool, trans) in transitions.sorted(by: { $0.value.count > $1.value.count }).prefix(maxResults) {
                    let conf = Double(trans.count) / Double(total) * 0.95  // Max 0.95 for trigrams
                    predictions.append(Prediction(toolName: tool, confidence: conf, source: "trigram"))
                }
            }
        }

        // Bigram prediction
        if let transitions = patterns.bigrams[last] {
            let total = transitions.values.reduce(0) { $0 + $1.count }
            for (tool, trans) in transitions.sorted(by: { $0.value.count > $1.value.count }).prefix(maxResults) {
                // Don't duplicate trigram predictions
                if !predictions.contains(where: { $0.toolName == tool }) {
                    let conf = Double(trans.count) / Double(total) * 0.7  // Max 0.7 for bigrams
                    predictions.append(Prediction(toolName: tool, confidence: conf, source: "bigram"))
                }
            }
        }

        // Frequency-based fallback
        if predictions.isEmpty {
            let sorted = patterns.frequency.sorted { $0.value > $1.value }
            for (tool, count) in sorted.prefix(maxResults) {
                let totalCalls = patterns.frequency.values.reduce(0, +)
                let conf = Double(count) / Double(totalCalls) * 0.3  // Max 0.3 for frequency
                predictions.append(Prediction(toolName: tool, confidence: conf, source: "frequency"))
            }
        }

        predictionsMade += 1
        return predictions.sorted { $0.confidence > $1.confidence }.prefix(maxResults).map { $0 }
    }

    /// Check if a prediction was correct (call after the actual tool executes)
    func validatePrediction(actualTool: String) {
        // Check if the last prediction included this tool
        let predictions = predictNextTools()
        if predictions.contains(where: { $0.toolName == actualTool }) {
            predictionsCorrect += 1
        }
    }

    // MARK: - Result Caching

    /// Try to get a cached result for a tool call
    func getCachedResult(toolName: String, input: [String: AnyCodable]) -> (ToolResult, String?)? {
        guard ToolOrchestrator.cacheableTools.contains(toolName) else { return nil }

        let key = cacheKey(toolName: toolName, input: input)
        guard let cached = resultCache[key] else {
            cacheMisses += 1
            return nil
        }

        // Check TTL
        let ttl = ToolOrchestrator.cacheTTL[toolName] ?? ToolOrchestrator.defaultTTL
        if Date().timeIntervalSince(cached.timestamp) > ttl {
            resultCache.removeValue(forKey: key)
            cacheMisses += 1
            return nil
        }

        cacheHits += 1
        return (cached.result, cached.screenshotBase64)
    }

    /// Store a tool result in cache
    func cacheResult(toolName: String, input: [String: AnyCodable], result: ToolResult, screenshotBase64: String?) {
        guard ToolOrchestrator.cacheableTools.contains(toolName), result.success else { return }

        let key = cacheKey(toolName: toolName, input: input)
        resultCache[key] = CachedResult(
            result: result,
            screenshotBase64: screenshotBase64,
            timestamp: Date(),
            inputHash: inputHash(input)
        )
    }

    /// Invalidate caches when a state-changing tool runs
    private func invalidateCaches(forTool toolName: String) {
        guard let invalidated = ToolOrchestrator.cacheInvalidators[toolName] else { return }
        resultCache = resultCache.filter { key, _ in
            !invalidated.contains(where: { key.hasPrefix($0 + ":") })
        }
    }

    /// Clear all caches
    func clearCache() {
        resultCache.removeAll()
    }

    // MARK: - Batching Hints

    /// Check if the AI is making suboptimal single tool calls that could be batched
    func checkBatchingOpportunity(currentTools: [String]) -> BatchHint? {
        // Only hint if the AI called exactly 1 tool
        guard currentTools.count == 1, let tool = currentTools.first else {
            consecutiveSingleCalls = 0
            return nil
        }

        consecutiveSingleCalls += 1

        // Check against known batch patterns
        for pattern in ToolOrchestrator.batchPatterns {
            if pattern.pattern.contains(tool) && currentTools != pattern.suggestion {
                // Only suggest if we've seen the full pattern before in history
                let patternKey = pattern.suggestion.prefix(2).joined(separator: "→")
                if let trigram = patterns.trigrams[patternKey], !trigram.isEmpty {
                    batchHintsGiven += 1
                    return BatchHint(
                        tools: pattern.suggestion,
                        reason: pattern.reason,
                        confidence: min(Double(consecutiveSingleCalls) * 0.2, 0.8)
                    )
                }
            }
        }

        // Check bigram data for commonly co-occurring tools
        if let transitions = patterns.bigrams[tool] {
            let total = transitions.values.reduce(0) { $0 + $1.count }
            if let (nextTool, trans) = transitions.max(by: { $0.value.count < $1.value.count }),
               Double(trans.count) / Double(total) > 0.6 {
                // This tool is almost always followed by another specific tool
                batchHintsGiven += 1
                return BatchHint(
                    tools: [tool, nextTool],
                    reason: "'\(tool)' is usually followed by '\(nextTool)' — consider batching",
                    confidence: Double(trans.count) / Double(total)
                )
            }
        }

        return nil
    }

    // MARK: - MCP Pre-warming

    /// Get MCP servers that should be pre-warmed based on predicted tool usage
    func mcpServersToPrewarm() -> [String] {
        let predictions = predictNextTools(maxResults: 5)
        return predictions
            .filter { $0.toolName.hasPrefix("mcp_") && $0.confidence > 0.5 }
            .compactMap { prediction in
                // Extract server name from "mcp_servername_toolname"
                let parts = prediction.toolName.split(separator: "_")
                return parts.count >= 2 ? String(parts[1]) : nil
            }
    }

    // MARK: - Analytics

    /// Get orchestrator stats for display
    var stats: String {
        let totalCalls = patterns.frequency.values.reduce(0, +)
        let uniqueTools = patterns.frequency.count
        let topTools = patterns.frequency.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        var lines: [String] = []
        lines.append("Tool Orchestrator Stats")
        lines.append("  Patterns: \(totalCalls) calls, \(uniqueTools) unique tools, \(patterns.sessionsTracked) sessions")
        lines.append("  Top tools: \(topTools)")
        lines.append("  Cache: \(cacheHits) hits / \(cacheHits + cacheMisses) lookups (\(String(format: "%.0f", cacheHitRate))%)")
        lines.append("  Predictions: \(predictionsCorrect)/\(predictionsMade) correct (\(String(format: "%.0f", predictionAccuracy))%)")
        lines.append("  Batch hints given: \(batchHintsGiven)")
        lines.append("  Result cache entries: \(resultCache.count)")

        // Show current predictions
        let predictions = predictNextTools()
        if !predictions.isEmpty {
            lines.append("  Next predicted: " + predictions.map {
                "\($0.toolName) (\(String(format: "%.0f", $0.confidence * 100))%, \($0.source))"
            }.joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }

    /// Get detailed pattern data for the AI to reason about
    func getPatternInsights() -> String {
        var insights: [String] = []

        // Most common sequences
        let topBigrams = patterns.bigrams.flatMap { from, tos in
            tos.map { (from: from, to: $0.key, count: $0.value.count) }
        }.sorted { $0.count > $1.count }.prefix(10)

        if !topBigrams.isEmpty {
            insights.append("Common tool sequences:")
            for b in topBigrams {
                insights.append("  \(b.from) → \(b.to) (\(b.count)x)")
            }
        }

        // Slowest tools
        let slowest = patterns.avgDuration.sorted { $0.value > $1.value }.prefix(5)
        if !slowest.isEmpty {
            insights.append("\nSlowest tools (avg ms):")
            for (tool, ms) in slowest {
                insights.append("  \(tool): \(ms)ms")
            }
        }

        // Single-call inefficiency detection
        if consecutiveSingleCalls > 3 {
            insights.append("\n⚠ Detected \(consecutiveSingleCalls) consecutive single-tool calls — batching would improve speed")
        }

        return insights.joined(separator: "\n")
    }

    // MARK: - Persistence

    /// Save patterns to disk (call at end of session)
    func savePatterns() {
        patterns.sessionsTracked += 1

        // Decay old transitions (reduce counts for entries not seen recently)
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)  // 7 days
        for (from, tos) in patterns.bigrams {
            for (to, trans) in tos {
                if trans.lastSeen < cutoff {
                    // Halve the count for stale entries
                    patterns.bigrams[from]?[to]?.count = max(1, trans.count / 2)
                }
            }
        }

        do {
            let data = try JSONEncoder().encode(patterns)
            let dir = (persistPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: persistPath))
        } catch {
            // Silent failure — patterns are a nice-to-have
        }
    }

    /// Reset session state (keep cross-session patterns)
    func resetSession() {
        currentSession.removeAll()
        resultCache.removeAll()
        cacheHits = 0
        cacheMisses = 0
        predictionsCorrect = 0
        predictionsMade = 0
        batchHintsGiven = 0
        consecutiveSingleCalls = 0
    }

    // MARK: - Helpers

    private func cacheKey(toolName: String, input: [String: AnyCodable]) -> String {
        "\(toolName):\(inputHash(input))"
    }

    private func inputHash(_ input: [String: AnyCodable]) -> String {
        // Stable hash of input parameters
        let sorted = input.sorted { $0.key < $1.key }
        let str = sorted.map { "\($0.key)=\($0.value.value)" }.joined(separator: "&")
        // Simple hash — not cryptographic, just for cache keys
        var hash: UInt64 = 5381
        for byte in str.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private static func loadPatterns(from path: String) -> PatternData {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let patterns = try? JSONDecoder().decode(PatternData.self, from: data) else {
            return PatternData(
                bigrams: [:], trigrams: [:], frequency: [:],
                avgDuration: [:], sessionsTracked: 0, readOnlyTools: cacheableTools
            )
        }
        return patterns
    }
}
