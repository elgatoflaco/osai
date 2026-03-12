import Foundation

// MARK: - Async Tool Pipeline
// Enables parallel execution of independent tools within a single Claude response.
// Tools are classified as parallelizable (read-only) or sequential (state-changing),
// then executed concurrently where safe, with early result return for fast tools.

final class AsyncToolPipeline {

    // MARK: - Types

    struct ToolCall: Sendable {
        let id: String
        let name: String
        let input: [String: AnyCodable]
    }

    struct PipelineResult: Sendable {
        let id: String
        let name: String
        let result: ToolResult
        let screenshotBase64: String?
        let durationMs: Int
        let wasCached: Bool
    }

    enum ExecutionStrategy {
        case parallel      // All tools can run concurrently
        case sequential    // Must run in order
        case mixed         // Some parallel, some sequential
    }

    // MARK: - Tool Classification

    /// Tools that are safe to run in parallel (read-only, no side effects)
    static let parallelSafe: Set<String> = [
        "read_file", "list_directory", "file_info", "read_clipboard",
        "list_apps", "get_frontmost_app", "list_windows", "get_screen_size",
        "read_memory", "spotlight_search", "read_program", "read_system_prompt",
        "read_improvement_log", "list_tasks", "orchestrator_stats",
        "orchestrator_insights", "adaptive_stats", "ui_cache_lookup"
    ]

    /// Tools that modify state and must be executed sequentially
    static let stateChanging: Set<String> = [
        "click_element", "type_text", "press_key", "scroll", "drag",
        "mouse_move", "write_file", "write_clipboard", "save_memory",
        "run_shell", "run_applescript", "open_app", "activate_app",
        "open_url", "move_window", "resize_window", "edit_program",
        "edit_system_prompt", "schedule_task", "cancel_task",
        "configure_gateway", "import_gateway_config"
    ]

    /// Tools that need special handling (delegated to AgentLoop)
    static let delegated: Set<String> = [
        "run_subagents", "mcp_install", "mcp_search", "claude_code",
        "schedule_task", "cancel_task", "run_task",
        "configure_gateway", "import_gateway_config"
    ]

    // MARK: - Strategy Analysis

    /// Determine the best execution strategy for a batch of tool calls
    static func analyzeStrategy(tools: [ToolCall]) -> ExecutionStrategy {
        guard tools.count > 1 else { return .sequential }

        let hasSequential = tools.contains { stateChanging.contains($0.name) || delegated.contains($0.name) }
        let hasParallel = tools.contains { parallelSafe.contains($0.name) }

        if !hasSequential { return .parallel }
        if !hasParallel { return .sequential }
        return .mixed
    }

    /// Partition tools into parallel and sequential groups, preserving order for sequential tools
    static func partition(tools: [ToolCall]) -> (parallel: [ToolCall], sequential: [ToolCall]) {
        var parallel: [ToolCall] = []
        var sequential: [ToolCall] = []

        for tool in tools {
            if parallelSafe.contains(tool.name) && !delegated.contains(tool.name) {
                parallel.append(tool)
            } else {
                sequential.append(tool)
            }
        }

        return (parallel, sequential)
    }

    // MARK: - Parallel Execution

