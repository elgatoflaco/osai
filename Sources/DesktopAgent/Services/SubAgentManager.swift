import Foundation

// MARK: - Sub-Agent Manager
// Coordinates concurrent sub-agent spawning with shared context streaming,
// result aggregation, and resource pooling.

final class SubAgentManager: @unchecked Sendable {

    // MARK: - Types

    struct AgentSlot {
        let id: String
        let type: SubAgentType
        var status: AgentStatus
        let startTime: Date
        var endTime: Date?
    }

    enum AgentStatus: String {
        case queued
        case running
        case completed
        case failed
    }

    struct AggregatedResult {
        let results: [SubTaskResult]
        let totalDuration: TimeInterval
        let wallClockDuration: TimeInterval  // Actual elapsed (parallel benefit)
        let concurrencyFactor: Double        // How much parallelism we achieved
        let successRate: Double
    }

    // MARK: - Configuration

    private let maxConcurrency: Int
    private let config: AgentConfig
    private let mcpManager: MCPManager?

    // MARK: - State

    private let lock = NSLock()
    private var activeSlots: [String: AgentSlot] = [:]
    private var completedCount: Int = 0
    private var totalSpawned: Int = 0
    private var totalDuration: TimeInterval = 0

    // Shared context buffer for streaming context between agents
    private var sharedContext: [String: String] = [:]

    init(config: AgentConfig, mcpManager: MCPManager? = nil, maxConcurrency: Int = 5) {
        self.config = config
        self.mcpManager = mcpManager
        self.maxConcurrency = maxConcurrency
    }

    // MARK: - Concurrent Execution

    /// Run multiple sub-tasks with concurrency limiting and shared context
    func runConcurrent(
        tasks: [SubTask],
        tools: [ClaudeTool],
        parentContext: String? = nil
    ) async -> AggregatedResult {
        let wallStart = Date()

        printColored("  🔀 SubAgentManager: launching \(tasks.count) agents (max \(maxConcurrency) concurrent)...", color: .magenta)

        // Register all slots
        for task in tasks {
            lock.lock()
            activeSlots[task.id] = AgentSlot(
                id: task.id, type: task.type,
                status: .queued, startTime: Date()
            )
            totalSpawned += 1
            lock.unlock()
        }

        let progress = SubAgentProgress(total: tasks.count)

        // Use a semaphore-like pattern with task groups for concurrency limiting
        let results: [SubTaskResult] = await withTaskGroup(of: SubTaskResult.self) { group in
            // Concurrency limiter via a simple counter
            let semaphore = AsyncSemaphore(limit: maxConcurrency)

            for task in tasks {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    self.updateSlot(id: task.id, status: .running)
                    progress.update(id: task.id, status: "⏳ running...")

                    // Build context: parent context + any shared results from completed agents
                    var fullContext = parentContext ?? ""
                    let shared = self.getSharedContext()
                    if !shared.isEmpty {
                        fullContext += "\n\n## Results from other agents:\n" + shared
                    }

                    let executor = SubAgentExecutor(
                        config: self.config,
                        mcpManager: self.mcpManager,
                        parentContext: fullContext.isEmpty ? nil : fullContext,
                        maxConcurrency: 1  // Sub-agents don't spawn more sub-agents
                    )

                    let result = await executor.runParallel(tasks: [task], tools: tools).first
                        ?? SubTaskResult(
                            id: task.id, description: task.description,
                            success: false, output: "Failed to execute",
                            type: task.type, iterations: 0, duration: 0
                        )

                    // Share result context with other running agents
                    self.addSharedContext(
                        id: task.id,
                        context: "[\(task.id)] \(task.description): \(String(result.output.prefix(500)))"
                    )

                    let finalStatus: AgentStatus = result.success ? .completed : .failed
                    self.updateSlot(id: task.id, status: finalStatus)

                    let preview = String(result.output.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                    progress.complete(id: task.id, success: result.success, preview: preview)

                    return result
                }
            }

            var collected: [SubTaskResult] = []
            collected.reserveCapacity(tasks.count)
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        progress.finish()

        let wallDuration = Date().timeIntervalSince(wallStart)
        let totalTaskDuration = results.map { $0.duration }.reduce(0, +)
        let concurrencyFactor = wallDuration > 0 ? totalTaskDuration / wallDuration : 1.0
        let successRate = results.isEmpty ? 0 : Double(results.filter { $0.success }.count) / Double(results.count)

        // Update cumulative stats
        lock.lock()
        completedCount += results.count
        totalDuration += wallDuration
        lock.unlock()

        // Print summary
        let succeeded = results.filter { $0.success }.count
        printColored("  ✓ \(succeeded)/\(results.count) agents completed in \(String(format: "%.1f", wallDuration))s (concurrency factor: \(String(format: "%.1fx", concurrencyFactor)))", color: .green)

        return AggregatedResult(
            results: results,
            totalDuration: totalTaskDuration,
            wallClockDuration: wallDuration,
            concurrencyFactor: concurrencyFactor,
            successRate: successRate
        )
    }

    // MARK: - Shared Context

    private func addSharedContext(id: String, context: String) {
        lock.lock()
        sharedContext[id] = context
        lock.unlock()
    }

    private func getSharedContext() -> String {
        lock.lock()
        let ctx = sharedContext.values.joined(separator: "\n")
        lock.unlock()
        return ctx
    }

    private func updateSlot(id: String, status: AgentStatus) {
        lock.lock()
        activeSlots[id]?.status = status
        if status == .completed || status == .failed {
            activeSlots[id]?.endTime = Date()
        }
        lock.unlock()
    }

    // MARK: - Analytics

    var statsDescription: String {
        lock.lock()
        let spawned = totalSpawned
        let completed = completedCount
        let active = activeSlots.filter { $0.value.status == .running }.count
        let duration = totalDuration
        lock.unlock()

        return "SubAgents: \(spawned) spawned, \(completed) completed, \(active) active, \(String(format: "%.1f", duration))s total"
    }

    /// Reset shared context between top-level requests
    func resetContext() {
        lock.lock()
        sharedContext.removeAll()
        activeSlots.removeAll()
        lock.unlock()
    }
}

// MARK: - Async Semaphore (concurrency limiter)

actor AsyncSemaphore {
    private let limit: Int
    private var current: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func wait() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        } else {
            current -= 1
        }
    }
}
