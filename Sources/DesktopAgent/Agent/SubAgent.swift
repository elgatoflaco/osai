import Foundation

// MARK: - Sub-Agent System for Parallel Execution

/// Types of sub-agents with different system prompts and tool scopes
enum SubAgentType: String, CaseIterable {
    case general      // Full tool access, general purpose
    case explore      // File/shell focused — fast research
    case analyze      // Read-only analysis — no writes, no GUI
    case execute      // Action-focused — GUI, shell, AppleScript

    var systemPrompt: String {
        switch self {
        case .general:
            return """
            You are a focused sub-agent executing a specific task. Be concise and efficient.
            Complete the task and return the result. Do not ask questions — just do your best.
            If you need information from the system, use the available tools.
            Keep your final response focused on the task result only.
            """
        case .explore:
            return """
            You are a fast exploration sub-agent. Your job is to find files, read code, search content, and report back.
            Use run_shell (ls, cat, find, grep), read_file, list_directory, spotlight_search, and file_info.
            Do NOT take screenshots, click, type, or modify anything. Just read and report.
            Be extremely concise — return only the relevant findings.
            """
        case .analyze:
            return """
            You are an analysis sub-agent. Read files, examine data, and provide insights.
            Use read_file, run_shell (for cat, wc, head, jq, etc.), file_info, list_directory.
            Do NOT write files, take screenshots, or interact with GUI.
            Focus on delivering a clear, structured analysis of what you find.
            """
        case .execute:
            return """
            You are an execution sub-agent. Perform actions on the system efficiently.
            You can use all tools: run_shell, run_applescript, take_screenshot, click, type, etc.
            Execute the task, verify the result, and report back concisely.
            If something fails, try an alternative approach before giving up.
            """
        }
    }

    /// Tools allowed for this agent type (nil = all tools)
    var allowedTools: Set<String>? {
        switch self {
        case .general, .execute:
            return nil  // all tools
        case .explore:
            return ["run_shell", "read_file", "list_directory", "file_info",
                    "spotlight_search", "read_memory"]
        case .analyze:
            return ["run_shell", "read_file", "list_directory", "file_info",
                    "spotlight_search", "read_memory", "read_clipboard"]
        }
    }
}

struct SubTask {
    let id: String
    let description: String
    let prompt: String
    let type: SubAgentType
}

struct SubTaskResult {
    let id: String
    let description: String
    let success: Bool
    let output: String
    let type: SubAgentType
    let iterations: Int
    let duration: TimeInterval
}

// MARK: - Progress Reporting

final class SubAgentProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: String] = [:]  // id -> status
    private let total: Int

    init(total: Int) {
        self.total = total
    }

    func update(id: String, status: String) {
        lock.lock()
        statuses[id] = status
        lock.unlock()
        render()
    }

    func complete(id: String, success: Bool, preview: String) {
        let icon = success ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
        lock.lock()
        statuses[id] = "\(icon) \(preview)"
        lock.unlock()
        render()
    }

    private func render() {
        lock.lock()
        let snap = statuses
        lock.unlock()

        let completed = snap.values.filter { $0.contains("✓") || $0.contains("✗") }.count
        let bar = progressBar(completed: completed, total: total)

        // Print status line
        print("\u{001B}[2K\r\u{001B}[90m  \(bar) \(completed)/\(total) agents\u{001B}[0m", terminator: "")
        fflush(stdout)
    }

    private func progressBar(completed: Int, total: Int) -> String {
        let width = 20
        let filled = total > 0 ? (completed * width) / total : 0
        let empty = width - filled
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]"
    }

    func finish() {
        print()  // newline after progress bar
        fflush(stdout)
    }
}

// MARK: - Sub-Agent Executor

final class SubAgentExecutor {
    private let config: AgentConfig
    private let mcpManager: MCPManager?
    private let parentContext: String?
    private let maxConcurrency: Int

    init(config: AgentConfig, mcpManager: MCPManager? = nil, parentContext: String? = nil, maxConcurrency: Int = 5) {
        self.config = config
        self.mcpManager = mcpManager
        self.parentContext = parentContext
        self.maxConcurrency = maxConcurrency
    }

