import Foundation

// MARK: - Performance Analyzer
// Real-time latency tracking, bottleneck identification,
// and automatic optimization suggestions.

final class PerformanceAnalyzer: @unchecked Sendable {

    // MARK: - Types

    struct ToolTiming {
        let name: String
        let durationMs: Int
        let timestamp: Date
        let wasCached: Bool
        let wasParallel: Bool
    }

    struct IterationTiming {
        let iteration: Int
        let apiCallMs: Int
        let toolExecutionMs: Int
        let toolCount: Int
        let parallelCount: Int
        let cacheHits: Int
        let timestamp: Date
    }

    struct Bottleneck {
        let tool: String
        let avgMs: Int
        let callCount: Int
        let totalMs: Int
        let suggestion: String
    }

    struct PerformanceReport {
        let sessionDurationMs: Int
        let totalIterations: Int
        let totalToolCalls: Int
        let totalApiCalls: Int
        let avgIterationMs: Int
        let avgToolMs: Int
        let avgApiMs: Int
        let parallelExecutions: Int
        let cacheHitRate: Double
        let bottlenecks: [Bottleneck]
        let timeSavedMs: Int  // From caching + parallelism
    }

    // MARK: - State

    private let lock = NSLock()
    private var toolTimings: [ToolTiming] = []
    private var iterationTimings: [IterationTiming] = []
    private var sessionStart: Date = Date()

    // Per-tool aggregates
    private var toolDurations: [String: [Int]] = [:]  // tool -> [durationMs]
    private var totalApiMs: Int = 0
    private var apiCallCount: Int = 0
    private var parallelExecutions: Int = 0
    private var totalTimeSavedMs: Int = 0

    init() {
        self.sessionStart = Date()
    }

    // MARK: - Recording

    /// Record a single tool execution timing
    func recordToolTiming(name: String, durationMs: Int, wasCached: Bool, wasParallel: Bool) {
        let timing = ToolTiming(
            name: name, durationMs: durationMs,
            timestamp: Date(), wasCached: wasCached, wasParallel: wasParallel
        )

        lock.lock()
        toolTimings.append(timing)
        toolDurations[name, default: []].append(durationMs)
        if wasParallel { parallelExecutions += 1 }
        lock.unlock()
    }

    /// Record an API call round-trip time
    func recordApiCall(durationMs: Int) {
        lock.lock()
        totalApiMs += durationMs
        apiCallCount += 1
        lock.unlock()
    }

    /// Record a complete iteration's timing
    func recordIteration(
        iteration: Int,
        apiCallMs: Int,
        toolExecutionMs: Int,
        toolCount: Int,
        parallelCount: Int,
        cacheHits: Int
    ) {
        let timing = IterationTiming(
            iteration: iteration, apiCallMs: apiCallMs,
            toolExecutionMs: toolExecutionMs, toolCount: toolCount,
            parallelCount: parallelCount, cacheHits: cacheHits,
            timestamp: Date()
        )

        lock.lock()
        iterationTimings.append(timing)
        lock.unlock()
    }

    /// Record time saved through optimization (caching, parallelism)
    func recordTimeSaved(ms: Int) {
        lock.lock()
        totalTimeSavedMs += ms
        lock.unlock()
    }

    // MARK: - Analysis

    /// Identify the top bottleneck tools
    func identifyBottlenecks(top: Int = 5) -> [Bottleneck] {
        lock.lock()
        let durations = toolDurations
        lock.unlock()

        var bottlenecks: [Bottleneck] = []

        for (tool, times) in durations {
            guard !times.isEmpty else { continue }
            let avg = times.reduce(0, +) / times.count
            let total = times.reduce(0, +)

            let suggestion: String
            if avg > 500 {
                suggestion = "Consider caching or async execution"
            } else if avg > 200 {
                suggestion = "Candidate for parallel execution"
            } else if times.count > 10 && avg > 50 {
                suggestion = "High frequency — batch where possible"
            } else {
                suggestion = "Acceptable"
            }

            bottlenecks.append(Bottleneck(
                tool: tool, avgMs: avg, callCount: times.count,
                totalMs: total, suggestion: suggestion
            ))
        }

        return bottlenecks
            .sorted { $0.totalMs > $1.totalMs }
            .prefix(top)
            .map { $0 }
    }

