import Foundation

// MARK: - Agent Loop

final class AgentLoop {
    private let client: AIClient
    private let executor: ToolExecutor
    private let config: AgentConfig
    private let mcpManager: MCPManager
    private var memory: MemoryManager { executor.memory }
    let approval: ApprovalSystem
    let context: ContextManager
    let aside: AsideMonitor
    let orchestrator: ToolOrchestrator
    let errorRecovery: ErrorRecovery
    let adaptive: AdaptiveResponseSystem
    let cacheManager: CacheManager
    let responseOptimizer: ResponseOptimizer
    let performanceAnalyzer: PerformanceAnalyzer
    let subAgentManager: SubAgentManager
    let spendingGuard: SpendingGuard
    private var conversationHistory: [ClaudeMessage] = []
    private let verbose: Bool

    // Consecutive tool failure tracking for error feedback
    private var consecutiveFailures: (toolName: String, errorPrefix: String, count: Int) = ("", "", 0)

    // Loop guard: recent tool call hashes for ping-pong detection
    private var recentToolCallHashes: [String] = []

    // Gateway support
    var gatewayContext: GatewayDeliveryContext?
    var onStreamText: ((String) async -> Void)?

    // Desktop app NDJSON mode
    var appModeEmitter: AppModeEmitter?

    // Cancellation support
    var isCancelled = false
    func cancel() {
        isCancelled = true
        // Kill any running shell process immediately
        executor.shell.killActiveProcess()
        // Interrupt any blocking MCP tool calls
        mcpManager.interruptActiveCalls()
    }
    func resetCancel() { isCancelled = false }

    var currentHistory: [ClaudeMessage] { conversationHistory }

    func restoreHistory(_ history: [ClaudeMessage]) {
        conversationHistory = history
    }

    init(config: AgentConfig, mcpManager: MCPManager) {
        self.config = config
        self.client = AIClient(config: config)
        self.executor = ToolExecutor()
        self.mcpManager = mcpManager
        self.approval = ApprovalSystem()
        self.context = ContextManager(model: config.model)
        self.aside = AsideMonitor()
        self.orchestrator = ToolOrchestrator()
        self.errorRecovery = ErrorRecovery()
        self.adaptive = AdaptiveResponseSystem()
        self.cacheManager = CacheManager()
        self.responseOptimizer = ResponseOptimizer()
        self.performanceAnalyzer = PerformanceAnalyzer()
        self.subAgentManager = SubAgentManager(config: config, mcpManager: mcpManager)
        self.spendingGuard = SpendingGuard(limits: AgentConfigFile.load().spendingLimits)
        self.verbose = config.verbose

        // Wire up MCP and sub-agent config
        self.executor.vision.maxWidth = config.maxScreenshotWidth
        self.executor.mcpManager = mcpManager
        self.executor.subAgentConfig = config
        self.executor.approvalSystem = self.approval
    }

    /// Process input with optional images (vision)
    func processUserInputWithImages(_ userInput: String, images: [InputResult.ImageAttachment] = []) async throws -> String {
        var content: [ClaudeContent] = []

        // Add images first
        for img in images {
            content.append(.image(source: ImageSource(
                type: "base64", mediaType: img.mediaType, data: img.base64
            )))
        }

        // Add text
        if !userInput.isEmpty {
            content.append(.text(userInput))
        } else if !images.isEmpty {
            content.append(.text("Describe this image."))
        }

        return try await processUserContent(content)
    }

    func processUserInput(_ userInput: String) async throws -> String {
        return try await processUserContent([.text(userInput)])
    }

    // MARK: - Fallback Model Chain

    /// Try each fallback model in order (1 attempt each). Returns the first successful response,
    /// or nil if all fallbacks fail (caller should throw the original error).
    private func tryFallbackModels(
        messages: [ClaudeMessage],
        system: String?,
        tools: [ClaudeTool]?,
        originalError: Error
    ) async throws -> ClaudeResponse? {
        guard !config.fallbackModels.isEmpty else { return nil }

        let fileConfig = AgentConfigFile.load()

        for modelString in config.fallbackModels {
            guard let resolved = AIProvider.resolve(modelString: modelString) else {
                if verbose {
                    printColored("  ⚠ Skipping unknown fallback model: \(modelString)", color: .gray)
                }
                continue
            }

            // Get API key for fallback provider
            var fallbackKey = fileConfig.getAPIKey(provider: resolved.provider.id) ?? ""
            if fallbackKey.isEmpty {
                let envKeys: [String: String] = [
                    "anthropic": "ANTHROPIC_API_KEY",
                    "openai": "OPENAI_API_KEY",
                    "google": "GOOGLE_API_KEY",
                    "groq": "GROQ_API_KEY",
                    "mistral": "MISTRAL_API_KEY",
                    "openrouter": "OPENROUTER_API_KEY",
                    "deepseek": "DEEPSEEK_API_KEY",
                    "xai": "XAI_API_KEY",
                ]
                if let envName = envKeys[resolved.provider.id] {
                    fallbackKey = ProcessInfo.processInfo.environment[envName] ?? ""
                }
            }

            guard !fallbackKey.isEmpty else {
                if verbose {
                    printColored("  ⚠ Skipping fallback \(modelString) — no API key", color: .gray)
                }
                continue
            }

            let fallbackBaseURL = fileConfig.getBaseURL(provider: resolved.provider.id) ?? resolved.provider.defaultBaseURL
            let fallbackClient = AIClient(
                apiKey: fallbackKey,
                model: resolved.model,
                maxTokens: config.maxTokens,
                baseURL: fallbackBaseURL,
                format: resolved.provider.format
            )

            printColored("  ⚠ Primary model failed, trying fallback: \(modelString)", color: .yellow)

            do {
                let response = try await fallbackClient.sendMessage(
                    messages: messages,
                    system: system,
                    tools: tools
                )
                printColored("  ✓ Fallback \(modelString) succeeded", color: .green)
                return response
            } catch {
                printColored("  ✗ Fallback \(modelString) also failed: \(error.localizedDescription)", color: .red)
                continue
            }
        }

        return nil
    }