    /// Run multiple sub-tasks in parallel with progress reporting
    func runParallel(tasks: [SubTask], tools: [ClaudeTool]) async -> [SubTaskResult] {
        printColored("  🔀 Launching \(tasks.count) sub-agents in parallel...", color: .magenta)

        // Print task overview
        for task in tasks {
            let typeTag = "[\(task.type.rawValue)]"
            printColored("    → [\(task.id)] \(typeTag) \(task.description)", color: .gray)
        }
        print()

        let progress = SubAgentProgress(total: tasks.count)

        let results: [SubTaskResult] = await withTaskGroup(of: SubTaskResult.self) { group in
            // Use a semaphore pattern for concurrency limiting
            // Add all tasks — Swift will manage scheduling
            for task in tasks {
                group.addTask {
                    progress.update(id: task.id, status: "⏳ running...")
                    let result = await self.runSingle(task: task, tools: tools)
                    let preview = String(result.output.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                    progress.complete(id: task.id, success: result.success, preview: preview)
                    return result
                }
            }

            var collected: [SubTaskResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        progress.finish()

        // Print summary
        let succeeded = results.filter { $0.success }.count
        let totalTime = results.map { $0.duration }.max() ?? 0
        let totalIter = results.map { $0.iterations }.reduce(0, +)

        printColored("  ✓ \(succeeded)/\(results.count) agents completed (\(String(format: "%.1f", totalTime))s, \(totalIter) total iterations)", color: .green)
        print()

        // Print individual results
        for result in results {
            let icon = result.success ? "✓" : "✗"
            let color: ANSIColor = result.success ? .green : .red
            let typeTag = "[\(result.type.rawValue)]"
            printColored("  \(icon) [\(result.id)] \(typeTag) \(result.description)", color: color)
            // Show first 200 chars of output
            let preview = String(result.output.prefix(200)).replacingOccurrences(of: "\n", with: "\n    ")
            printColored("    \(preview)", color: .gray)
            print()
        }

        return results
    }

    /// Run a single sub-task with its own Claude conversation
    private func runSingle(task: SubTask, tools: [ClaudeTool]) async -> SubTaskResult {
        let startTime = Date()
        let client = AIClient(config: config)
        let executor = ToolExecutor()
        executor.mcpManager = mcpManager

        // Filter tools based on agent type
        let filteredTools: [ClaudeTool]
        if let allowed = task.type.allowedTools {
            filteredTools = tools.filter { allowed.contains($0.name) }
        } else {
            // Remove run_subagents to prevent infinite recursion
            filteredTools = tools.filter { $0.name != "run_subagents" }
        }

        // Build system prompt with parent context
        var systemPrompt = task.type.systemPrompt
        if let ctx = parentContext, !ctx.isEmpty {
            systemPrompt += "\n\n## Context from parent agent:\n\(ctx)"
        }

        var messages: [ClaudeMessage] = [
            ClaudeMessage(role: "user", content: [.text(task.prompt)])
        ]

        var finalOutput = ""
        var iterations = 0
        let maxIterations = task.type == .explore ? 8 : 15

        while iterations < maxIterations {
            iterations += 1

            do {
                let response = try await client.sendMessage(
                    messages: messages,
                    system: systemPrompt,
                    tools: filteredTools
                )

                var hasToolUse = false
                var assistantContent: [ClaudeContent] = []
                var toolResults: [ClaudeContent] = []

                for content in response.content {
                    assistantContent.append(content)

                    switch content {
                    case .text(let text):
                        if !text.isEmpty {
                            finalOutput = text
                        }
                    case .toolUse(let id, let name, let input):
                        hasToolUse = true

                        // Check if it's an MCP tool
                        if let mcp = mcpManager, mcp.canHandle(toolName: name) {
                            let args = input.mapValues { $0.value }
                            let result = mcp.executeTool(qualifiedName: name, arguments: args)
                            toolResults.append(.toolResultText(toolUseId: id, text: result.output))
                        } else {
                            let (result, screenshotBase64) = executor.execute(toolName: name, input: input)
                            if let base64 = screenshotBase64 {
                                toolResults.append(.toolResultWithImage(
                                    toolUseId: id, text: result.output,
                                    imageBase64: base64, mediaType: "image/jpeg"
                                ))
                            } else {
                                toolResults.append(.toolResultText(toolUseId: id, text: result.output))
                            }
                        }
                    default:
                        break
                    }
                }

                messages.append(ClaudeMessage(role: "assistant", content: assistantContent))

                if hasToolUse {
                    messages.append(ClaudeMessage(role: "user", content: toolResults))
                } else {
                    break
                }

                if response.stopReason == "end_turn" && !hasToolUse {
                    break
                }

            } catch {
                let duration = Date().timeIntervalSince(startTime)
                return SubTaskResult(
                    id: task.id,
                    description: task.description,
                    success: false,
                    output: "Error: \(error)",
                    type: task.type,
                    iterations: iterations,
                    duration: duration
                )
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        return SubTaskResult(
            id: task.id,
            description: task.description,
            success: true,
            output: finalOutput,
            type: task.type,
            iterations: iterations,
            duration: duration
        )
    }
}

// MARK: - Task Parsing

extension SubAgentExecutor {
    /// Parse tasks from the AI's structured tool call
    static func parseTasks(from input: [String: AnyCodable]) -> [SubTask] {
        // Try structured array first (new format)
        if let tasksJson = input["tasks"]?.stringValue,
           let data = tasksJson.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { dict -> SubTask? in
                guard let id = dict["id"] as? String,
                      let desc = dict["description"] as? String,
                      let prompt = dict["prompt"] as? String else { return nil }
                let typeStr = dict["type"] as? String ?? "general"
                let type = SubAgentType(rawValue: typeStr) ?? .general
                return SubTask(id: id, description: desc, prompt: prompt, type: type)
            }
        }
        return []
    }
}