    /// Generate a full performance report
    func generateReport() -> PerformanceReport {
        lock.lock()
        let tools = toolTimings
        let iterations = iterationTimings
        let apiMs = totalApiMs
        let apiCount = apiCallCount
        let parallel = parallelExecutions
        let saved = totalTimeSavedMs
        lock.unlock()

        let sessionMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
        let totalTools = tools.count
        let avgTool = totalTools > 0 ? tools.map { $0.durationMs }.reduce(0, +) / totalTools : 0
        let avgApi = apiCount > 0 ? apiMs / apiCount : 0
        let avgIteration = iterations.isEmpty ? 0 :
            iterations.map { $0.apiCallMs + $0.toolExecutionMs }.reduce(0, +) / iterations.count

        let cacheHits = tools.filter { $0.wasCached }.count
        let cacheRate = totalTools > 0 ? Double(cacheHits) / Double(totalTools) * 100 : 0

        return PerformanceReport(
            sessionDurationMs: sessionMs,
            totalIterations: iterations.count,
            totalToolCalls: totalTools,
            totalApiCalls: apiCount,
            avgIterationMs: avgIteration,
            avgToolMs: avgTool,
            avgApiMs: avgApi,
            parallelExecutions: parallel,
            cacheHitRate: cacheRate,
            bottlenecks: identifyBottlenecks(),
            timeSavedMs: saved
        )
    }

    // MARK: - Optimization Suggestions

    /// Get actionable optimization suggestions based on current metrics
    func getSuggestions() -> [String] {
        let report = generateReport()
        var suggestions: [String] = []

        // Check cache utilization
        if report.cacheHitRate < 10 && report.totalToolCalls > 5 {
            suggestions.append("Cache hit rate is \(String(format: "%.0f", report.cacheHitRate))% — enable predictive cache warming for read-only tools")
        }

        // Check parallelism
        if report.parallelExecutions == 0 && report.totalToolCalls > 3 {
            suggestions.append("No parallel tool execution detected — enable async pipeline for independent tools")
        }

        // Check for slow tools
        for bottleneck in report.bottlenecks.prefix(3) {
            if bottleneck.avgMs > 300 {
                suggestions.append("'\(bottleneck.tool)' averages \(bottleneck.avgMs)ms — \(bottleneck.suggestion)")
            }
        }

        // Check API latency
        if report.avgApiMs > 3000 {
            suggestions.append("API calls averaging \(report.avgApiMs)ms — consider response streaming or smaller context")
        }

        // Check iteration count
        if report.totalIterations > 15 {
            suggestions.append("High iteration count (\(report.totalIterations)) — use tool batching to reduce round-trips")
        }

        return suggestions
    }

    // MARK: - Display

    /// Compact stats line for verbose mode
    var shortStats: String {
        lock.lock()
        let toolCount = toolTimings.count
        let iterCount = iterationTimings.count
        let cached = toolTimings.filter { $0.wasCached }.count
        let parallel = parallelExecutions
        let saved = totalTimeSavedMs
        lock.unlock()

        return "Perf: \(toolCount) tools, \(iterCount) iters, \(cached) cached, \(parallel) parallel, ~\(saved)ms saved"
    }

    /// Detailed performance summary
    var detailedStats: String {
        let report = generateReport()
        var lines: [String] = []

        lines.append("Performance Analysis")
        lines.append("  Session: \(report.sessionDurationMs / 1000)s elapsed")
        lines.append("  Iterations: \(report.totalIterations) (avg \(report.avgIterationMs)ms)")
        lines.append("  API calls: \(report.totalApiCalls) (avg \(report.avgApiMs)ms)")
        lines.append("  Tool calls: \(report.totalToolCalls) (avg \(report.avgToolMs)ms)")
        lines.append("  Parallel: \(report.parallelExecutions) executions")
        lines.append("  Cache: \(String(format: "%.0f", report.cacheHitRate))% hit rate")
        lines.append("  Time saved: ~\(report.timeSavedMs)ms")

        if !report.bottlenecks.isEmpty {
            lines.append("  Bottlenecks:")
            for b in report.bottlenecks.prefix(3) {
                lines.append("    \(b.tool): \(b.avgMs)ms avg (\(b.callCount)x) — \(b.suggestion)")
            }
        }

        let suggestions = getSuggestions()
        if !suggestions.isEmpty {
            lines.append("  Suggestions:")
            for s in suggestions {
                lines.append("    → \(s)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Reset all metrics for a new session
    func reset() {
        lock.lock()
        toolTimings.removeAll()
        iterationTimings.removeAll()
        toolDurations.removeAll()
        totalApiMs = 0
        apiCallCount = 0
        parallelExecutions = 0
        totalTimeSavedMs = 0
        sessionStart = Date()
        lock.unlock()
    }
}