    private func processUserContent(_ content: [ClaudeContent]) async throws -> String {
        // Add user message
        conversationHistory.append(ClaudeMessage(
            role: "user",
            content: content
        ))

        let userInput = content.compactMap {
            if case .text(let t) = $0 { return t }
            return nil
        }.joined(separator: " ")

        // --- Specialized Agent Routing ---
        // Only auto-route on first message or very early in conversation (not follow-ups)
        let shouldRoute = conversationHistory.count <= 2
        if shouldRoute, let specializedAgent = AgentRegistry.route(input: userInput) {
            // Claude Code backend: delegate directly to CLI
            if specializedAgent.usesClaudeCode {
                if let emitter = appModeEmitter {
                    emitter.emitAgentRoute(agent: specializedAgent.name, model: "claude-code")
                } else if verbose {
                    printColored("  \u{1F3AF} Routing to Claude Code agent: \(specializedAgent.name)", color: .magenta)
                }
                let result = try await runClaudeCodeAgent(agent: specializedAgent, input: userInput)
                if !result.isEmpty {
                    conversationHistory.append(ClaudeMessage(role: "assistant", content: [.text(result)]))
                    return result
                }
            }
            // API backend: verify the model can be resolved
            else if let resolved = AIProvider.resolve(modelString: specializedAgent.model) {
                if let emitter = appModeEmitter {
                    emitter.emitAgentRoute(agent: specializedAgent.name, model: specializedAgent.model)
                } else if verbose {
                    printColored("  \u{1F3AF} Routing to specialized agent: \(specializedAgent.name) (\(specializedAgent.model))", color: .magenta)
                }
                do {
                    let result = try await runSpecializedAgent(agent: specializedAgent, resolved: resolved, input: userInput)
                    if !result.isEmpty {
                        conversationHistory.append(ClaudeMessage(role: "assistant", content: [.text(result)]))
                        return result
                    }
                } catch {
                    // Specialized agent failed — fall through to main model
                    let msg = "Agent '\(specializedAgent.name)' failed: \(error is AgentError ? (error as! AgentError).description : error.localizedDescription). Falling back to main model."
                    if let emitter = appModeEmitter {
                        emitter.emitStatus(msg)
                    } else {
                        printColored("  \u{26A0} \(msg)", color: .yellow)
                    }
                }
            } else if verbose {
                printColored("  \u{26A0} Agent '\(specializedAgent.name)' model '\(specializedAgent.model)' not resolved, using main model", color: .yellow)
            }
        }

        var finalResponse = ""
        var iterations = 0
        let maxIterations = 30

        // Start aside monitor so user can type while we work (skip in gateway mode)
        if gatewayContext == nil {
            aside.start()
        }

        // Build system prompt with conditional memory + matched skills + adaptive context
        let memoryContext = memory.getMemoryContext(for: userInput)
        let skillContext = SkillManager.buildSkillContext(for: userInput)
        let adaptiveContext = adaptive.buildAdaptiveContext(
            userInput: userInput,
            gatewayContext: gatewayContext,
            isSubAgent: false
        )
        let fullSystemPrompt = config.systemPrompt + memoryContext + skillContext + adaptiveContext

        // Determine required tool categories based on user message (intent-based dynamic loading)
        let requiredCategories = IntentAnalyzer.requiredToolCategories(for: userInput)
        var filteredTools = ToolDefinitions.tools(for: requiredCategories)

        // Always add MCP tools if any are configured (they're already specific to installed servers)
        let mcpTools = mcpManager.getClaudeTools()
        if !mcpTools.isEmpty {
            filteredTools += mcpTools
        }

        // Add discover_tools meta-tool so the agent can request more tools if needed
        filteredTools.append(ToolDefinitions.discoverToolsTool)

        // Track dynamically discovered tools that get added mid-conversation
        var dynamicToolCategories: Set<ToolCategory> = []

        var allTools = filteredTools

        if verbose {
            let loadedNames = filteredTools.filter { $0.name != "discover_tools" }.map { $0.name }
            printColored("  [Tools] Loaded \(loadedNames.count) tools for categories: \(requiredCategories.map { $0.rawValue }.sorted().joined(separator: ", "))", color: .gray)
        }

        while iterations < maxIterations {
            // Check cancellation
            if isCancelled {
                if let emitter = appModeEmitter {
                    emitter.emitStatus("Task cancelled by user")
                } else {
                    printColored("\n  ⚠ Task cancelled by user", color: .yellow)
                }
                isCancelled = false
                return finalResponse
            }

            iterations += 1

            if verbose {
                printColored("  [Agent] Iteration \(iterations)/\(maxIterations)", color: .gray)
            }

            // Strip old images from history to save tokens (images are ~85K tokens each)
            // Keep only the 2 most recent screenshots; older ones are replaced with text placeholders
            if conversationHistory.count > 6 {
                conversationHistory = context.stripOldImages(from: conversationHistory, keepLast: 2)
            }

            // Check if compaction needed before sending
            if context.needsCompaction && conversationHistory.count > 10 {
                let preCount = conversationHistory.count
                let preTokens = context.estimateMessageTokens(conversationHistory)
                if let emitter = appModeEmitter {
                    emitter.emitStatus("Compacting context (\(preCount) messages, ~\(context.fmtTokens(preTokens)) tokens)...")
                } else {
                    printColored("  🗜 Compacting context (\(preCount) messages, ~\(context.fmtTokens(preTokens)) tokens)...", color: .magenta)
                }
                conversationHistory = try await context.compactHistory(
                    messages: conversationHistory,
                    client: client,
                    systemPrompt: fullSystemPrompt
                )
                let postTokens = context.estimateMessageTokens(conversationHistory)
                let saved = max(preTokens - postTokens, 0)
                if let emitter = appModeEmitter {
                    emitter.emitStatus("Compacted: \(preCount) → \(conversationHistory.count) messages, saved ~\(context.fmtTokens(saved)) tokens")
                } else {
                    printColored("  ✓ Compacted: \(preCount) → \(conversationHistory.count) messages, saved ~\(context.fmtTokens(saved)) tokens", color: .green)
                }
            }

            // Check spending limits before API call
            if let limitError = spendingGuard.checkLimits() {
                throw AgentError.permissionDenied(limitError)
            }
            if let warning = spendingGuard.checkWarnings() {
                if let emitter = appModeEmitter {
                    emitter.emitStatus(warning)
                } else {
                    printColored("  \(warning)", color: .yellow)
                }
            }

            // API call with automatic retry for transient errors + fallback models
            let apiStartTime = DispatchTime.now()
            let response: ClaudeResponse
            do {
                response = try await client.sendMessage(
                    messages: conversationHistory,
                    system: fullSystemPrompt,
                    tools: allTools
                )
                let apiElapsed = Int((DispatchTime.now().uptimeNanoseconds - apiStartTime.uptimeNanoseconds) / 1_000_000)
                performanceAnalyzer.recordApiCall(durationMs: apiElapsed)
            } catch {
                let classified = errorRecovery.classify(error: error)
                errorRecovery.recordError(classified)
                if classified.isRetryable, case .retry(let delayMs, _) = classified.suggestedAction {
                    if let emitter = appModeEmitter {
                        emitter.emitStatus("\(classified.category) — retrying in \(delayMs)ms...")
                    } else {
                        printColored("  🔄 \(classified.category) — retrying in \(delayMs)ms...", color: .yellow)
                    }
                    try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                    do {
                        response = try await client.sendMessage(
                            messages: conversationHistory,
                            system: fullSystemPrompt,
                            tools: allTools
                        )
                    } catch {
                        // Primary model retry failed — try fallback models
                        if let fallbackResponse = try await tryFallbackModels(
                            messages: conversationHistory,
                            system: fullSystemPrompt,
                            tools: allTools,
                            originalError: error
                        ) {
                            response = fallbackResponse
                        } else {
                            throw error
                        }
                    }
                } else {
                    // Non-retryable on primary — try fallback models directly
                    if let fallbackResponse = try await tryFallbackModels(
                        messages: conversationHistory,
                        system: fullSystemPrompt,
                        tools: allTools,
                        originalError: error
                    ) {
                        response = fallbackResponse
                    } else {
                        throw error
                    }
                }
            }

            // Track token usage and spending
            context.recordUsage(response.usage)
            if let usage = response.usage {
                let cost = context.pricing.costForTokens(input: usage.inputTokens, output: usage.outputTokens)
                spendingGuard.recordSpend(cost: cost)
            }

            if let emitter = appModeEmitter, let usage = response.usage {
                emitter.emitTokens(input: usage.inputTokens, output: usage.outputTokens)
                let pct = Int(context.contextPercentage)
                emitter.emitContextPressure(usedPercent: pct)
            } else if verbose, let usage = response.usage {
                printColored("  [Tokens] ↑\(usage.inputTokens) ↓\(usage.outputTokens) | Context: \(context.shortStatus)", color: .gray)
            }

            var hasToolUse = false
            var assistantContent: [ClaudeContent] = []
            var toolResults: [ClaudeContent] = []

            // === PHASE 1: Collect all content and identify tool calls ===
            var pendingToolCalls: [(id: String, name: String, input: [String: AnyCodable])] = []

            for content in response.content {
                assistantContent.append(content)

                switch content {
                case .text(let text):
                    if !text.isEmpty {
                        finalResponse += (finalResponse.isEmpty ? "" : "\n") + text
                        if let emitter = appModeEmitter {
                            emitter.emitText(text)
                        } else {
                            printWithPlanFormatting(text)
                        }
                        if let stream = onStreamText {
                            await stream(text)
                        }
                    }

                case .toolUse(let id, let name, let input, _):
                    hasToolUse = true
                    let detail = toolDetail(name: name, input: input)
                    if let emitter = appModeEmitter {
                        emitter.emitToolStart(id: id, name: name, detail: detail)
                    } else {
                        let icon = toolIcon(name)
                        if detail.isEmpty {
                            printColored("  \(icon) \(name)", color: .yellow)
                        } else {
                            printColored("  \(icon) \(name)", color: .yellow)
                            printColored("    \(detail)", color: .gray)
                        }

                        if verbose {
                            let inputDesc = input.map { "\($0.key): \($0.value.value)" }.joined(separator: ", ")
                            printColored("    Input: \(inputDesc)", color: .gray)
                        }
                    }

                    pendingToolCalls.append((id: id, name: name, input: input))

                default:
                    break
                }
            }

            // === Loop Guard: Ping-pong detection ===
            if !pendingToolCalls.isEmpty {
                let callHash = pendingToolCalls.map { "\($0.name):\($0.input.keys.sorted().joined())" }.joined(separator: "|")
                recentToolCallHashes.append(callHash)
                if recentToolCallHashes.count > 6 {
                    recentToolCallHashes.removeFirst()
                }
                // Detect ping-pong: A-B-A-B pattern
                if recentToolCallHashes.count >= 4 {
                    let last4 = Array(recentToolCallHashes.suffix(4))
                    if last4[0] == last4[2] && last4[1] == last4[3] && last4[0] != last4[1] {
                        let warning = "[SYSTEM: Loop detected - you are repeating the same tool call pattern. Break the cycle by trying a different approach or informing the user.]"
                        if let emitter = appModeEmitter {
                            emitter.emitStatus("Loop pattern detected - injecting guidance")
                        } else {
                            printColored("  ⚠ Loop pattern detected (ping-pong)", color: .yellow)
                        }
                        conversationHistory.append(ClaudeMessage(role: "user", content: [.text(warning)]))
                    }
                }
            }

            // === PHASE 2: Execute tool calls with async pipeline ===
            let toolExecStart = DispatchTime.now()
            var pipelineToolCalls: [AsyncToolPipeline.ToolCall] = []

            for tc in pendingToolCalls {
                // --- Approval check ---
                let classification = approval.classify(toolName: tc.name, input: tc.input)
                if !approval.requestApproval(toolName: tc.name, classification: classification, input: tc.input) {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: "Action denied by user."))
                    continue
                }

                // Wire shell streaming for long-running commands in gateway mode
                if tc.name == "run_shell", onStreamText != nil {
                    let command = tc.input["command"]?.stringValue ?? ""
                    let timeout = tc.input["timeout"]?.intValue ?? 30
                    if timeout > 5 {
                        var result = await executeShellWithStreaming(command: command, timeout: timeout)
                        if !result.success {
                            let enhanced = enhanceToolError(toolName: tc.name, input: tc.input, error: result.output)
                            let guidance = "\n\n[SYSTEM: This tool call failed. Do NOT fabricate or assume the result. Do NOT take downstream actions based on expected output from this failed call. Instead, inform the user of the failure or try an alternative approach.]"
                            result = ToolResult(success: false, output: enhanced + guidance, screenshot: result.screenshot)
                        } else {
                            resetConsecutiveFailures(toolName: tc.name)
                        }
                        if let emitter = appModeEmitter {
                            emitter.emitToolResult(id: tc.id, name: tc.name, success: result.success, output: result.output)
                        } else {
                            let statusIcon = result.success ? "✓" : "✗"
                            printColored("    \(statusIcon) \(String(result.output.prefix(300)))", color: result.success ? .green : .red)
                        }
                        toolResults.append(.toolResultText(toolUseId: tc.id, text: result.output))
                        continue
                    }
                }

                // Handle discover_tools — dynamically load more tools
                if tc.name == "discover_tools" {
                    let query = tc.input["query"]?.stringValue ?? ""
                    let matchedCategories = IntentAnalyzer.requiredToolCategories(for: query)
                    let newCategories = matchedCategories.subtracting(requiredCategories).subtracting(dynamicToolCategories)

                    if newCategories.isEmpty {
                        toolResults.append(.toolResultText(toolUseId: tc.id, text: "All relevant tools are already loaded. Available tools: \(allTools.map { $0.name }.joined(separator: ", "))"))
                    } else {
                        let newTools = ToolDefinitions.tools(for: newCategories).filter { newTool in
                            !allTools.contains(where: { $0.name == newTool.name })
                        }
                        dynamicToolCategories.formUnion(newCategories)
                        allTools += newTools
                        let toolNames = newTools.map { $0.name }.joined(separator: ", ")
                        printColored("    🔧 Discovered \(newTools.count) tools: \(toolNames)", color: .cyan)
                        toolResults.append(.toolResultText(toolUseId: tc.id, text: "Loaded \(newTools.count) additional tools: \(toolNames). You can now use them."))
                    }
                }
                // Handle delegated tools (sub-agents, MCP, schedulers, etc.)
                else if tc.name == "run_subagents" {
                    let subResult = await handleSubAgents(input: tc.input, allTools: allTools)
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: subResult))
                }
                else if tc.name == "mcp_install" {
                    let installResult = handleMCPInstall(input: tc.input)
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: installResult))
                }
                else if tc.name == "mcp_search" {
                    let searchResult = handleMCPSearch(input: tc.input)
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: searchResult))
                }
                else if tc.name == "schedule_task" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: handleScheduleTask(input: tc.input)))
                }
                else if tc.name == "list_tasks" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: handleListTasks()))
                }
                else if tc.name == "cancel_task" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: handleCancelTask(input: tc.input)))
                }
                else if tc.name == "run_task" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: handleRunTask(input: tc.input)))
                }
                else if tc.name == "configure_gateway" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: handleConfigureGateway(input: tc.input)))
                }
                else if tc.name == "import_gateway_config" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: handleImportGatewayConfig(input: tc.input)))
                }
                else if tc.name == "claude_code" {
                    let result = await handleClaudeCode(input: tc.input)
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: result))
                }
                else if tc.name == "orchestrator_stats" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: orchestrator.stats))
                }
                else if tc.name == "orchestrator_insights" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: orchestrator.getPatternInsights()))
                }
                else if tc.name == "clear_tool_cache" {
                    orchestrator.clearCache()
                    cacheManager.clearAll()
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: "Tool result cache cleared."))
                }
                else if tc.name == "adaptive_stats" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: adaptive.stats))
                }
                else if tc.name == "performance_stats" {
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: performanceAnalyzer.detailedStats))
                }
                else if tc.name == "ui_cache_lookup" {
                    let appName = tc.input["app_name"]?.stringValue ?? ""
                    toolResults.append(.toolResultText(toolUseId: tc.id, text: handleUICacheLookup(appName: appName)))
                }
                else if tc.name == "clear_ui_cache" {
                    let appName = tc.input["app_name"]?.stringValue
                    if let app = appName {
                        adaptive.uiIntelligence.clearCache()
                        toolResults.append(.toolResultText(toolUseId: tc.id, text: "UI cache cleared for \(app)."))
                    } else {
                        adaptive.clearAll()
                        toolResults.append(.toolResultText(toolUseId: tc.id, text: "All UI caches cleared."))
                    }
                }
                else {
                    // Collect for async pipeline execution
                    pipelineToolCalls.append(AsyncToolPipeline.ToolCall(
                        id: tc.id, name: tc.name, input: tc.input
                    ))
                }
            }

            // === PHASE 3: Execute pipeline tools (parallel where safe) ===
            if !pipelineToolCalls.isEmpty {
                let strategy = AsyncToolPipeline.analyzeStrategy(tools: pipelineToolCalls)

                if let emitter = appModeEmitter, pipelineToolCalls.count > 1 {
                    emitter.emitStatus("Pipeline: \(pipelineToolCalls.count) tools, strategy=\(strategy)")
                } else if verbose && pipelineToolCalls.count > 1 {
                    printColored("    ⚡ Pipeline: \(pipelineToolCalls.count) tools, strategy=\(strategy)", color: .cyan)
                }

                let pipelineResults: [AsyncToolPipeline.PipelineResult]
                switch strategy {
                case .parallel:
                    pipelineResults = await AsyncToolPipeline.executeParallel(
                        tools: pipelineToolCalls, executor: executor,
                        orchestrator: orchestrator, verbose: verbose
                    )
                case .mixed:
                    pipelineResults = await AsyncToolPipeline.executeMixed(
                        tools: pipelineToolCalls, executor: executor,
                        orchestrator: orchestrator, verbose: verbose
                    )
                case .sequential:
                    // Fall back to sequential but still use pipeline infrastructure
                    var seqResults: [AsyncToolPipeline.PipelineResult] = []
                    for tool in pipelineToolCalls {
                        let results = await AsyncToolPipeline.executeParallel(
                            tools: [tool], executor: executor,
                            orchestrator: orchestrator, verbose: verbose
                        )
                        seqResults.append(contentsOf: results)
                    }
                    pipelineResults = seqResults
                }

                // Process pipeline results with error recovery and response optimization
                for pr in pipelineResults {
                    var result = pr.result
                    var screenshotBase64 = pr.screenshotBase64

                    // Error recovery for failed tools
                    if !result.success {
                        if let classified = errorRecovery.classifyToolFailure(toolName: pr.name, result: result) {
                            errorRecovery.recordError(classified)
                            if classified.isRetryable {
                                if verbose { printColored("    🔄 Attempting recovery (\(classified.category))...", color: .yellow) }
                                if let recovered = errorRecovery.attemptRecovery(
                                    toolName: pr.name, input: pipelineToolCalls.first(where: { $0.id == pr.id })?.input ?? [:],
                                    error: classified, executor: executor
                                ) {
                                    result = recovered.0
                                    screenshotBase64 = recovered.1
                                    if verbose { printColored("    ✓ Recovered via retry", color: .green) }
                                }
                            }
                            if !result.success {
                                let input = pipelineToolCalls.first(where: { $0.id == pr.id })?.input ?? [:]
                                if let fallback = errorRecovery.executeFallback(
                                    toolName: pr.name, input: input, executor: executor
                                ) {
                                    result = fallback.0
                                    screenshotBase64 = fallback.1
                                    if verbose { printColored("    ✓ Recovered via fallback", color: .green) }
                                }
                            }
                        }
                    }

                    // Enhance failed tool results with contextual hints for self-correction
                    let toolInput = pipelineToolCalls.first(where: { $0.id == pr.id })?.input ?? [:]
                    if !result.success {
                        let enhanced = enhanceToolError(toolName: pr.name, input: toolInput, error: result.output)
                        let guidance = "\n\n[SYSTEM: This tool call failed. Do NOT fabricate or assume the result. Do NOT take downstream actions based on expected output from this failed call. Instead, inform the user of the failure or try an alternative approach.]"
                        result = ToolResult(success: false, output: enhanced + guidance, screenshot: result.screenshot)
                    } else {
                        resetConsecutiveFailures(toolName: pr.name)
                    }

                    // Optimize result output to save tokens
                    result = responseOptimizer.optimize(toolName: pr.name, result: result)

                    // Also cache in CacheManager for predictive warming
                    cacheManager.put(toolName: pr.name, input: toolInput, result: result, screenshotBase64: screenshotBase64)
                    cacheManager.invalidate(forTool: pr.name)

                    // Record in performance analyzer
                    performanceAnalyzer.recordToolTiming(
                        name: pr.name, durationMs: pr.durationMs,
                        wasCached: pr.wasCached, wasParallel: strategy == .parallel
                    )

                    if let emitter = appModeEmitter {
                        emitter.emitToolResult(id: pr.id, name: pr.name, success: result.success, output: result.output, durationMs: pr.durationMs)
                    } else {
                        let statusIcon = result.success ? "✓" : "✗"
                        let statusColor: ANSIColor = result.success ? .green : .red
                        let cacheTag = pr.wasCached ? " ⚡cache" : ""
                        printColored("    \(statusIcon) \(String(result.output.prefix(300)))\(cacheTag)", color: statusColor)
                    }

                    if let base64 = screenshotBase64 {
                        toolResults.append(.toolResultWithImage(
                            toolUseId: pr.id, text: result.output,
                            imageBase64: base64, mediaType: "image/jpeg"
                        ))
                        printColored("    📸 Screenshot sent to AI", color: .magenta)
                    } else {
                        toolResults.append(.toolResultText(toolUseId: pr.id, text: result.output))
                    }
                }

                // Record pipeline stats
                let pipelineStats = AsyncToolPipeline.computeStats(results: pipelineResults, tools: pipelineToolCalls)
                if pipelineStats.savedMs > 0 {
                    performanceAnalyzer.recordTimeSaved(ms: pipelineStats.savedMs)
                    if verbose {
                        printColored("    ⚡ Pipeline: \(pipelineStats.description)", color: .cyan)
                    }
                }
            }

            // Check cancellation after tool execution
            if isCancelled {
                if let emitter = appModeEmitter {
                    emitter.emitStatus("Task cancelled by user")
                } else {
                    printColored("\n  ⚠ Task cancelled by user", color: .yellow)
                }
                isCancelled = false
                return finalResponse
            }

            // Record iteration timing
            let toolExecElapsed = Int((DispatchTime.now().uptimeNanoseconds - toolExecStart.uptimeNanoseconds) / 1_000_000)
            let apiElapsedForIter = Int((toolExecStart.uptimeNanoseconds - apiStartTime.uptimeNanoseconds) / 1_000_000)
            performanceAnalyzer.recordIteration(
                iteration: iterations,
                apiCallMs: apiElapsedForIter,
                toolExecutionMs: toolExecElapsed,
                toolCount: pendingToolCalls.count,
                parallelCount: pipelineToolCalls.count,
                cacheHits: pipelineToolCalls.isEmpty ? 0 : pipelineToolCalls.filter { tc in
                    cacheManager.get(toolName: tc.name, input: tc.input) != nil
                }.count
            )

            // Predictive cache warming (async, non-blocking)
            if hasToolUse {
                let predictions = orchestrator.predictNextTools(maxResults: 3)
                if !predictions.isEmpty {
                    Task {
                        await self.cacheManager.warmCache(
                            predictions: predictions, executor: self.executor,
                            orchestrator: self.orchestrator
                        )
                    }
                }
            }

            conversationHistory.append(ClaudeMessage(role: "assistant", content: assistantContent))

            if hasToolUse {
                // Collect tool names from this iteration for batching analysis
                let toolsThisTurn = assistantContent.compactMap { c -> String? in
                    if case .toolUse(_, let n, _, _) = c { return n }
                    return nil
                }

                // Inject batching hint if the AI is making suboptimal single calls
                if let hint = orchestrator.checkBatchingOpportunity(currentTools: toolsThisTurn) {
                    if verbose {
                        printColored("  ⚡ Batch hint: \(hint.reason)", color: .cyan)
                    }
                    let hintText = "[ORCHESTRATOR HINT] \(hint.reason). Consider calling these together: \(hint.tools.joined(separator: ", "))"
                    toolResults.append(.text(hintText))
                }

                // Check for user asides (messages typed while agent was working)
                let asides = aside.drain()
                if !asides.isEmpty {
                    let asideText = asides.map { "💬 [USER ASIDE]: \($0)" }.joined(separator: "\n")
                    toolResults.append(.text(asideText))
                }
                conversationHistory.append(ClaudeMessage(role: "user", content: toolResults))
            } else {
                break
            }

            if response.stopReason == "end_turn" && !hasToolUse {
                break
            }
        }

        // Stop aside monitor
        aside.stop()

        // Save orchestrator patterns and adaptive learning data
        orchestrator.savePatterns()
        adaptive.saveSession()

        if iterations >= maxIterations {
            printColored("  ⚠ Reached maximum iterations (\(maxIterations)).", color: .yellow)
        }

        if verbose {
            printColored("  [Orchestrator] Cache: \(orchestrator.cacheHits)h/\(orchestrator.cacheHits + orchestrator.cacheMisses)t, Predictions: \(orchestrator.predictionsCorrect)/\(orchestrator.predictionsMade)", color: .gray)
            printColored("  [Pipeline] \(cacheManager.statsDescription)", color: .gray)
            printColored("  [Optimizer] \(responseOptimizer.statsDescription)", color: .gray)
            printColored("  [Perf] \(performanceAnalyzer.shortStats)", color: .gray)
        }

        return finalResponse
    }

    // MARK: - Sub-Agent Handling

    private func handleSubAgents(input: [String: AnyCodable], allTools: [ClaudeTool]) async -> String {
        let tasks = SubAgentExecutor.parseTasks(from: input)

        if tasks.isEmpty {
            return "Error: No valid tasks found. Expected JSON array with id, description, prompt, type fields."
        }

        // Extract optional context from the parent agent
        let context = input["context"]?.stringValue

        let subExecutor = SubAgentExecutor(
            config: config,
            mcpManager: mcpManager,
            parentContext: context,
            maxConcurrency: 5
        )
        let results = await subExecutor.runParallel(tasks: tasks, tools: allTools)

        // Format results for the parent agent
        let succeeded = results.filter { $0.success }.count
        var output = "Sub-agent results: \(succeeded)/\(results.count) succeeded\n\n"
        for result in results {
            let icon = result.success ? "✓" : "✗"
            output += "### \(icon) [\(result.id)] \(result.description) (\(result.type.rawValue), \(result.iterations) iters, \(String(format: "%.1f", result.duration))s)\n"
            output += result.output + "\n\n"
        }
        return output
    }

    // MARK: - MCP Search & Install

    private func handleMCPSearch(input: [String: AnyCodable]) -> String {
        let query = input["query"]?.stringValue ?? ""
        printColored("    🔍 Searching npm for MCP servers: \(query)...", color: .magenta)

        let shell = ShellDriver()
        let result = shell.execute(command: "npm search --json 'mcp \(query)' 2>/dev/null | head -c 5000", timeout: 30)

        if !result.success || result.output.isEmpty {
            // Fallback: try a simpler search
            let fallback = shell.execute(command: "npm search 'mcp-server \(query)' --long 2>/dev/null | head -20", timeout: 30)
            if fallback.success && !fallback.output.isEmpty {
                return "NPM search results for MCP servers related to '\(query)':\n\(fallback.output)\n\nTo install one, use the mcp_install tool with the package name."
            }
            return "No MCP packages found for '\(query)'. Try searching with different keywords, or check https://github.com/modelcontextprotocol/servers for official MCP servers."
        }

        return "NPM search results (JSON):\n\(result.output)\n\nTo install, use mcp_install with the package name (e.g., the 'name' field from above)."
    }

    private func handleMCPInstall(input: [String: AnyCodable]) -> String {
        let package = input["package"]?.stringValue ?? ""
        let name = input["name"]?.stringValue ?? package.split(separator: "/").last.map(String.init) ?? "mcp"
        let args = input["args"]?.stringValue?.split(separator: " ").map(String.init) ?? []

        if package.isEmpty {
            return "Error: 'package' is required. Example: mcp_install(package: \"chrome-devtools-mcp\", name: \"chrome\")"
        }

        printColored("    📦 Installing MCP server '\(name)' from '\(package)'...", color: .magenta)

        // Determine command: if it looks like an npm package, use npx
        let command: String
        let cmdArgs: [String]
        if package.contains("/") || !package.contains(".") {
            // npm package — use npx
            command = "npx"
            cmdArgs = [package] + args
        } else {
            // Direct command
            command = package
            cmdArgs = args
        }

        // Save to config
        let serverConfig = MCPServerConfig(command: command, args: cmdArgs.isEmpty ? nil : cmdArgs, env: nil, description: "Installed via mcp_install")
        var fileConfig = AgentConfigFile.load()
        if fileConfig.mcpServers == nil { fileConfig.mcpServers = [:] }
        fileConfig.mcpServers?[name] = serverConfig
        do {
            try fileConfig.save()
        } catch {
            return "Error saving MCP config: \(error)"
        }

        // Try to start it
        do {
            try mcpManager.startServer(name: name, config: serverConfig)
            let tools = mcpManager.availableTools.filter { $0.qualifiedName.hasPrefix("mcp_\(name)_") }
            var output = "✓ MCP server '\(name)' installed and started.\n"
            output += "  Command: \(command) \(cmdArgs.joined(separator: " "))\n"
            if !tools.isEmpty {
                output += "  Available tools (\(tools.count)):\n"
                for tool in tools {
                    output += "    • \(tool.qualifiedName): \(tool.description.prefix(60))\n"
                }
            }
            return output
        } catch {
            return "MCP server '\(name)' saved to config but failed to start: \(error)\nThe config is saved — try restarting the agent or check the package name."
        }
    }

    // MARK: - Task Scheduler Handlers

    private func handleScheduleTask(input: [String: AnyCodable]) -> String {
        let id = input["id"]?.stringValue ?? "task-\(Int(Date().timeIntervalSince1970))"
        let description = input["description"]?.stringValue ?? ""
        let command = input["command"]?.stringValue ?? ""
        let scheduleType = input["schedule_type"]?.stringValue ?? "once"

        guard !command.isEmpty else {
            return "Error: 'command' is required."
        }

        let schedule: ScheduledTask.TaskSchedule
        switch scheduleType {
        case "daily":
            let hour = input["hour"]?.intValue ?? 8
            let minute = input["minute"]?.intValue ?? 0
            schedule = .recurring(hour: hour, minute: minute)
        case "interval":
            let minutes = input["minutes"]?.intValue ?? 60
            schedule = .interval(minutes: minutes)
        case "once":
            if let atStr = input["at"]?.stringValue {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let date = fmt.date(from: atStr)
                    ?? ISO8601DateFormatter().date(from: atStr)
                    ?? Date(timeIntervalSinceNow: 300)  // fallback: 5 min
                schedule = .once(at: date)
            } else if let minutes = input["minutes"]?.intValue {
                schedule = .once(at: Date(timeIntervalSinceNow: Double(minutes) * 60))
            } else {
                schedule = .once(at: Date(timeIntervalSinceNow: 300))
            }
        default:
            return "Error: Unknown schedule_type '\(scheduleType)'. Use: once, daily, interval."
        }

        printColored("    📅 Scheduling: \(description)", color: .magenta)

        // Attach delivery target from gateway context (so task results go back to the chat)
        var delivery: ScheduledTask.DeliveryTarget? = nil
        if let gw = gatewayContext {
            delivery = ScheduledTask.DeliveryTarget(platform: gw.platform, chatId: gw.chatId)
        }

        do {
            let task = try TaskScheduler.createTask(id: id, description: description, command: command, schedule: schedule, delivery: delivery)
            return "✓ Task '\(task.id)' scheduled: \(task.schedule.displayString)\n  Command: \(task.command)\n  The task will run automatically via macOS launchd."
        } catch {
            return "Error scheduling task: \(error)"
        }
    }

    private func handleListTasks() -> String {
        let tasks = TaskScheduler.listTasks()
        if tasks.isEmpty {
            return "No scheduled tasks. Use schedule_task to create one."
        }

        var output = "Scheduled tasks (\(tasks.count)):\n"
        for task in tasks {
            let status = task.enabled ? "●" : "○"
            let lastRun = task.lastRun.map { d in
                let fmt = DateFormatter()
                fmt.dateFormat = "MM/dd HH:mm"
                return " (last: \(fmt.string(from: d)))"
            } ?? ""
            output += "  \(status) \(task.id) — \(task.description)\n"
            output += "    Schedule: \(task.schedule.displayString)\(lastRun) · Runs: \(task.runCount)\n"
            output += "    Command: \(task.command.prefix(80))\n"
        }
        return output
    }

    private func handleCancelTask(input: [String: AnyCodable]) -> String {
        let id = input["id"]?.stringValue ?? ""
        guard !id.isEmpty else { return "Error: 'id' is required." }

        do {
            try TaskScheduler.cancelTask(id: id)
            return "✓ Task '\(id)' cancelled and removed."
        } catch {
            return "Error cancelling task: \(error)"
        }
    }

    private func handleRunTask(input: [String: AnyCodable]) -> String {
        let taskId = input["task_id"]?.stringValue ?? ""
        guard !taskId.isEmpty else { return "Error: 'task_id' is required." }
        guard let task = TaskScheduler.getTask(id: taskId) else {
            return "Error: Task '\(taskId)' not found."
        }

        // Spawn the task process in background
        let process = Process()
        process.executableURL = URL(fileURLWithPath: TaskScheduler.osaiPath)
        var args = ["--task-id", task.id]
        if let delivery = task.delivery {
            args += ["--deliver", "\(delivery.platform):\(delivery.chatId)"]
        }
        args.append(task.command)
        process.arguments = args
        process.environment = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin",
            "HOME": NSHomeDirectory()
        ]

        do {
            try process.run()
            return "✓ Task '\(taskId)' triggered. Running in background."
        } catch {
            return "Error running task: \(error)"
        }
    }

    // MARK: - Adaptive Response Handlers

    private func handleUICacheLookup(appName: String) -> String {
        guard !appName.isEmpty else { return "Error: 'app_name' is required." }

        // Try memory cache first, then disk
        let layout = adaptive.uiIntelligence.getCachedLayout(appName: appName)
            ?? adaptive.uiIntelligence.loadCachedLayout(appName: appName)

        guard let layout = layout else {
            return "No cached UI data for '\(appName)'. Use get_ui_elements to inspect the app first."
        }

        var output = "Cached UI data for \(layout.appName):\n"
        output += "  Last updated: \(layout.lastUpdated)\n"
        output += "  Cached elements: \(layout.elements.count)\n"

        // Show top elements by interaction count
        let topElements = layout.elements.values
            .sorted { $0.hitCount > $1.hitCount }
            .prefix(15)

        if !topElements.isEmpty {
            output += "\nTop elements:\n"
            for elem in topElements {
                let title = elem.title ?? elem.role
                let lastSuccess = elem.lastSuccess.map { " (last success: \($0))" } ?? ""
                output += "  • [\(elem.role)] \(title) at (\(elem.centerX),\(elem.centerY)) size \(elem.width)x\(elem.height) — \(elem.hitCount) interactions\(lastSuccess)\n"
            }
        }

        // Show workflows
        if !layout.workflows.isEmpty {
            output += "\nLearned workflows:\n"
            for wf in layout.workflows {
                output += "  • \(wf.name): \(wf.steps.count) steps, \(Int(wf.reliability * 100))% reliable, ~\(wf.avgDurationMs)ms, used \(wf.successCount + wf.failCount)x\n"
            }
        }

        return output
    }

    private func handleConfigureGateway(input: [String: AnyCodable]) -> String {
        let platform = input["platform"]?.stringValue ?? ""
        let enabled = input["enabled"]?.stringValue == "true"

        var fileConfig = AgentConfigFile.load()
        if fileConfig.gateways == nil {
            fileConfig.gateways = GatewayConfig()
        }

        switch platform {
        case "telegram":
            let token = input["bot_token"]?.stringValue ?? ""
            var tgConfig = fileConfig.gateways?.telegram ?? TelegramGatewayConfig(enabled: false, botToken: "")
            tgConfig.enabled = enabled
            if !token.isEmpty { tgConfig.botToken = token }
            if let users = input["allowed_users"]?.stringValue {
                tgConfig.allowedUsers = users.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            }
            fileConfig.gateways?.telegram = tgConfig
        case "discord":
            let token = input["bot_token"]?.stringValue ?? ""
            var dcConfig = fileConfig.gateways?.discord ?? DiscordGatewayConfig(enabled: false, botToken: "")
            dcConfig.enabled = enabled
            if !token.isEmpty { dcConfig.botToken = token }
            if let users = input["allowed_users"]?.stringValue {
                dcConfig.allowedUsers = users.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            }
            fileConfig.gateways?.discord = dcConfig
        case "slack":
            let token = input["bot_token"]?.stringValue ?? ""
            let appToken = input["app_token"]?.stringValue ?? ""
            var slConfig = fileConfig.gateways?.slack ?? SlackGatewayConfig(enabled: false, botToken: "", appToken: "")
            slConfig.enabled = enabled
            if !token.isEmpty { slConfig.botToken = token }
            if !appToken.isEmpty { slConfig.appToken = appToken }
            fileConfig.gateways?.slack = slConfig
        case "whatsapp":
            var waConfig = fileConfig.gateways?.whatsapp ?? WhatsAppGatewayConfig(enabled: false)
            waConfig.enabled = enabled
            fileConfig.gateways?.whatsapp = waConfig
        default:
            return "Error: Unknown platform '\(platform)'. Use: telegram, discord, slack, whatsapp."
        }

        try? fileConfig.save()
        return "✓ Gateway '\(platform)' \(enabled ? "enabled" : "disabled"). Run `osai gateway` to start."
    }

    private func handleImportGatewayConfig(input: [String: AnyCodable]) -> String {
        let platform = input["platform"]?.stringValue ?? "all"
        let openClawPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = FileManager.default.contents(atPath: openClawPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = json["channels"] as? [String: Any] else {
            return "Error: Could not read OpenClaw config at ~/.openclaw/openclaw.json"
        }

        var fileConfig = AgentConfigFile.load()
        if fileConfig.gateways == nil {
            fileConfig.gateways = GatewayConfig()
        }

        var imported: [String] = []

        if platform == "all" || platform == "discord" {
            if let discord = channels["discord"] as? [String: Any],
               let token = discord["botToken"] as? String ?? discord["bot_token"] as? String {
                var dcConfig = DiscordGatewayConfig(enabled: true, botToken: token)
                if let allowFrom = discord["allowFrom"] as? [String] ?? discord["allow_from"] as? [String] {
                    dcConfig.allowedUsers = allowFrom
                }
                fileConfig.gateways?.discord = dcConfig
                imported.append("discord")
            }
        }

        if platform == "all" || platform == "telegram" {
            if let tg = channels["telegram"] as? [String: Any],
               let token = tg["botToken"] as? String ?? tg["bot_token"] as? String {
                var tgConfig = TelegramGatewayConfig(enabled: true, botToken: token)
                if let allowFrom = tg["allowFrom"] as? [Int] ?? tg["allow_from"] as? [Int] {
                    tgConfig.allowedUsers = allowFrom
                }
                fileConfig.gateways?.telegram = tgConfig
                imported.append("telegram")
            }
        }

        if imported.isEmpty {
            return "No matching gateway configs found in OpenClaw for '\(platform)'."
        }

        try? fileConfig.save()
        return "✓ Imported from OpenClaw: \(imported.joined(separator: ", ")). Run `osai gateway` to start."
    }

    // MARK: - Streamed Shell Execution (Gateway)

    /// Execute a shell command with real-time output streaming to gateway.
    /// Uses the same buffered streaming pattern as handleClaudeCode.
    private func executeShellWithStreaming(command: String, timeout: Int) async -> ToolResult {
        // Protect osai source code
        let sourcePatterns = ["/Sites/osai/Sources/", "/Sites/osai/Package.swift"]
        let writeCommands = ["sed -i", "tee ", "> ", ">> ", "cat >", "echo >", "cp ", "mv ", "rm ", "git checkout", "git reset"]
        let isSourceWrite = sourcePatterns.contains { srcP in
            writeCommands.contains { wc in command.contains(srcP) && command.contains(wc) }
        }
        if isSourceWrite {
            return ToolResult(success: false, output: "⛔ Cannot modify osai source code via shell. Use the `claude_code` tool.", screenshot: nil)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ToolResult(success: false, output: "Failed to run command: \(error.localizedDescription)", screenshot: nil)
        }

        // Timeout
        let timeoutSeconds = min(max(timeout, 1), 120)
        var timedOut = false
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .seconds(timeoutSeconds))
        timer.setEventHandler { timedOut = true; process.terminate() }
        timer.resume()

        // Stream stdout to gateway with periodic buffer flush
        let streamCallback = onStreamText
        var fullOutput = ""
        let bufferLock = NSLock()
        var pendingBuffer = ""

        let flusher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                bufferLock.lock()
                let chunk = pendingBuffer
                pendingBuffer = ""
                bufferLock.unlock()
                if !chunk.isEmpty, let stream = streamCallback {
                    await stream(chunk)
                }
            }
        }

        // Read stdout incrementally
        let readGroup = DispatchGroup()
        var stderrText = ""

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = stdoutPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    bufferLock.lock()
                    fullOutput += text
                    pendingBuffer += text
                    bufferLock.unlock()
                }
            }
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = stderrPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    bufferLock.lock()
                    stderrText += text
                    bufferLock.unlock()
                }
            }
            readGroup.leave()
        }

        process.waitUntilExit()
        timer.cancel()
        readGroup.wait()
        flusher.cancel()

        // Flush remaining
        bufferLock.lock()
        let remaining = pendingBuffer
        pendingBuffer = ""
        bufferLock.unlock()
        if !remaining.isEmpty, let stream = streamCallback {
            await stream(remaining)
        }

        let stdout = fullOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)

        if timedOut {
            let partial = (stdout + "\n" + stderr)
            let truncated = partial.count > 10000 ? String(partial.prefix(5000)) + "\n...[truncated]...\n" + String(partial.suffix(5000)) : partial
            return ToolResult(success: false, output: "Command timed out after \(timeoutSeconds)s.\nPartial output:\n\(truncated)", screenshot: nil)
        }

        var output = ""
        if !stdout.isEmpty { output += stdout }
        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n--- stderr ---\n" }
            output += stderr
        }
        if output.isEmpty { output = "(no output)" }

        // Truncate for tool result
        if output.count > 10000 {
            let half = 5000
            output = String(output.prefix(half)) + "\n\n... [truncated \(output.count - 10000) chars] ...\n\n" + String(output.suffix(half))
        }

        let exitCode = process.terminationStatus
        let success = exitCode == 0
        if !success { output = "Exit code: \(exitCode)\n\(output)" }

        return ToolResult(success: success, output: output, screenshot: nil)
    }

    // MARK: - Claude Code Integration

    private func handleClaudeCode(input: [String: AnyCodable]) async -> String {
        let prompt = input["prompt"]?.stringValue ?? ""
        guard !prompt.isEmpty else { return "Error: 'prompt' is required." }

        let workdir = input["workdir"]?.stringValue ?? NSHomeDirectory() + "/Sites/osai"
        let claudePath = NSHomeDirectory() + "/.local/bin/claude"

        guard FileManager.default.fileExists(atPath: claudePath) else {
            return "Error: Claude Code CLI not found at \(claudePath). Install from https://claude.ai/claude-code"
        }

        printColored("  🧠 Delegating to Claude Code...", color: .magenta)
        printColored("    Prompt: \(String(prompt.prefix(120)))...", color: .gray)

        // Notify gateway user
        if let stream = onStreamText {
            await stream("🧠 Delegando tarea a Claude Code...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--dangerously-skip-permissions", "-p", "--output-format", "text", prompt]
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)
        process.environment = ProcessInfo.processInfo.environment

        // /dev/null stdin so the process doesn't get suspended (SIGTSTP)
        let devNull = FileHandle(forReadingAtPath: "/dev/null")!
        process.standardInput = devNull

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error running Claude Code: \(error)"
        }

        // Put process in its own group so we can kill the entire tree on timeout
        setpgid(process.processIdentifier, process.processIdentifier)

        // Stream stdout in real-time — read chunks and forward to gateway
        // Zero extra tokens: just reading process output from the pipe
        let streamCallback = onStreamText
        var fullOutput = ""
        let bufferLock = NSLock()
        var pendingBuffer = ""
        let flushInterval: TimeInterval = 3.0  // Send to gateway every 3s

        // Background task: flush buffer to gateway periodically
        let flusher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
                bufferLock.lock()
                let chunk = pendingBuffer
                pendingBuffer = ""
                bufferLock.unlock()

                if !chunk.isEmpty, let stream = self?.onStreamText {
                    await stream(chunk)
                }
            }
        }

        // Read stdout incrementally on a background queue
        let readQueue = DispatchQueue(label: "claude-code-reader")
        let readDone = DispatchSemaphore(value: 0)

        readQueue.async {
            let handle = stdoutPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF
                if let text = String(data: data, encoding: .utf8) {
                    bufferLock.lock()
                    fullOutput += text
                    pendingBuffer += text
                    bufferLock.unlock()

                    // Also print to terminal
                    print(text, terminator: "")
                }
            }
            readDone.signal()
        }

        // Wait for process with real 10 min timeout
        let timeoutSeconds = 600
        let processFinished = DispatchSemaphore(value: 0)
        let processWaiter = DispatchQueue(label: "claude-code-waiter")
        processWaiter.async {
            process.waitUntilExit()
            processFinished.signal()
        }

        let waitResult = processFinished.wait(timeout: .now() + .seconds(timeoutSeconds))
        if waitResult == .timedOut {
            printColored("  ⚠ Claude Code timed out after \(timeoutSeconds)s — killing process", color: .yellow)
            // Kill the entire process group to clean up child processes
            let pid = process.processIdentifier
            kill(-pid, SIGKILL)  // Kill process group
            process.terminate()  // Belt and suspenders
            if let stream = onStreamText {
                await stream("\n⚠️ Claude Code timed out after \(timeoutSeconds/60) minutes.")
            }
        }

        // Wait for reader to finish (with 5s grace period)
        let readerResult = readDone.wait(timeout: .now() + .seconds(5))
        if readerResult == .timedOut {
            // Reader stuck — close the pipe to unblock it
            stdoutPipe.fileHandleForReading.closeFile()
        }

        // Cancel flusher and flush remaining buffer
        flusher.cancel()

        bufferLock.lock()
        let remaining = pendingBuffer
        pendingBuffer = ""
        bufferLock.unlock()

        if !remaining.isEmpty {
            if let stream = streamCallback {
                await stream(remaining)
            }
        }

        // Read stderr
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errors = String(data: errData, encoding: .utf8) ?? ""

        var result = fullOutput
        if !errors.isEmpty && process.terminationStatus != 0 {
            result += "\n[stderr]: \(errors)"
        }
        if result.isEmpty {
            result = "Claude Code completed with no output (exit code: \(process.terminationStatus))"
        }

        // Truncate very long responses for the tool result (gateway already got the full stream)
        if result.count > 15000 {
            result = String(result.prefix(15000)) + "\n\n... [truncated — full output was \(result.count) chars]"
        }

        printColored("\n  ✓ Claude Code finished (\(fullOutput.count) chars)", color: .green)
        return result
    }

    func clearHistory() {
        conversationHistory.removeAll()
        context.reset()
        printColored("  Conversation cleared.", color: .green)
    }

    var historyCount: Int { conversationHistory.count }

    // MARK: - Run with Plugin

    func processWithPlugin(_ plugin: AgentPlugin, input: String) async throws -> String {
        // Use plugin's system prompt with conditional memory
        let memoryContext = memory.getMemoryContext(for: input)
        let fullPrompt = plugin.systemPrompt + memoryContext

        conversationHistory.append(ClaudeMessage(role: "user", content: [.text(input)]))

        // Resolve plugin model (may be a different provider)
        let pluginModel = plugin.model ?? "\(config.providerId)/\(config.model)"
        let resolved = AIProvider.resolve(modelString: pluginModel)
        let pluginProvider = resolved?.provider ?? AIProvider.known[0]
        let resolvedModel = resolved?.model ?? config.model

        // Get API key for the plugin's provider
        let fileConfig = AgentConfigFile.load()
        let pluginKey = fileConfig.getAPIKey(provider: pluginProvider.id) ?? config.apiKey
        let pluginBaseURL = fileConfig.getBaseURL(provider: pluginProvider.id) ?? pluginProvider.defaultBaseURL

        let pluginConfig = AgentConfig(
            apiKey: pluginKey,
            model: resolvedModel,
            maxTokens: config.maxTokens,
            systemPrompt: fullPrompt,
            verbose: config.verbose,
            maxScreenshotWidth: config.maxScreenshotWidth,
            baseURL: pluginBaseURL,
            apiFormat: pluginProvider.format,
            providerId: pluginProvider.id,
            profileName: config.profileName,
            fallbackModels: config.fallbackModels
        )

        let pluginClient = AIClient(config: pluginConfig)
        // Plugins get all tools since they run specialized tasks
        let allTools = ToolDefinitions.allTools + mcpManager.getClaudeTools()

        var finalResponse = ""
        var iterations = 0
        let maxIterations = 25

        aside.start()

        while iterations < maxIterations {
            iterations += 1

            let response = try await pluginClient.sendMessage(
                messages: conversationHistory,
                system: fullPrompt,
                tools: allTools
            )

            var hasToolUse = false
            var assistantContent: [ClaudeContent] = []
            var toolResults: [ClaudeContent] = []

            for content in response.content {
                assistantContent.append(content)
                switch content {
                case .text(let text):
                    if !text.isEmpty {
                        finalResponse += (finalResponse.isEmpty ? "" : "\n") + text
                        printWithPlanFormatting(text)
                    }
                case .toolUse(let id, let name, let input, _):
                    hasToolUse = true
                    printColored("  \(toolIcon(name)) \(name)", color: .yellow)

                    // Approval check (same as processUserInput)
                    let classification = approval.classify(toolName: name, input: input)
                    if !approval.requestApproval(toolName: name, classification: classification, input: input) {
                        toolResults.append(.toolResultText(toolUseId: id, text: "Action denied by user."))
                        continue
                    }

                    if name == "run_subagents" {
                        let subResult = await handleSubAgents(input: input, allTools: allTools)
                        toolResults.append(.toolResultText(toolUseId: id, text: subResult))
                    } else {
                        var (result, base64) = executor.execute(toolName: name, input: input)

                        // Enhance failed tool results with contextual hints
                        if !result.success {
                            let enhanced = enhanceToolError(toolName: name, input: input, error: result.output)
                            let guidance = "\n\n[SYSTEM: This tool call failed. Do NOT fabricate or assume the result. Do NOT take downstream actions based on expected output from this failed call. Instead, inform the user of the failure or try an alternative approach.]"
                            result = ToolResult(success: false, output: enhanced + guidance, screenshot: result.screenshot)
                        } else {
                            resetConsecutiveFailures(toolName: name)
                        }

                        let icon = result.success ? "✓" : "✗"
                        printColored("    \(icon) \(String(result.output.prefix(200)))", color: result.success ? .green : .red)
                        if let b64 = base64 {
                            toolResults.append(.toolResultWithImage(toolUseId: id, text: result.output, imageBase64: b64))
                        } else {
                            toolResults.append(.toolResultText(toolUseId: id, text: result.output))
                        }
                    }
                default: break
                }
            }

            conversationHistory.append(ClaudeMessage(role: "assistant", content: assistantContent))
            if hasToolUse {
                // Check for user asides
                let asides = aside.drain()
                if !asides.isEmpty {
                    let asideText = asides.map { "💬 [USER ASIDE]: \($0)" }.joined(separator: "\n")
                    toolResults.append(.text(asideText))
                }
                conversationHistory.append(ClaudeMessage(role: "user", content: toolResults))
            } else { break }
            if response.stopReason == "end_turn" && !hasToolUse { break }
        }

        aside.stop()
        return finalResponse
    }

    // MARK: - Tool Error Enhancement

    /// Enhance a failed tool result with contextual hints to help the agent self-correct.
    /// Also tracks consecutive failures and escalates when the same tool fails repeatedly.
    private func enhanceToolError(toolName: String, input: [String: AnyCodable], error: String) -> String {
        var enhanced = error

        // --- Contextual hints based on error content ---
        if error.contains("command not found") {
            enhanced += "\n\u{1F4A1} Hint: The command may not be installed. Try `which <command>` or install it with brew."
        }
        if error.lowercased().contains("permission denied") {
            enhanced += "\n\u{1F4A1} Hint: Permission denied. Consider if you need sudo, or check file permissions with `ls -la`."
        }
        if error.contains("No such file") {
            enhanced += "\n\u{1F4A1} Hint: File not found. Use `ls` or `find` to locate the correct path."
        }
        if toolName == "run_applescript" && error.contains("not allowed") {
            enhanced += "\n\u{1F4A1} Hint: AppleScript permission denied. The app may need Accessibility permissions in System Settings."
        }
        if toolName == "click_element" && error.contains("not found") {
            enhanced += "\n\u{1F4A1} Hint: UI element not found. Take a fresh screenshot to see current UI state, then use get_ui_elements to find the correct element."
        }
        if error.lowercased().contains("timeout") || error.lowercased().contains("timed out") {
            enhanced += "\n\u{1F4A1} Hint: Command timed out. Try breaking it into smaller steps or increasing the timeout parameter."
        }
        if error.contains("connection refused") || error.contains("Could not resolve host") {
            enhanced += "\n\u{1F4A1} Hint: Network error. Check if the service is running or the URL is correct."
        }
        if toolName == "run_shell" && error.contains("syntax error") {
            enhanced += "\n\u{1F4A1} Hint: Shell syntax error. Check for unescaped quotes, missing brackets, or incorrect command structure."
        }

        // --- Consecutive failure tracking ---
        let errorPrefix = String(error.prefix(100))
        if consecutiveFailures.toolName == toolName && consecutiveFailures.errorPrefix == errorPrefix {
            consecutiveFailures.count += 1
        } else {
            consecutiveFailures = (toolName: toolName, errorPrefix: errorPrefix, count: 1)
        }

        if consecutiveFailures.count >= 3 {
            enhanced += "\n\u{26D4} This approach has failed \(consecutiveFailures.count) times. Try a completely different strategy."
        }

        return enhanced
    }

    /// Reset consecutive failure counter (call when a tool succeeds)
    private func resetConsecutiveFailures(toolName: String) {
        if consecutiveFailures.toolName == toolName {
            consecutiveFailures = ("", "", 0)
        }
    }

    // MARK: - Tool Detail (show what each tool is doing)

    private func toolDetail(name: String, input: [String: AnyCodable]) -> String {
        switch name {
        case "run_shell":
            let cmd = input["command"]?.stringValue ?? ""
            return String(cmd.prefix(120))
        case "run_applescript":
            let script = input["script"]?.stringValue ?? ""
            let firstLine = script.components(separatedBy: "\n").first ?? ""
            return String(firstLine.prefix(100))
        case "send_email":
            let to = input["to"]?.stringValue ?? ""
            let subj = input["subject"]?.stringValue ?? ""
            return "→ \(to) | \(subj)"
        case "open_app", "activate_app":
            return input["name"]?.stringValue ?? ""
        case "open_url":
            return input["url"]?.stringValue ?? ""
        case "click_element":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            return "(\(x), \(y))"
        case "type_text":
            let text = input["text"]?.stringValue ?? ""
            return String(text.prefix(80))
        case "press_key":
            return input["key"]?.stringValue ?? ""
        case "read_file", "write_file", "list_directory", "file_info":
            return input["path"]?.stringValue ?? ""
        case "get_ui_elements":
            return input["app_name"]?.stringValue ?? ""
        case "save_memory":
            return input["topic"]?.stringValue ?? ""
        case "spotlight_search":
            return input["query"]?.stringValue ?? ""
        case "wait":
            let s = input["seconds"]?.doubleValue ?? 1.0
            return "\(s)s"
        case "schedule_task":
            return input["description"]?.stringValue ?? input["name"]?.stringValue ?? ""
        default:
            if name.hasPrefix("mcp_") {
                // Show first meaningful param for MCP tools
                let meaningful = input.first(where: { $0.key != "type" })
                if let (k, v) = meaningful {
                    return "\(k): \(String(describing: v.value).prefix(80))"
                }
            }
            return ""
        }
    }

    // MARK: - Claude Code Agent Backend

    /// Delegate a task to Claude Code CLI (zero API tokens — uses subscription)
    /// Only reads the final summary, not the full code output
    private func runClaudeCodeAgent(agent: SpecializedAgentDef, input: String) async throws -> String {
        let claudePath = NSHomeDirectory() + "/.local/bin/claude"
        guard FileManager.default.fileExists(atPath: claudePath) else {
            printColored("  \u{26A0} Claude Code not found at \(claudePath)", color: .yellow)
            return ""  // Fall through to normal processing
        }

        printColored("  \u{1F9E0} [\(agent.name)] Delegating to Claude Code (zero API cost)...", color: .magenta)

        // Build the prompt: agent's system prompt + user input
        let fullPrompt: String
        if agent.systemPrompt.isEmpty {
            fullPrompt = input
        } else {
            fullPrompt = "\(agent.systemPrompt)\n\n## Task:\n\(input)"
        }

        // Notify gateway
        if let stream = onStreamText {
            await stream("\u{1F9E0} [\(agent.name)] Delegando a Claude Code...")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--dangerously-skip-permissions", "-p", "--output-format", "text", fullPrompt]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.environment = ProcessInfo.processInfo.environment

        let devNull = FileHandle(forReadingAtPath: "/dev/null")!
        process.standardInput = devNull

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error running Claude Code: \(error)"
        }

        setpgid(process.processIdentifier, process.processIdentifier)

        // Read output — only capture the final text, not streaming
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let fullOutput = String(data: outputData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus

        if exitCode != 0 {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            printColored("  \u{26A0} Claude Code exited with code \(exitCode)", color: .yellow)
            if !stderr.isEmpty {
                return "Claude Code error: \(stderr.prefix(500))"
            }
        }

        // Extract just the conclusion — Claude Code's text output is already the summary
        let result = fullOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.isEmpty {
            return "Claude Code completed but returned no output."
        }

        printColored("  \u{2713} [\(agent.name)] Claude Code finished", color: .green)

        // Stream result to gateway
        if let stream = onStreamText {
            await stream(result)
        }

        return result
    }

    // MARK: - Specialized Agent Execution

    /// Run a specialized agent with its own model/provider and return the final text output.
    private func runSpecializedAgent(
        agent: SpecializedAgentDef,
        resolved: (provider: AIProvider, model: String),
        input: String
    ) async throws -> String {
        let fileConfig = AgentConfigFile.load()
        let agentKey = fileConfig.getAPIKey(provider: resolved.provider.id) ?? config.apiKey
        let agentBaseURL = fileConfig.getBaseURL(provider: resolved.provider.id) ?? resolved.provider.defaultBaseURL

        let agentConfig = AgentConfig(
            apiKey: agentKey,
            model: resolved.model,
            maxTokens: config.maxTokens,
            systemPrompt: agent.systemPrompt,
            verbose: config.verbose,
            maxScreenshotWidth: config.maxScreenshotWidth,
            baseURL: agentBaseURL,
            apiFormat: resolved.provider.format,
            providerId: resolved.provider.id,
            profileName: nil,
            fallbackModels: config.fallbackModels
        )

        let agentClient = AIClient(config: agentConfig)
        let agentExecutor = ToolExecutor()
        agentExecutor.mcpManager = mcpManager

        // Determine tools for this agent
        let tools: [ClaudeTool]
        if let categories = agent.toolCategories {
            let cats = Set(categories.compactMap { ToolCategory(rawValue: $0) })
            tools = ToolDefinitions.tools(for: cats)
        } else {
            // All built-in tools + MCP tools, but no discover_tools or run_subagents to keep it contained
            var allTools = ToolDefinitions.tools(for: Set(ToolCategory.allCases))
            allTools = allTools.filter { $0.name != "run_subagents" }
            allTools += mcpManager.getClaudeTools()
            tools = allTools
        }

        // Show routing indicator
        printColored("  \u{1F916} [\(agent.name)] using \(agent.model)", color: .magenta)

        // Run the specialized agent conversation
        var messages: [ClaudeMessage] = [
            ClaudeMessage(role: "user", content: [.text(input)])
        ]

        var finalOutput = ""
        let maxIter = agent.maxIterations ?? 15

        for _ in 0..<maxIter {
            if isCancelled {
                printColored("\n  \u{26A0} Specialized agent cancelled", color: .yellow)
                break
            }

            // Check spending limits
            if let limitError = spendingGuard.checkLimits() {
                throw AgentError.permissionDenied(limitError)
            }

            let response = try await agentClient.sendMessage(
                messages: messages,
                system: agent.systemPrompt,
                tools: tools
            )

            // Track tokens in main context manager
            context.recordUsage(response.usage)

            var hasToolUse = false
            var assistantContent: [ClaudeContent] = []
            var toolResults: [ClaudeContent] = []

            for content in response.content {
                assistantContent.append(content)

                switch content {
                case .text(let text):
                    if !text.isEmpty {
                        finalOutput = text
                        // Stream text to gateway if connected
                        if let stream = onStreamText {
                            await stream(text)
                        }
                    }
                case .toolUse(let id, let name, let toolInput, _):
                    hasToolUse = true
                    let icon = toolIcon(name)
                    printColored("  \(icon) [\(agent.name)] \(name)", color: .gray)

                    // Execute the tool
                    if mcpManager.canHandle(toolName: name) {
                        let args = toolInput.mapValues { $0.value }
                        let result = mcpManager.executeTool(qualifiedName: name, arguments: args)
                        toolResults.append(.toolResultText(toolUseId: id, text: result.output))
                    } else {
                        let (result, screenshotBase64) = agentExecutor.execute(toolName: name, input: toolInput)
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
        }

        return finalOutput
    }

    // MARK: - Tool Icons

    private func toolIcon(_ name: String) -> String {
        if name.hasPrefix("mcp_") { return "🔌" }
        switch name {
        case "run_applescript": return "🍎"
        case "run_shell": return "💻"
        case "spotlight_search": return "🔍"
        case "list_apps": return "📋"
        case "get_frontmost_app": return "🎯"
        case "activate_app", "open_app": return "🚀"
        case "get_ui_elements": return "🌳"
        case "click_element": return "👆"
        case "mouse_move": return "🖱️"
        case "scroll": return "📜"
        case "drag": return "✋"
        case "type_text": return "⌨️"
        case "press_key": return "⚡"
        case "take_screenshot": return "📸"
        case "list_windows": return "🪟"
        case "move_window", "resize_window": return "📐"
        case "open_url": return "🌐"
        case "read_clipboard", "write_clipboard": return "📎"
        case "get_screen_size": return "📏"
        case "wait": return "⏳"
        case "read_file", "write_file", "list_directory", "file_info": return "📂"
        case "save_memory", "read_memory": return "🧠"
        case "run_subagents": return "🔀"
        case "mcp_search": return "🔍"
        case "mcp_install": return "📦"
        case "read_program", "edit_program": return "📋"
        case "read_system_prompt", "edit_system_prompt": return "🧬"
        case "log_improvement", "read_improvement_log": return "📈"
        case "schedule_task": return "📅"
        case "list_tasks": return "📋"
        case "cancel_task": return "🗑️"
        case "modify_config": return "⚙️"
        case "create_plugin": return "🔌"
        case "send_email": return "✉️"
        case "discover_tools": return "🔧"
        default: return "⚡"
        }
    }
}

// MARK: - ANSI Colors

enum ANSIColor: String {
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case gray = "\u{001B}[90m"
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
}

func printColored(_ text: String, color: ANSIColor) {
    TerminalDisplay.shared.writeLine("\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)")
}

/// Prints model text with special formatting for plan blocks and step progress.
func printWithPlanFormatting(_ text: String) {
    let hasPlan = text.contains("📋 Plan:") || text.contains("📋Plan:")
    let hasProgress = text.contains("✅ Step") || text.contains("⏳ Step")

    guard hasPlan || hasProgress else {
        printColored(text, color: .cyan)
        return
    }

    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var inPlanBox = false
    let boxWidth = 44
    let bar = String(repeating: "─", count: boxWidth)

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("📋") {
            TerminalDisplay.shared.writeLine("\(ANSIColor.magenta.rawValue)┌\(bar)┐\(ANSIColor.reset.rawValue)")
            let padded = trimmed.padding(toLength: boxWidth - 1, withPad: " ", startingAt: 0)
            TerminalDisplay.shared.writeLine("\(ANSIColor.bold.rawValue)\(ANSIColor.magenta.rawValue)│ \(padded)│\(ANSIColor.reset.rawValue)")
            inPlanBox = true
        } else if inPlanBox {
            if let first = trimmed.first, first.isNumber || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                let padded = trimmed.padding(toLength: boxWidth - 1, withPad: " ", startingAt: 0)
                TerminalDisplay.shared.writeLine("\(ANSIColor.magenta.rawValue)│ \(ANSIColor.cyan.rawValue)\(padded)\(ANSIColor.magenta.rawValue)│\(ANSIColor.reset.rawValue)")
            } else {
                TerminalDisplay.shared.writeLine("\(ANSIColor.magenta.rawValue)└\(bar)┘\(ANSIColor.reset.rawValue)")
                inPlanBox = false
                if trimmed.hasPrefix("✅") {
                    TerminalDisplay.shared.writeLine("\(ANSIColor.green.rawValue)\(line)\(ANSIColor.reset.rawValue)")
                } else if trimmed.hasPrefix("⏳") {
                    TerminalDisplay.shared.writeLine("\(ANSIColor.yellow.rawValue)\(line)\(ANSIColor.reset.rawValue)")
                } else if !trimmed.isEmpty {
                    printColored(line, color: .cyan)
                }
            }
        } else if trimmed.hasPrefix("✅") {
            TerminalDisplay.shared.writeLine("\(ANSIColor.green.rawValue)\(line)\(ANSIColor.reset.rawValue)")
        } else if trimmed.hasPrefix("⏳") {
            TerminalDisplay.shared.writeLine("\(ANSIColor.yellow.rawValue)\(line)\(ANSIColor.reset.rawValue)")
        } else {
            printColored(line, color: .cyan)
        }
    }

    if inPlanBox {
        TerminalDisplay.shared.writeLine("\(ANSIColor.magenta.rawValue)└\(bar)┘\(ANSIColor.reset.rawValue)")
    }
}