    /// Execute multiple independent tools concurrently
    static func executeParallel(
        tools: [ToolCall],
        executor: ToolExecutor,
        orchestrator: ToolOrchestrator,
        verbose: Bool = false
    ) async -> [PipelineResult] {
        guard !tools.isEmpty else { return [] }

        if tools.count == 1 {
            return [executeSingle(tool: tools[0], executor: executor, orchestrator: orchestrator)]
        }

        let results: [PipelineResult] = await withTaskGroup(of: PipelineResult.self) { group in
            for tool in tools {
                group.addTask {
                    return executeSingle(tool: tool, executor: executor, orchestrator: orchestrator)
                }
            }

            var collected: [PipelineResult] = []
            collected.reserveCapacity(tools.count)
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Restore original order (task group returns in completion order)
        let idOrder = tools.map { $0.id }
        return results.sorted { a, b in
            (idOrder.firstIndex(of: a.id) ?? 0) < (idOrder.firstIndex(of: b.id) ?? 0)
        }
    }

    /// Execute a mixed batch: parallel tools first, then sequential tools in order
    static func executeMixed(
        tools: [ToolCall],
        executor: ToolExecutor,
        orchestrator: ToolOrchestrator,
        verbose: Bool = false
    ) async -> [PipelineResult] {
        let (parallel, sequential) = partition(tools: tools)
        var allResults: [PipelineResult] = []

        // Run parallel tools concurrently
        if !parallel.isEmpty {
            if verbose {
                printColored("    ⚡ Executing \(parallel.count) tools in parallel", color: .cyan)
            }
            let parallelResults = await executeParallel(
                tools: parallel, executor: executor,
                orchestrator: orchestrator, verbose: verbose
            )
            allResults.append(contentsOf: parallelResults)
        }

        // Run sequential tools in order
        for tool in sequential {
            let result = executeSingle(tool: tool, executor: executor, orchestrator: orchestrator)
            allResults.append(result)
        }

        // Restore original order
        let idOrder = tools.map { $0.id }
        return allResults.sorted { a, b in
            (idOrder.firstIndex(of: a.id) ?? 0) < (idOrder.firstIndex(of: b.id) ?? 0)
        }
    }

    // MARK: - Single Tool Execution

    private static func executeSingle(
        tool: ToolCall,
        executor: ToolExecutor,
        orchestrator: ToolOrchestrator
    ) -> PipelineResult {
        let startTime = DispatchTime.now()
        // Check cache first
        if let cached = orchestrator.getCachedResult(toolName: tool.name, input: tool.input) {
            let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            return PipelineResult(
                id: tool.id, name: tool.name,
                result: cached.0, screenshotBase64: cached.1,
                durationMs: Int(elapsed / 1_000_000), wasCached: true
            )
        }

        // Execute
        let execResult = executor.execute(toolName: tool.name, input: tool.input)

        // Cache result
        orchestrator.cacheResult(
            toolName: tool.name, input: tool.input,
            result: execResult.result, screenshotBase64: execResult.screenshotBase64
        )

        let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let durationMs = Int(elapsed / 1_000_000)

        // Record timing
        orchestrator.recordToolCall(
            name: tool.name, input: tool.input, durationMs: durationMs,
            success: execResult.result.success, hadScreenshot: execResult.screenshotBase64 != nil
        )

        return PipelineResult(
            id: tool.id, name: tool.name,
            result: execResult.result, screenshotBase64: execResult.screenshotBase64,
            durationMs: durationMs, wasCached: false
        )
    }

    // MARK: - Pipeline Stats

    struct PipelineStats {
        let totalTools: Int
        let parallelCount: Int
        let sequentialCount: Int
        let totalDurationMs: Int
        let savedMs: Int  // Estimated time saved via parallelism
        let cacheHits: Int

        var description: String {
            var parts: [String] = []
            parts.append("\(totalTools) tools")
            if parallelCount > 0 {
                parts.append("\(parallelCount) parallel")
            }
            if cacheHits > 0 {
                parts.append("\(cacheHits) cached")
            }
            if savedMs > 0 {
                parts.append("~\(savedMs)ms saved")
            }
            return parts.joined(separator: ", ")
        }
    }

    /// Calculate stats for a completed pipeline run
    static func computeStats(results: [PipelineResult], tools: [ToolCall]) -> PipelineStats {
        let (parallel, sequential) = partition(tools: tools)
        let totalDuration = results.map { $0.durationMs }.reduce(0, +)
        let maxParallelDuration = results
            .filter { r in parallel.contains { $0.id == r.id } }
            .map { $0.durationMs }
            .max() ?? 0
        let sumParallelDuration = results
            .filter { r in parallel.contains { $0.id == r.id } }
            .map { $0.durationMs }
            .reduce(0, +)
        let savedMs = max(0, sumParallelDuration - maxParallelDuration)
        let cacheHits = results.filter { $0.wasCached }.count

        return PipelineStats(
            totalTools: tools.count,
            parallelCount: parallel.count,
            sequentialCount: sequential.count,
            totalDurationMs: totalDuration,
            savedMs: savedMs,
            cacheHits: cacheHits
        )
    }
}
