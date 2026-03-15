import Foundation
import AppKit

// MARK: - Terminal-safe print override
// Routes all print() through TerminalDisplay so output doesn't corrupt the
// always-active LineEditor input line. When no editor is active, behaves
// identically to Swift.print().

func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let text = items.map { String(describing: $0) }.joined(separator: separator)
    if terminator == "\n" {
        TerminalDisplay.shared.writeLine(text)
    } else {
        TerminalDisplay.shared.writeInline(text + terminator)
    }
}

// MARK: - Desktop Agent CLI

@main
struct DesktopAgentCLI {
    static let lineEditor = LineEditor()

    static func main() async {
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        let args = CommandLine.arguments
        if args.contains("--help") || args.contains("-h") {
            printUsage()
            return
        }

        // --- Self-update: osai update ---
        if args.contains("update") {
            selfUpdate()
            return
        }

        // --- Doctor: osai doctor ---
        if args.contains("doctor") {
            runDoctor()
            return
        }

        // --- Version: osai version / osai --version ---
        if args.contains("version") || args.contains("--version") || args.contains("-V") {
            Swift.print("osai v3.0 (build \(buildHash()))")
            return
        }

        // --- First-run onboarding ---
        let isFirstRun = !FileManager.default.fileExists(atPath: AgentConfigFile.configPath)
        if isFirstRun && isatty(STDIN_FILENO) != 0 && !args.contains("gateway") {
            runOnboarding()
        }

        let config = AgentConfig.load()

        // Install built-in plugins & skills
        PluginManager.installBuiltins()
        SkillManager.installBuiltins()

        // Retry any pending deliveries from previous runs
        let retried = await DeliveryQueue.retryPending()
        if retried > 0 {
            printColored("  \u{1F4EC} Retried \(retried) pending deliveries", color: .green)
        }

        // Start MCP servers from config
        let mcpManager = MCPManager()
        let fileConfig = AgentConfigFile.load()
        mcpManager.startFromConfig(fileConfig)

        // --- Script mode: osai run script.md ---
        if args.count >= 3 && args[1] == "run" {
            let scriptPath: String
            let rawPath = (args[2] as NSString).expandingTildeInPath
            if rawPath.hasPrefix("/") {
                scriptPath = rawPath
            } else {
                scriptPath = FileManager.default.currentDirectoryPath + "/" + rawPath
            }
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                printColored("  Error: file not found: \(scriptPath)", color: .red)
                return
            }
            do {
                let contents = try String(contentsOfFile: scriptPath, encoding: .utf8)
                guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    printColored("  Error: script file is empty", color: .red)
                    return
                }
                let agent = AgentLoop(config: config, mcpManager: mcpManager)
                agent.approval.autoApprove = true
                _ = try await agent.processUserInput(contents)
            } catch {
                printColored("  Error reading script: \(error.localizedDescription)", color: .red)
            }
            mcpManager.stopAll()
            return
        }

        // --- Watch mode: osai watch "prompt" [--interval 5m] ---
        if args.count >= 3 && args[1] == "watch" {
            let interval = parseWatchInterval(args)
            let prompt = args.dropFirst(2).filter { !$0.hasPrefix("--") }.joined(separator: " ")
            guard !prompt.isEmpty else {
                printColored("  Usage: osai watch \"check something\" [--interval 5m]", color: .yellow)
                mcpManager.stopAll()
                return
            }
            await runWatch(prompt: prompt, interval: interval, config: config, mcpManager: mcpManager)
            mcpManager.stopAll()
            return
        }

        // --- Gateway mode: osai gateway ---
        if args.contains("gateway") {
            let gwConfig = fileConfig.gateways ?? GatewayConfig()
            let server = GatewayServer(config: config, mcpManager: mcpManager, gatewayConfig: gwConfig)
            await server.start()
            server.stop()
            mcpManager.stopAll()
            return
        }

        // --- Single command mode (no banner, no status) ---
        // osai "do something"
        // osai --deliver discord:channelId "do something"
        // echo "do something" | osai
        var commandArgs: [String] = []
        var deliverTarget: String? = nil
        var taskId: String? = nil
        var skipNext = false
        for (i, arg) in args.enumerated() {
            if i == 0 { continue }
            if skipNext { skipNext = false; continue }
            if arg == "--model" { skipNext = true; continue }
            if arg == "--profile" { skipNext = true; continue }
            if arg == "--verbose" || arg == "-v" { continue }
            if arg == "gateway" { continue }
            if arg == "--deliver" { skipNext = true; deliverTarget = args.count > i + 1 ? args[i + 1] : nil; continue }
            if arg == "--task-id" { skipNext = true; taskId = args.count > i + 1 ? args[i + 1] : nil; continue }
            commandArgs.append(arg)
        }

        // Check for piped stdin
        var pipeInput: String? = nil
        if isatty(STDIN_FILENO) == 0 {
            if let data = FileHandle.standardInput.availableData as Data?, !data.isEmpty {
                pipeInput = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let singleCommand = !commandArgs.isEmpty
            ? commandArgs.joined(separator: " ")
            : pipeInput

        if let command = singleCommand, !command.isEmpty {
            let agent = AgentLoop(config: config, mcpManager: mcpManager)
            agent.approval.autoApprove = true  // One-shot/task mode: no prompts
            do {
                let response = try await agent.processUserInput(command)

                // Deliver result to gateway if --deliver specified
                if let target = deliverTarget {
                    let msg = response.isEmpty
                        ? "⚠️ Task completed but produced no output.\nCommand: \(String(command.prefix(100)))"
                        : response
                    await deliverToGateway(target: target, message: msg)
                }

                // Mark task as run
                if let tid = taskId {
                    TaskScheduler.markRun(id: tid)
                }
            } catch {
                printColored("Error: \(error)", color: .red)
                if let target = deliverTarget {
                    await deliverToGateway(target: target, message: "❌ Task error: \(error.localizedDescription)\nCommand: \(String(command.prefix(100)))")
                }
                if let tid = taskId {
                    TaskScheduler.markRun(id: tid)
                }
            }
            mcpManager.stopAll()
            return
        }

        // --- Interactive mode (full UI) ---
        printBanner()

        if config.apiKey.isEmpty {
            printColored("  No API key found for '\(config.providerId)'.", color: .yellow)
            printHint("Set it with:  /config set-key \(config.providerId) YOUR_API_KEY")
            printHint("Or import from openclaw:  /config import-openclaw")
            print()
        }

        // Status line
        let providerName = AIProvider.find(id: config.providerId)?.name ?? config.providerId
        let profileSuffix = config.profileName.map { " | profile: \($0)" } ?? ""
        printDim("  \(providerName) / \(config.model)\(profileSuffix)")

        // Check permissions
        let acc = AccessibilityDriver()
        let hasAX = acc.checkPermissions()
        let vis = VisionDriver()
        let hasScreen = vis.takeScreenshot().success
        let axIcon = hasAX ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[33m⚠\u{001B}[0m"
        let scrIcon = hasScreen ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[33m⚠\u{001B}[0m"
        printDim("  \(axIcon) Accessibility  \(scrIcon) Screen Recording")

        let mcpCount = mcpManager.connectedServers.count
        if mcpCount > 0 {
            printDim("  🔌 \(mcpCount) MCP server\(mcpCount == 1 ? "" : "s") connected")
        }

        print()
        printDim("  Type /help for commands, Tab to autocomplete")
        await runInteractive(config: config, mcpManager: mcpManager)
        mcpManager.stopAll()
    }

    // MARK: - Interactive Mode

    // These must be nonisolated(unsafe) for signal handler / cross-thread access
    nonisolated(unsafe) static var activeAgent: AgentLoop?
    nonisolated(unsafe) static var lastSigintNs: UInt64 = 0
    nonisolated(unsafe) static var savedTermios = termios()
    nonisolated(unsafe) static var hasSavedTermios = false
    // Chat mode: mutable state accessible from input thread
    nonisolated(unsafe) static var chatConfig: AgentConfig?
    nonisolated(unsafe) static var chatAgent: AgentLoop?
    // Session persistence
    nonisolated(unsafe) static var currentSessionId: String = UUID().uuidString
    nonisolated(unsafe) static var currentSessionName: String?
    nonisolated(unsafe) static var sessionFirstMessage: String?
    nonisolated(unsafe) static var sessionTurnCount: Int = 0
    nonisolated(unsafe) static var sessionTotalTokens: Int = 0

    // Usage display level: cycles off → tokens → full → off
    enum UsageDisplayLevel: Int, CaseIterable {
        case off = 0
        case tokens = 1
        case full = 2

        var next: UsageDisplayLevel {
            let all = UsageDisplayLevel.allCases
            let nextIdx = (rawValue + 1) % all.count
            return all[nextIdx]
        }

        var label: String {
            switch self {
            case .off: return "off"
            case .tokens: return "tokens"
            case .full: return "full (tokens + cost)"
            }
        }
    }
    nonisolated(unsafe) static var usageDisplayLevel: UsageDisplayLevel = .full

    /// Save terminal state before entering raw mode (called once at interactive start)
    static func saveTerminal() {
        tcgetattr(STDIN_FILENO, &savedTermios)
        hasSavedTermios = true
    }

    /// Restore terminal to normal mode (safe to call from signal handler)
    static func restoreTerminal() {
        if hasSavedTermios {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios)
        }
    }

    static func runInteractive(config: AgentConfig, mcpManager: MCPManager) async {
        var currentConfig = config
        var agent = AgentLoop(config: currentConfig, mcpManager: mcpManager)

        // Publish state for input thread prompt building
        chatConfig = currentConfig
        chatAgent = agent

        // Disable AsideMonitor — LineEditor owns stdin in chat mode
        agent.aside.disabled = true

        // Session: check for a previous auto-saved session to resume
        if SessionManager.hasCurrentSession(),
           let session = SessionManager.load(id: "current") {
            let ago = Int(Date().timeIntervalSince(session.info.updatedAt))
            let agoStr: String
            if ago < 60 { agoStr = "\(ago)s ago" }
            else if ago < 3600 { agoStr = "\(ago / 60)m ago" }
            else if ago < 86400 { agoStr = "\(ago / 3600)h ago" }
            else { agoStr = "\(ago / 86400)d ago" }
            printColored("  Previous session found: \"\(session.info.name)\" (\(session.info.turnCount) turns, \(agoStr))", color: .cyan)
            printDim("  Type /session resume to continue, or /new to start fresh.")
            print()
        }

        // Save terminal state before anything touches raw mode
        saveTerminal()

        // SIGINT handler — safety net for when raw mode is off between readInput calls.
        // Primary Ctrl+C handling is in LineEditor (ISIG off, catches \u{03} directly).
        signal(SIGINT) { _ in
            let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            if DesktopAgentCLI.activeAgent != nil {
                let elapsed = nowNs - DesktopAgentCLI.lastSigintNs
                if DesktopAgentCLI.lastSigintNs != 0 && elapsed < 2_000_000_000 {
                    DesktopAgentCLI.restoreTerminal()
                    _exit(1)
                }
                DesktopAgentCLI.lastSigintNs = nowNs
                DesktopAgentCLI.activeAgent?.cancel()
                let msg = "\n\u{001B}[33m  ⚠ Cancelling... (Ctrl+C again to force quit)\u{001B}[0m\n"
                _ = msg.withCString { ptr in write(STDOUT_FILENO, ptr, strlen(ptr)) }
            } else {
                DesktopAgentCLI.restoreTerminal()
                _exit(0)
            }
        }

        // Start continuous input on a dedicated thread.
        // The LineEditor stays active between messages — user can always type.
        // While agent processes, output streams above via TerminalDisplay coordination.
        let inputStream = lineEditor.startContinuousInput(promptBuilder: {
            if DesktopAgentCLI.lineEditor.agentBusy {
                // Minimal prompt while agent works — user can still type asides
                return "  \u{001B}[90m···\u{001B}[0m "
            }
            let cfg = DesktopAgentCLI.chatConfig ?? config
            let ctx = DesktopAgentCLI.chatAgent?.context
            return buildPrompt(config: cfg, context: ctx)
        })

        for await inputResult in inputStream {
            let input = inputResult.text
            if input.isEmpty && !inputResult.hasImages { continue }

            // Show paste summary if large paste was collapsed
            if inputResult.pastedLines > 0 {
                TerminalDisplay.shared.writeLine("  \u{001B}[90m📋 Pasted \(inputResult.pastedLines) lines (\(input.count) chars)\u{001B}[0m")
            }

            // Show image attachment info
            for img in inputResult.images {
                let filename = (img.path as NSString).lastPathComponent
                let size = (try? FileManager.default.attributesOfItem(atPath: img.path)[.size] as? Int) ?? 0
                let sizeStr = size > 1_000_000 ? "\(size / 1_000_000)MB" : "\(size / 1_000)KB"
                TerminalDisplay.shared.writeLine("  \u{001B}[35m📎 \(filename) (\(sizeStr), \(img.mediaType))\u{001B}[0m")
            }

            // --- Slash Commands ---
            if input.hasPrefix("/") && !inputResult.hasImages {
                let result = await handleSlashCommand(input, agent: agent, config: &currentConfig, mcpManager: mcpManager)
                if result == .quit { return }
                if result == .handled {
                    chatConfig = currentConfig  // sync in case config changed
                    continue
                }
                if result == .reload {
                    agent = AgentLoop(config: currentConfig, mcpManager: mcpManager)
                    agent.aside.disabled = true
                    chatConfig = currentConfig
                    chatAgent = agent
                    continue
                }
                if result == .passthrough {
                    let suggestion = suggestCommand(input)
                    if let s = suggestion {
                        TerminalDisplay.shared.writeLine("  \u{001B}[33mUnknown command. Did you mean \u{001B}[1m\(s)\u{001B}[0m\u{001B}[33m?\u{001B}[0m")
                    } else {
                        TerminalDisplay.shared.writeLine("  \u{001B}[33mUnknown command. Type /help for available commands.\u{001B}[0m")
                    }
                    continue
                }
            }

            // Check API key before sending
            if currentConfig.apiKey.isEmpty {
                TerminalDisplay.shared.writeLine("  \u{001B}[31mNo API key set.\u{001B}[0m")
                TerminalDisplay.shared.writeLine("  \u{001B}[90mUse: /config set-key \(currentConfig.providerId) YOUR_KEY\u{001B}[0m")
                continue
            }

            // Process with agent
            do {
                // Chat-style: echo user message with visual separator
                TerminalDisplay.shared.writeLine("")
                TerminalDisplay.shared.writeLine("\u{001B}[90m  ─────────────────────────────────────────\u{001B}[0m")
                TerminalDisplay.shared.writeLine("  \u{001B}[1m❯\u{001B}[0m \(input)")
                TerminalDisplay.shared.writeLine("")

                activeAgent = agent
                lineEditor.agentBusy = true
                agent.resetCancel()
                if inputResult.hasImages {
                    _ = try await agent.processUserInputWithImages(input, images: inputResult.images)
                } else {
                    _ = try await agent.processUserInput(input)
                }
                activeAgent = nil
                lineEditor.agentBusy = false
                if agent.context.turnCount > 0 {
                    if let usageLine = formatUsageLine(context: agent.context) {
                        TerminalDisplay.shared.writeLine("  \u{001B}[90m\(usageLine)\u{001B}[0m")
                    } else {
                        // Still consume the turn summary to reset compaction display state
                        _ = agent.context.consumeTurnSummary()
                    }
                }
                TerminalDisplay.shared.writeLine("")

                // Auto-save session
                if sessionFirstMessage == nil { sessionFirstMessage = input }
                sessionTurnCount += 1
                let name = currentSessionName ?? SessionManager.generateName(from: sessionFirstMessage ?? input)
                currentSessionName = name
                let info = SessionInfo(
                    id: currentSessionId,
                    name: name,
                    model: currentConfig.model,
                    createdAt: Date(),
                    updatedAt: Date(),
                    turnCount: sessionTurnCount,
                    totalTokens: sessionTotalTokens
                )
                SessionManager.save(id: "current", info: info, messages: agent.currentHistory)
            } catch let error as AgentError {
                activeAgent = nil
                lineEditor.agentBusy = false
                TerminalDisplay.shared.writeLine("\n  \u{001B}[31mError: \(error.description)\u{001B}[0m\n")
            } catch {
                activeAgent = nil
                lineEditor.agentBusy = false
                TerminalDisplay.shared.writeLine("\n  \u{001B}[31mError: \(error.localizedDescription)\u{001B}[0m\n")
            }
        }

        // Stream ended (EOF)
        TerminalDisplay.shared.writeLine("")
        TerminalDisplay.shared.writeLine("  \u{001B}[90mGoodbye!\u{001B}[0m")
    }

    // MARK: - Prompt Builder

    static func buildPrompt(config: AgentConfig, context: ContextManager? = nil) -> String {
        let provider = AIProvider.find(id: config.providerId)?.name ?? config.providerId
        // Short model name: "claude-sonnet-4" from "claude-sonnet-4-20250514"
        let parts = config.model.split(separator: "-")
        let shortModel: String
        if parts.count > 3, let _ = Int(String(parts.last ?? "")) {
            shortModel = parts.dropLast().joined(separator: "-")
        } else {
            shortModel = config.model
        }
        let contextIndicator = context?.promptIndicator ?? ""
        return "\(contextIndicator)\u{001B}[90m\(provider)/\(shortModel)\u{001B}[0m \u{001B}[1m>\u{001B}[0m "
    }

    // MARK: - Command Suggestion (fuzzy match)

    static func suggestCommand(_ input: String) -> String? {
        let cmd = input.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let commands = ["/help", "/quit", "/exit", "/clear", "/config", "/model",
                       "/mcp", "/plugin", "/memory", "/skill", "/task", "/gateway",
                       "/fallback", "/apps", "/windows", "/screen", "/perms",
                       "/verbose", "/yolo", "/context", "/compact",
                       "/save", "/sessions", "/session", "/new"]

        // Find closest match by edit distance or prefix
        var bestMatch: String?
        var bestScore = 0

        for c in commands {
            // Common chars score
            let score = zip(cmd, c).filter { $0 == $1 }.count
            if score > bestScore && score >= cmd.count / 2 {
                bestScore = score
                bestMatch = c
            }
            // Prefix match
            if c.hasPrefix(cmd) || cmd.hasPrefix(c) {
                return c
            }
        }
        return bestMatch
    }

    // MARK: - Slash Command Handler

    enum CommandResult { case handled, quit, passthrough, reload }

    static func handleSlashCommand(_ input: String, agent: AgentLoop, config: inout AgentConfig, mcpManager: MCPManager) async -> CommandResult {
        let parts = input.split(separator: " ", maxSplits: 10).map(String.init)
        let command = parts[0].lowercased()
        let args = Array(parts.dropFirst())

        switch command {

        // --- Basic ---
        case "/quit", "/exit", "/q":
            printColored("  Goodbye!", color: .gray)
            return .quit

        case "/clear":
            agent.clearHistory()
            return .handled

        case "/help":
            printHelp()
            return .handled

        case "/verbose":
            printHint("Set DESKTOP_AGENT_VERBOSE=1 to enable verbose mode")
            return .handled

        case "/yolo":
            agent.approval.autoApprove.toggle()
            if agent.approval.autoApprove {
                printColored("  ⚡ YOLO mode ON — all actions auto-approved", color: .yellow)
            } else {
                printColored("  🛡 YOLO mode OFF — dangerous actions require approval", color: .green)
            }
            return .handled

        case "/usage":
            usageDisplayLevel = usageDisplayLevel.next
            printColored("  Usage display: \(usageDisplayLevel.label)", color: .cyan)
            return .handled

        case "/status":
            printStatus(agent: agent, config: config)
            return .handled

        case "/context", "/ctx":
            print()
            print(agent.context.fullStatus)
            printDim("  Model: \(config.model)")
            printDim("  Messages: \(agent.historyCount)")
            print()
            print("  \(agent.orchestrator.stats)")
            print()
            return .handled

        case "/compact":
            if agent.historyCount < 6 {
                printDim("  Not enough history to compact.")
            } else {
                printColored("  Compacting...", color: .magenta)
                // Trigger compaction on next turn by temporarily lowering threshold
                printHint("Compaction will happen automatically or use /clear to reset.")
            }
            return .handled

        // --- Config ---
        case "/config":
            return handleConfig(args: args, config: &config)

        // --- Model ---
        case "/model":
            return handleModel(args: args, config: &config)

        // --- System Info ---
        case "/apps":
            let driver = AppleScriptDriver()
            let apps = driver.listRunningApps()
            for app in apps {
                let active = app.isActive ? " \u{001B}[32m[ACTIVE]\u{001B}[0m" : ""
                printColored("  \(app.name) \u{001B}[90m(pid: \(app.pid)) \(app.bundleId ?? "")\u{001B}[0m\(active)", color: .cyan)
            }
            return .handled

        case "/windows":
            let acc = AccessibilityDriver()
            let windows = acc.listWindows()
            for w in windows { printColored("  \(w.description)", color: .cyan) }
            if windows.isEmpty { printDim("  No windows") }
            return .handled

        case "/screen":
            let vision = VisionDriver()
            let ts = Int(Date().timeIntervalSince1970)
            let path = NSHomeDirectory() + "/Desktop/screenshot_\(ts).jpg"
            let result = vision.saveScreenshot(to: path)
            printColored("  \(result.output)", color: result.success ? .green : .red)
            return .handled

        case "/perms":
            let acc = AccessibilityDriver()
            let vis = VisionDriver()
            let axOk = acc.checkPermissions()
            let scrOk = vis.takeScreenshot().success
            printColored("  Accessibility:    \(axOk ? "✓ granted" : "✗ denied")", color: axOk ? .green : .red)
            printColored("  Screen Recording: \(scrOk ? "✓ granted" : "✗ denied")", color: scrOk ? .green : .red)
            if !axOk || !scrOk {
                printHint("Grant permissions in System Settings > Privacy & Security")
            }
            return .handled

        // --- MCP ---
        case "/mcp":
            handleMCP(args: args, mcpManager: mcpManager)
            return .handled

        // --- Plugins ---
        case "/plugin":
            await handlePlugin(args: args, agent: agent, config: config, mcpManager: mcpManager)
            return .handled

        // --- Memory ---
        case "/memory":
            handleMemory(args: args)
            return .handled

        // --- Skills ---
        case "/skill", "/skills":
            handleSkill(args: args)
            return .handled

        // --- Tasks ---
        case "/task", "/tasks":
            handleTask(args: args)
            return .handled

        // --- Profiles ---
        case "/profile", "/profiles":
            return handleProfile(args: args, config: &config)

        // --- Program / Self-Improvement ---
        case "/program":
            handleProgram(args: args)
            return .handled

        case "/improve":
            // Send self-improvement request to the agent
            let task = args.isEmpty
                ? "Review your current program.md, system prompt, and improvement log. Identify what could be improved about your behavior, tools, or approach. Make specific changes and log them."
                : args.joined(separator: " ")
            do {
                print()
                _ = try await agent.processUserInput("Self-improve: \(task)")
                print()
            } catch {
                printColored("  Error: \(error)", color: .red)
            }
            return .handled

        case "/watch":
            guard !args.isEmpty else {
                printColored("  Usage: /watch <prompt> [--interval 5m]", color: .yellow)
                printDim("  Example: /watch check if there's a new email from X")
                printDim("  Options: --interval 30s | 5m | 1h (default: 5m)")
                return .handled
            }
            // Parse interval from args
            var promptParts: [String] = []
            var watchInterval: TimeInterval = 300
            var skipNextArg = false
            for (idx, arg) in args.enumerated() {
                if skipNextArg { skipNextArg = false; continue }
                if (arg == "--interval" || arg == "--every"), idx + 1 < args.count {
                    let value = args[idx + 1]
                    if value.hasSuffix("s"), let n = Double(value.dropLast()) { watchInterval = n }
                    else if value.hasSuffix("m"), let n = Double(value.dropLast()) { watchInterval = n * 60 }
                    else if value.hasSuffix("h"), let n = Double(value.dropLast()) { watchInterval = n * 3600 }
                    else if let n = Double(value) { watchInterval = n }
                    skipNextArg = true
                    continue
                }
                promptParts.append(arg)
            }
            let watchPrompt = promptParts.joined(separator: " ")
            guard !watchPrompt.isEmpty else {
                printColored("  Error: no prompt provided", color: .red)
                return .handled
            }
            agent.approval.autoApprove = true
            let watchUnit = formatWatchInterval(watchInterval)
            printColored("\n  \u{1F441} Watch mode: checking every \(watchUnit)", color: .cyan)
            printDim("  \u{1F4CB} \(watchPrompt)")
            printDim("  Type /quit or Ctrl+C to stop\n")
            var watchIteration = 0
            while true {
                watchIteration += 1
                let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                printColored("  \u{23F1} [\(ts)] Check #\(watchIteration)...", color: .yellow)
                do {
                    let response = try await agent.processUserInput(watchPrompt)
                    if !response.isEmpty { print(response) }
                } catch {
                    printColored("  \u{26A0} Error: \(error.localizedDescription)", color: .yellow)
                }
                printDim("  \u{1F4A4} Next check in \(watchUnit)...\n")
                try? await Task.sleep(nanoseconds: UInt64(watchInterval * 1_000_000_000))
            }

        case "/fallback", "/fallbacks":
            return handleFallback(args: args, config: &config)

        case "/gateway":
            handleGateway(args: args)
            return .handled

        // --- Sessions ---
        case "/save":
            return handleSessionSave(agent: agent, config: config)

        case "/sessions":
            return handleSessionList()

        case "/session":
            return handleSession(args: args, agent: agent, config: config)

        case "/new":
            return handleSessionNew(agent: agent)

        default:
            return .passthrough
        }
    }

    // MARK: - Session Commands

    static func handleSessionSave(agent: AgentLoop, config: AgentConfig) -> CommandResult {
        let history = agent.currentHistory
        guard !history.isEmpty else {
            printDim("  Nothing to save — conversation is empty.")
            return .handled
        }

        let name = currentSessionName ?? SessionManager.generateName(from: sessionFirstMessage ?? "untitled")
        currentSessionName = name
        let info = SessionInfo(
            id: currentSessionId,
            name: name,
            model: config.model,
            createdAt: Date(),
            updatedAt: Date(),
            turnCount: sessionTurnCount,
            totalTokens: sessionTotalTokens
        )
        SessionManager.save(id: currentSessionId, info: info, messages: history)
        let shortId = String(currentSessionId.prefix(8))
        printColored("  Session saved: \"\(name)\" [\(shortId)]", color: .green)
        return .handled
    }

    static func handleSessionList() -> CommandResult {
        let sessions = SessionManager.listRecent(limit: 10)
        if sessions.isEmpty {
            printDim("  No saved sessions.")
            return .handled
        }
        print()
        printColored("  Saved sessions:", color: .cyan)
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        for (i, s) in sessions.enumerated() {
            let shortId = String(s.id.prefix(8))
            let date = fmt.string(from: s.updatedAt)
            printColored("  \(i + 1). \(s.name) \u{001B}[90m[\(shortId)] \(s.turnCount) turns, \(date)\u{001B}[0m", color: .reset)
        }
        print()
        printDim("  Use /session load <number> to resume")
        return .handled
    }

    static func handleSession(args: [String], agent: AgentLoop, config: AgentConfig) -> CommandResult {
        let sub = args.first ?? "list"

        switch sub {
        case "list":
            return handleSessionList()

        case "load", "resume":
            let target = args.count > 1 ? args[1] : nil

            // /session resume — load current auto-saved session
            if sub == "resume" || target == nil {
                guard let session = SessionManager.load(id: "current") else {
                    printDim("  No session to resume.")
                    return .handled
                }
                agent.restoreHistory(session.messages)
                currentSessionId = session.info.id
                currentSessionName = session.info.name
                sessionFirstMessage = session.info.name
                sessionTurnCount = session.info.turnCount
                sessionTotalTokens = session.info.totalTokens
                printColored("  Resumed session: \"\(session.info.name)\" (\(session.messages.count) messages)", color: .green)
                return .handled
            }

            // Try number first, then ID prefix
            let sessions = SessionManager.listRecent(limit: 20)
            var found: (info: SessionInfo, messages: [ClaudeMessage])?

            if let num = Int(target!), num >= 1, num <= sessions.count {
                let id = sessions[num - 1].id
                found = SessionManager.load(id: id)
            } else {
                // Match by ID prefix
                let prefix = target!.lowercased()
                if let match = sessions.first(where: { $0.id.lowercased().hasPrefix(prefix) }) {
                    found = SessionManager.load(id: match.id)
                }
            }

            guard let session = found else {
                printColored("  Session not found.", color: .red)
                return .handled
            }

            agent.restoreHistory(session.messages)
            currentSessionId = session.info.id
            currentSessionName = session.info.name
            sessionFirstMessage = session.info.name
            sessionTurnCount = session.info.turnCount
            sessionTotalTokens = session.info.totalTokens
            printColored("  Loaded session: \"\(session.info.name)\" (\(session.messages.count) messages)", color: .green)
            return .handled

        case "delete":
            guard args.count > 1 else {
                printDim("  Usage: /session delete <number-or-id>")
                return .handled
            }
            let target = args[1]
            let sessions = SessionManager.listRecent(limit: 20)

            if let num = Int(target), num >= 1, num <= sessions.count {
                let s = sessions[num - 1]
                SessionManager.delete(id: s.id)
                printColored("  Deleted session: \"\(s.name)\"", color: .green)
            } else {
                let prefix = target.lowercased()
                if let match = sessions.first(where: { $0.id.lowercased().hasPrefix(prefix) }) {
                    SessionManager.delete(id: match.id)
                    printColored("  Deleted session: \"\(match.name)\"", color: .green)
                } else {
                    printColored("  Session not found.", color: .red)
                }
            }
            return .handled

        default:
            printDim("  Usage: /session list | load <id> | resume | delete <id>")
            return .handled
        }
    }

    static func handleSessionNew(agent: AgentLoop) -> CommandResult {
        agent.clearHistory()
        SessionManager.deleteCurrent()
        currentSessionId = UUID().uuidString
        currentSessionName = nil
        sessionFirstMessage = nil
        sessionTurnCount = 0
        sessionTotalTokens = 0
        printColored("  New session started.", color: .green)
        return .handled
    }

    // MARK: - Watch Mode

    static func parseWatchInterval(_ args: [String]) -> TimeInterval {
        for (i, arg) in args.enumerated() {
            if (arg == "--interval" || arg == "--every"), i + 1 < args.count {
                let value = args[i + 1]
                if value.hasSuffix("s"), let n = Double(value.dropLast()) { return n }
                if value.hasSuffix("m"), let n = Double(value.dropLast()) { return n * 60 }
                if value.hasSuffix("h"), let n = Double(value.dropLast()) { return n * 3600 }
                if let n = Double(value) { return n } // bare number = seconds
            }
        }
        return 300 // default 5 minutes
    }

    static func formatWatchInterval(_ interval: TimeInterval) -> String {
        if interval >= 3600 { return "\(Int(interval / 3600))h" }
        if interval >= 60 { return "\(Int(interval / 60))m" }
        return "\(Int(interval))s"
    }

    static func runWatch(prompt: String, interval: TimeInterval, config: AgentConfig, mcpManager: MCPManager) async {
        let unit = formatWatchInterval(interval)

        Swift.print("\u{001B}[36m\u{001B}[1m\u{1F441} Watch mode\u{001B}[0m: checking every \(unit)")
        Swift.print("  \u{001B}[90m\u{1F4CB} \(prompt)\u{001B}[0m")
        Swift.print("  \u{001B}[90mPress Ctrl+C to stop\u{001B}[0m\n")

        let agent = AgentLoop(config: config, mcpManager: mcpManager)
        agent.approval.autoApprove = true
        var iteration = 0

        while true {
            iteration += 1
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            Swift.print("\u{001B}[33m\u{23F1} [\(timestamp)] Check #\(iteration)...\u{001B}[0m")

            do {
                let response = try await agent.processUserInput(prompt)
                if !response.isEmpty {
                    Swift.print(response)
                }
            } catch {
                Swift.print("\u{001B}[33m\u{26A0} Error: \(error.localizedDescription)\u{001B}[0m")
            }

            Swift.print("  \u{001B}[90m\u{1F4A4} Next check in \(unit)...\u{001B}[0m\n")
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    // MARK: - /profile command

    static func handleProfile(args: [String], config: inout AgentConfig) -> CommandResult {
        let sub = args.first ?? "list"

        switch sub {
        case "list":
            let profiles = ProfileManager.listProfiles()
            if profiles.isEmpty {
                printDim("  No profiles found. Run the app once to install defaults.")
                return .handled
            }
            printColored("\n  Profiles (~/.desktop-agent/profiles/):", color: .bold)
            for name in profiles {
                let active = (config.profileName == name) ? " \u{001B}[32m[active]\u{001B}[0m" : ""
                printColored("    \(name)\(active)", color: .cyan)
            }
            if config.profileName == nil {
                printDim("    (no profile active)")
            }
            print()
            printDim("  /profile use <name>  — switch profile")
            printDim("  /profile show        — show current profile content")
            printDim("  /profile edit <name> — open in $EDITOR")
            print()
            return .handled

        case "use":
            guard args.count >= 2 else {
                printColored("  Usage: /profile use <name>", color: .yellow)
                let available = ProfileManager.listProfiles().joined(separator: ", ")
                if !available.isEmpty { printDim("  Available: \(available)") }
                return .handled
            }
            let name = args[1]
            guard ProfileManager.exists(name: name) else {
                printColored("  Profile '\(name)' not found.", color: .red)
                let available = ProfileManager.listProfiles().joined(separator: ", ")
                if !available.isEmpty { printDim("  Available: \(available)") }
                return .handled
            }
            guard let profileContent = ProfileManager.load(name: name) else {
                printColored("  Error loading profile '\(name)'.", color: .red)
                return .handled
            }

            // Rebuild system prompt with the new profile
            // Strip any existing profile section from the current prompt
            var basePrompt = config.systemPrompt
            if let range = basePrompt.range(of: "\n\n## ACTIVE PROFILE (") {
                basePrompt = String(basePrompt[..<range.lowerBound])
            }
            let newPrompt = basePrompt + "\n\n## ACTIVE PROFILE (\(name)):\n" + profileContent

            config = AgentConfig(
                apiKey: config.apiKey,
                model: config.model,
                maxTokens: config.maxTokens,
                systemPrompt: newPrompt,
                verbose: config.verbose,
                maxScreenshotWidth: config.maxScreenshotWidth,
                baseURL: config.baseURL,
                apiFormat: config.apiFormat,
                providerId: config.providerId,
                profileName: name,
                fallbackModels: config.fallbackModels
            )
            printColored("  Switched to profile: \(name)", color: .green)
            return .reload

        case "show":
            let name = config.profileName ?? "default"
            guard let content = ProfileManager.load(name: name) else {
                printDim("  No active profile (or profile file missing).")
                return .handled
            }
            printColored("\n  Profile: \(name)", color: .bold)
            printDim("  Path: \(ProfileManager.path(for: name))")
            print()
            for line in content.components(separatedBy: "\n") {
                printDim("    \(line)")
            }
            print()
            return .handled

        case "edit":
            let name = args.count >= 2 ? args[1] : (config.profileName ?? "default")
            let path = ProfileManager.path(for: name)

            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.createDirectory(atPath: ProfileManager.profilesDir, withIntermediateDirectories: true)
                try? "## Profile: \(name)\n\nAdd your custom instructions here.\n".write(toFile: path, atomically: true, encoding: .utf8)
            }

            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vim"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, path]
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            do {
                try process.run()
                process.waitUntilExit()
                printColored("  Profile saved. Use /profile use \(name) to activate.", color: .green)
            } catch {
                printColored("  Error opening editor: \(error.localizedDescription)", color: .red)
            }
            return .handled

        default:
            printColored("  Usage: /profile [list|use <name>|show|edit <name>]", color: .yellow)
            return .handled
        }
    }

    // MARK: - /fallback command

    static func handleFallback(args: [String], config: inout AgentConfig) -> CommandResult {
        let sub = args.first?.lowercased() ?? "list"

        switch sub {
        case "list":
            let fallbacks = config.fallbackModels
            if fallbacks.isEmpty {
                printDim("  No fallback models configured.")
                printDim("  When the primary model fails, fallbacks are tried in order.")
            } else {
                printColored("\n  Fallback chain:", color: .bold)
                for (i, model) in fallbacks.enumerated() {
                    let providerName = AIProvider.resolve(modelString: model)?.provider.name ?? "?"
                    printColored("    \(i + 1). \(model) \u{001B}[90m(\(providerName))\u{001B}[0m", color: .cyan)
                }
                print()
            }
            printDim("  /fallback add <provider/model>    \u{2014} add a fallback")
            printDim("  /fallback remove <provider/model>  \u{2014} remove a fallback")
            printDim("  /fallback clear                    \u{2014} clear all fallbacks")
            print()
            return .handled

        case "add":
            guard args.count >= 2 else {
                printColored("  Usage: /fallback add <provider/model>", color: .yellow)
                printDim("  Example: /fallback add openai/gpt-4o")
                return .handled
            }
            let modelString = args[1]

            guard let resolved = AIProvider.resolve(modelString: modelString) else {
                printColored("  \u{2717} Unknown model: \(modelString)", color: .red)
                printHint("Use provider/model format, e.g. openai/gpt-4o, anthropic/claude-haiku-4-5-20251001")
                return .handled
            }

            let canonical = "\(resolved.provider.id)/\(resolved.model)"
            var fileConfig = AgentConfigFile.load()
            var fallbacks = fileConfig.fallbackModels ?? []
            if fallbacks.contains(canonical) {
                printDim("  Already in fallback chain: \(canonical)")
                return .handled
            }
            fallbacks.append(canonical)
            fileConfig.fallbackModels = fallbacks
            do {
                try fileConfig.save()
            } catch {
                printColored("  \u{2717} Error saving: \(error)", color: .red)
                return .handled
            }
            config = AgentConfig.load()
            printColored("  \u{2713} Added fallback: \(canonical) (\(resolved.provider.name))", color: .green)
            return .reload

        case "remove":
            guard args.count >= 2 else {
                printColored("  Usage: /fallback remove <provider/model>", color: .yellow)
                return .handled
            }
            let modelString = args[1]
            var fileConfig = AgentConfigFile.load()
            var fallbacks = fileConfig.fallbackModels ?? []
            let canonical = AIProvider.resolve(modelString: modelString).map { "\($0.provider.id)/\($0.model)" } ?? modelString
            if let idx = fallbacks.firstIndex(of: canonical) {
                fallbacks.remove(at: idx)
            } else if let idx = fallbacks.firstIndex(of: modelString) {
                fallbacks.remove(at: idx)
            } else {
                printColored("  \u{2717} Not found in fallback chain: \(modelString)", color: .red)
                let current = fallbacks.joined(separator: ", ")
                if !current.isEmpty { printDim("  Current: \(current)") }
                return .handled
            }
            fileConfig.fallbackModels = fallbacks.isEmpty ? nil : fallbacks
            do {
                try fileConfig.save()
            } catch {
                printColored("  \u{2717} Error saving: \(error)", color: .red)
                return .handled
            }
            config = AgentConfig.load()
            printColored("  \u{2713} Removed fallback: \(canonical)", color: .green)
            return .reload

        case "clear":
            var fileConfig = AgentConfigFile.load()
            fileConfig.fallbackModels = nil
            do {
                try fileConfig.save()
            } catch {
                printColored("  \u{2717} Error saving: \(error)", color: .red)
                return .handled
            }
            config = AgentConfig.load()
            printColored("  \u{2713} Cleared all fallback models", color: .green)
            return .reload

        default:
            printColored("  Subcommands: list, add, remove, clear", color: .yellow)
            return .handled
        }
    }

    // MARK: - /gateway command

    static func handleGateway(args: [String]) {
        let sub = args.first ?? "status"
        switch sub {
        case "status":
            let configFile = AgentConfigFile.load()
            let gw = configFile.gateways
            printColored("\n  Gateway Configuration:", color: .bold)
            let platforms: [(String, Bool, String?)] = [
                ("Telegram", gw?.telegram?.enabled ?? false,
                 gw?.telegram != nil ? "users: \(gw?.telegram?.allowedUsers?.count ?? 0)" : nil),
                ("WhatsApp", gw?.whatsapp?.enabled ?? false,
                 gw?.whatsapp != nil ? "jids: \(gw?.whatsapp?.allowedJIDs?.count ?? 0)" : nil),
                ("Slack", gw?.slack?.enabled ?? false,
                 gw?.slack != nil ? "users: \(gw?.slack?.allowedUsers?.count ?? 0)" : nil),
                ("Discord", gw?.discord?.enabled ?? false,
                 gw?.discord != nil ? "users: \(gw?.discord?.allowedUsers?.count ?? 0)" : nil),
                ("Watch", gw?.watch?.enabled ?? false,
                 gw?.watch != nil ? "port: \(gw?.watch?.port ?? 8375), devices: \(gw?.watch?.allowedDevices?.count ?? 0)" : nil),
            ]
            for (name, enabled, detail) in platforms {
                let icon = enabled ? "🟢" : "⚫"
                let extra = detail.map { " (\($0))" } ?? ""
                printColored("  \(icon) \(name): \(enabled ? "configured" : "not configured")\(extra)", color: enabled ? .green : .gray)
            }
            print()

            // Check if OpenClaw has gateways we could import
            let noneConfigured = (gw == nil) ||
                (gw?.telegram == nil && gw?.whatsapp == nil && gw?.slack == nil && gw?.discord == nil && gw?.watch == nil)
            if noneConfigured {
                let openclawPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
                if let data = FileManager.default.contents(atPath: openclawPath),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let channels = json["channels"] as? [String: Any], !channels.isEmpty {
                    let available = channels.keys.sorted().joined(separator: ", ")
                    printColored("  💡 Found OpenClaw config with: \(available)", color: .cyan)
                    printColored("  Run: /gateway import  to import them\n", color: .cyan)
                } else {
                    printDim("  To configure: ask the agent or use /config import-openclaw")
                }
            }
            printDim("  To start: osai gateway")
            print()

        case "import":
            importFromOpenClaw()

        default:
            printColored("  Usage: /gateway [status|import]", color: .yellow)
        }
    }

    // MARK: - Gateway Delivery (for scheduled tasks)

    static func deliverToGateway(target: String, message: String) async {
        // Enqueue before attempting delivery (for retry on failure)
        let pending = DeliveryQueue.enqueue(target: target, message: message)

        // Parse target: "discord:channelId" or "telegram:chatId"
        let parts = target.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            printColored("  ✗ Invalid delivery target: \(target)", color: .red)
            DeliveryQueue.fail(id: pending.id)
            return
        }
        let platform = String(parts[0])
        let chatId = String(parts[1])

        let fileConfig = AgentConfigFile.load()
        var deliveryFailed = false

        switch platform {
        case "discord":
            guard let discord = fileConfig.gateways?.discord else {
                printColored("  ✗ Discord not configured for delivery", color: .red)
                DeliveryQueue.fail(id: pending.id)
                return
            }
            // Short messages: plain content. Long messages (>500): embed with teal color.
            // Embed description max 4096 chars; split into multiple embeds if needed.
            if message.count <= 500 {
                let chunks = splitForDelivery(message, maxLength: 2000)
                for chunk in chunks {
                    do {
                        let url = URL(string: "https://discord.com/api/v10/channels/\(chatId)/messages")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.setValue("Bot \(discord.botToken)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try JSONSerialization.data(withJSONObject: ["content": chunk])
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                            printColored("  ✗ Discord delivery failed: HTTP \(http.statusCode)", color: .red)
                            deliveryFailed = true
                        }
                    } catch {
                        printColored("  ✗ Discord delivery error: \(error)", color: .red)
                        deliveryFailed = true
                    }
                }
            } else {
                // Split into embed-sized chunks (max 4096 per embed description)
                let embedChunks = splitForDelivery(message, maxLength: 4096)
                let iso8601 = ISO8601DateFormatter()
                let timestamp = iso8601.string(from: Date())
                for chunk in embedChunks {
                    do {
                        let embed: [String: Any] = [
                            "description": chunk,
                            "color": 0x00D4AA,
                            "footer": ["text": "osai"],
                            "timestamp": timestamp
                        ]
                        let payload: [String: Any] = ["embeds": [embed]]
                        let url = URL(string: "https://discord.com/api/v10/channels/\(chatId)/messages")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.setValue("Bot \(discord.botToken)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                            printColored("  ✗ Discord embed delivery failed: HTTP \(http.statusCode)", color: .red)
                            deliveryFailed = true
                        }
                    } catch {
                        printColored("  ✗ Discord delivery error: \(error)", color: .red)
                        deliveryFailed = true
                    }
                }
            }
            if !deliveryFailed {
                printColored("  📬 Delivered to Discord channel \(chatId)", color: .green)
            }

        case "telegram":
            guard let tg = fileConfig.gateways?.telegram else {
                printColored("  ✗ Telegram not configured for delivery", color: .red)
                DeliveryQueue.fail(id: pending.id)
                return
            }
            let chunks = splitForDelivery(message, maxLength: 4096)
            for chunk in chunks {
                do {
                    let url = URL(string: "https://api.telegram.org/bot\(tg.botToken)/sendMessage")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "chat_id": chatId, "text": chunk, "parse_mode": "Markdown"
                    ] as [String: Any])
                    let _ = try await URLSession.shared.data(for: request)
                } catch {
                    printColored("  ✗ Telegram delivery error: \(error)", color: .red)
                    deliveryFailed = true
                }
            }
            if !deliveryFailed {
                printColored("  📬 Delivered to Telegram chat \(chatId)", color: .green)
            }

        case "slack":
            guard let slack = fileConfig.gateways?.slack else {
                printColored("  ✗ Slack not configured for delivery", color: .red)
                DeliveryQueue.fail(id: pending.id)
                return
            }
            do {
                let url = URL(string: "https://slack.com/api/chat.postMessage")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(slack.botToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "channel": chatId, "text": message
                ])
                let _ = try await URLSession.shared.data(for: request)
            } catch {
                printColored("  ✗ Slack delivery error: \(error)", color: .red)
                deliveryFailed = true
            }
            if !deliveryFailed {
                printColored("  📬 Delivered to Slack channel \(chatId)", color: .green)
            }

        case "whatsapp":
            // Send via wacli
            let wacliPath = "/opt/homebrew/bin/wacli"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: wacliPath)
            process.arguments = ["send", "text", "--to", chatId, "--message", message, "--json"]
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                printColored("  📬 Delivered to WhatsApp \(chatId)", color: .green)
            } else {
                printColored("  ✗ WhatsApp delivery failed", color: .red)
                deliveryFailed = true
            }

        case "watch":
            // Deliver via HTTP POST to watch gateway's pending queue
            // The watch adapter accumulates responses that the watch polls for
            guard let watch = fileConfig.gateways?.watch else {
                printColored("  ✗ Watch not configured for delivery", color: .red)
                DeliveryQueue.fail(id: pending.id)
                return
            }
            let port = watch.port ?? 8375
            do {
                let url = URL(string: "http://localhost:\(port)/message")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "device_id": chatId, "text": message, "user_name": "osai-task"
                ])
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                    printColored("  ✗ Watch delivery failed: HTTP \(http.statusCode)", color: .red)
                    deliveryFailed = true
                }
            } catch {
                printColored("  ✗ Watch delivery error: \(error)", color: .red)
                deliveryFailed = true
            }
            if !deliveryFailed {
                printColored("  📬 Delivered to Watch device \(chatId)", color: .green)
            }

        default:
            printColored("  ✗ Unknown delivery platform: \(platform)", color: .red)
            deliveryFailed = true
        }

        // Update delivery queue based on result
        if deliveryFailed {
            DeliveryQueue.fail(id: pending.id)
        } else {
            DeliveryQueue.complete(id: pending.id)
        }
    }

    private static func splitForDelivery(_ text: String, maxLength: Int) -> [String] {
        if text.count <= maxLength { return [text] }
        var chunks: [String] = []
        var remaining = text
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(maxLength, remaining.count))
            let chunk = String(remaining[..<end])
            if let lastNewline = chunk.lastIndex(of: "\n"), remaining.count > maxLength {
                let splitAt = remaining.index(after: lastNewline)
                chunks.append(String(remaining[..<splitAt]))
                remaining = String(remaining[splitAt...])
            } else {
                chunks.append(chunk)
                remaining = String(remaining[end...])
            }
        }
        return chunks
    }

    static func deliverImageToDiscord(channelId: String, imageData: Data, filename: String, caption: String?) async {
        let fileConfig = AgentConfigFile.load()
        guard let discord = fileConfig.gateways?.discord else {
            printColored("  ✗ Discord not configured for image delivery", color: .red)
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let url = URL(string: "https://discord.com/api/v10/channels/\(channelId)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bot \(discord.botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add JSON payload with optional caption
        if let caption = caption {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"payload_json\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            let payloadJSON = try? JSONSerialization.data(withJSONObject: ["content": caption])
            body.append(payloadJSON ?? Data())
            body.append("\r\n".data(using: .utf8)!)
        }

        // Add file attachment
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files[0]\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                printColored("  ✗ Discord image delivery failed: HTTP \(http.statusCode)", color: .red)
            } else {
                printColored("  📬 Delivered image to Discord channel \(channelId)", color: .green)
            }
        } catch {
            printColored("  ✗ Discord image delivery error: \(error)", color: .red)
        }
    }

    static func importFromOpenClaw() {
        let openclawPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = FileManager.default.contents(atPath: openclawPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = json["channels"] as? [String: Any] else {
            printColored("  ✗ Could not read ~/.openclaw/openclaw.json or no channels found.", color: .red)
            return
        }

        var fileConfig = AgentConfigFile.load()
        if fileConfig.gateways == nil { fileConfig.gateways = GatewayConfig() }
        var imported: [String] = []

        if let discord = channels["discord"] as? [String: Any],
           let token = discord["token"] as? String {
            let enabled = discord["enabled"] as? Bool ?? true
            let allowFrom = discord["allowFrom"] as? [String]
            fileConfig.gateways?.discord = DiscordGatewayConfig(
                enabled: enabled, botToken: token, allowedGuilds: nil,
                allowedUsers: allowFrom, systemPrompt: nil
            )
            imported.append("Discord")
            let userCount = allowFrom?.count ?? 0
            printColored("  ✓ Discord: token imported, \(userCount) allowed user\(userCount == 1 ? "" : "s")", color: .green)
        }

        if let telegram = channels["telegram"] as? [String: Any],
           let token = telegram["botToken"] as? String ?? telegram["token"] as? String {
            let enabled = telegram["enabled"] as? Bool ?? true
            fileConfig.gateways?.telegram = TelegramGatewayConfig(
                enabled: enabled, botToken: token, allowedUsers: nil, systemPrompt: nil
            )
            imported.append("Telegram")
            printColored("  ✓ Telegram: token imported", color: .green)
        }

        if let slack = channels["slack"] as? [String: Any],
           let botToken = slack["botToken"] as? String,
           let appToken = slack["appToken"] as? String {
            let enabled = slack["enabled"] as? Bool ?? true
            fileConfig.gateways?.slack = SlackGatewayConfig(
                enabled: enabled, botToken: botToken, appToken: appToken,
                allowedChannels: nil, allowedUsers: nil, systemPrompt: nil
            )
            imported.append("Slack")
            printColored("  ✓ Slack: tokens imported", color: .green)
        }

        if imported.isEmpty {
            printDim("  No gateway channels found in OpenClaw config.")
            return
        }

        do {
            try fileConfig.save()
            print()
            printColored("  Imported \(imported.joined(separator: ", ")) from OpenClaw.", color: .green)
            printDim("  Run `osai gateway` to start the gateway server.")
            print()
        } catch {
            printColored("  ✗ Error saving: \(error)", color: .red)
        }
    }

    // MARK: - /config command

    static func handleConfig(args: [String], config: inout AgentConfig) -> CommandResult {
        let subcmd = args.first?.lowercased() ?? "list"

        switch subcmd {
        case "set-key":
            guard args.count >= 3 else {
                printColored("  Usage: /config set-key <provider> <api-key>", color: .yellow)
                printDim("  Providers: \(AIProvider.known.map { $0.id }.joined(separator: ", "))")
                print()
                printDim("  Examples:")
                printDim("    /config set-key anthropic sk-ant-...")
                printDim("    /config set-key openai sk-proj-...")
                printDim("    /config set-key google AIza...")
                return .handled
            }
            let provider = args[1].lowercased()
            let key = args[2]

            // Validate key format
            if let warning = validateAPIKey(key: key, provider: provider) {
                printColored("  ⚠ \(warning)", color: .yellow)
                printDim("  The key will be saved anyway, but double-check it's correct.")
                print()
            }

            guard AIProvider.find(id: provider) != nil else {
                printColored("  ✗ Unknown provider: '\(provider)'", color: .red)
                printDim("  Available: \(AIProvider.known.map { $0.id }.joined(separator: ", "))")
                return .handled
            }

            var fileConfig = AgentConfigFile.load()
            fileConfig.setAPIKey(provider: provider, key: key)
            do {
                try fileConfig.save()
                let providerName = AIProvider.find(id: provider)?.name ?? provider
                let masked = maskKey(key)
                printColored("  ✓ API key saved for \(providerName): \(masked)", color: .green)

                // If this is the current provider, reload config
                if provider == config.providerId {
                    config = AgentConfig.load()
                    return .reload
                }
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }
            return .handled

        case "remove-key":
            guard args.count >= 2 else {
                printColored("  Usage: /config remove-key <provider>", color: .yellow)
                return .handled
            }
            var fileConfig = AgentConfigFile.load()
            fileConfig.removeAPIKey(provider: args[1])
            do {
                try fileConfig.save()
                printColored("  ✓ Key removed for \(args[1])", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }
            return .handled

        case "import-openclaw":
            let openclawPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
            guard let data = FileManager.default.contents(atPath: openclawPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let env = json["env"] as? [String: Any],
                  let vars = env["vars"] as? [String: String] else {
                printColored("  ✗ Could not read ~/.openclaw/openclaw.json", color: .red)
                return .handled
            }

            var fileConfig = AgentConfigFile.load()
            var imported = 0

            let keyMap: [(envVar: String, provider: String)] = [
                ("ANTHROPIC_API_KEY", "anthropic"),
                ("OPENAI_API_KEY", "openai"),
                ("GOOGLE_API_KEY", "google"),
                ("GROQ_API_KEY", "groq"),
                ("MISTRAL_API_KEY", "mistral"),
                ("OPENROUTER_API_KEY", "openrouter"),
                ("DEEPSEEK_API_KEY", "deepseek"),
                ("XAI_API_KEY", "xai"),
            ]

            for (envVar, provider) in keyMap {
                if let key = vars[envVar], !key.isEmpty {
                    fileConfig.setAPIKey(provider: provider, key: key)
                    let name = AIProvider.find(id: provider)?.name ?? provider
                    printColored("  ✓ \(name): \(maskKey(key))", color: .green)
                    imported += 1
                }
            }

            // Also import gateway/channel configs
            var gatewayImported: [String] = []
            if let channels = json["channels"] as? [String: Any] {
                if fileConfig.gateways == nil { fileConfig.gateways = GatewayConfig() }

                if let discord = channels["discord"] as? [String: Any],
                   let token = discord["token"] as? String {
                    let enabled = discord["enabled"] as? Bool ?? true
                    let allowFrom = discord["allowFrom"] as? [String]
                    fileConfig.gateways?.discord = DiscordGatewayConfig(
                        enabled: enabled, botToken: token, allowedGuilds: nil,
                        allowedUsers: allowFrom, systemPrompt: nil
                    )
                    gatewayImported.append("Discord")
                    printColored("  ✓ Discord gateway: \(maskKey(token))", color: .green)
                }

                if let telegram = channels["telegram"] as? [String: Any],
                   let token = telegram["botToken"] as? String ?? telegram["token"] as? String {
                    let enabled = telegram["enabled"] as? Bool ?? true
                    fileConfig.gateways?.telegram = TelegramGatewayConfig(
                        enabled: enabled, botToken: token, allowedUsers: nil, systemPrompt: nil
                    )
                    gatewayImported.append("Telegram")
                    printColored("  ✓ Telegram gateway: \(maskKey(token))", color: .green)
                }
            }

            if imported > 0 || !gatewayImported.isEmpty {
                do {
                    try fileConfig.save()
                    var summary: [String] = []
                    if imported > 0 { summary.append("\(imported) API key\(imported == 1 ? "" : "s")") }
                    if !gatewayImported.isEmpty { summary.append("gateways: \(gatewayImported.joined(separator: ", "))") }
                    printColored("\n  Imported \(summary.joined(separator: " + ")) from OpenClaw.", color: .green)
                    if !gatewayImported.isEmpty {
                        printDim("  Run `osai gateway` to start gateway server.")
                    }
                    config = AgentConfig.load()
                    return .reload
                } catch {
                    printColored("  ✗ Error saving: \(error)", color: .red)
                }
            } else {
                printDim("  No API keys or gateways found in openclaw config.")
            }
            return .handled

        case "list", "show":
            let fileConfig = AgentConfigFile.load()
            printDim("  \(AgentConfigFile.configPath)")
            print()

            printColored("  API Keys", color: .bold)
            if let keys = fileConfig.apiKeys, !keys.isEmpty {
                for (provider, provConfig) in keys.sorted(by: { $0.key < $1.key }) {
                    let name = AIProvider.find(id: provider)?.name ?? provider
                    let masked = maskKey(provConfig.apiKey)
                    let active = provider == config.providerId ? " \u{001B}[32m← active\u{001B}[0m" : ""
                    print("    \u{001B}[36m\(name)\u{001B}[0m \u{001B}[90m(\(provider))\u{001B}[0m  \(masked)\(active)")
                }
            } else {
                printDim("    (none set)")
            }

            print()
            printColored("  Active Model", color: .bold)
            let provName = AIProvider.find(id: config.providerId)?.name ?? config.providerId
            print("    \u{001B}[36m\(provName)/\(config.model)\u{001B}[0m")

            return .handled

        case "set-url":
            guard args.count >= 3 else {
                printColored("  Usage: /config set-url <provider> <base-url>", color: .yellow)
                printDim("  Use for custom/self-hosted endpoints")
                return .handled
            }
            let provider = args[1].lowercased()
            let url = args[2]
            var fileConfig = AgentConfigFile.load()
            let existingKey = fileConfig.getAPIKey(provider: provider) ?? ""
            fileConfig.setAPIKey(provider: provider, key: existingKey, baseURL: url)
            do {
                try fileConfig.save()
                printColored("  ✓ Base URL set for \(provider): \(url)", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }
            return .handled

        default:
            printColored("  Subcommands: set-key, remove-key, set-url, import-openclaw, list", color: .yellow)
            return .handled
        }
    }

    // MARK: - /model command

    static func handleModel(args: [String], config: inout AgentConfig) -> CommandResult {
        let subcmd = args.first?.lowercased() ?? "show"

        switch subcmd {
        case "show", "current":
            let providerName = AIProvider.find(id: config.providerId)?.name ?? config.providerId
            print("  \u{001B}[36m\(providerName) / \(config.model)\u{001B}[0m")
            printDim("  Format: \(config.apiFormat)  URL: \(config.baseURL)")
            return .handled

        case "list":
            let items = InteractivePicker.buildModelItems(
                currentProviderId: config.providerId,
                currentModel: config.model
            )

            if let selected = InteractivePicker.pick(title: "Select a model:", items: items) {
                guard let resolved = AIProvider.resolve(modelString: selected) else {
                    printColored("  ✗ Unknown model: \(selected)", color: .red)
                    return .handled
                }

                let fileConfig = AgentConfigFile.load()
                let hasKey = fileConfig.getAPIKey(provider: resolved.provider.id) != nil
                if !hasKey {
                    printColored("  ⚠ No API key set for \(resolved.provider.name).", color: .yellow)
                    printHint("Set one: /config set-key \(resolved.provider.id) YOUR_KEY")
                }

                var updatedConfig = AgentConfigFile.load()
                updatedConfig.activeModel = selected
                do {
                    try updatedConfig.save()
                } catch {
                    printColored("  ✗ Error saving: \(error)", color: .red)
                    return .handled
                }

                config = AgentConfig.load()
                let providerName = AIProvider.find(id: config.providerId)?.name ?? config.providerId
                printColored("  ✓ Switched to \(providerName) / \(config.model)", color: .green)
                return .reload
            } else {
                printDim("  Cancelled.")
            }
            return .handled

        case "use", "switch", "set":
            guard args.count >= 2 else {
                printColored("  Usage: /model use <provider/model>", color: .yellow)
                printDim("  Example: /model use openai/gpt-4o")
                printDim("  Tip: use /model list for interactive selection")
                return .handled
            }
            let modelString = args[1]

            guard let resolved = AIProvider.resolve(modelString: modelString) else {
                printColored("  ✗ Unknown model: \(modelString)", color: .red)
                printHint("Use /model list to see available models")
                return .handled
            }

            let fileConfig = AgentConfigFile.load()
            let hasKey = fileConfig.getAPIKey(provider: resolved.provider.id) != nil
            if !hasKey {
                printColored("  ⚠ No API key set for \(resolved.provider.name).", color: .yellow)
                printHint("Set one: /config set-key \(resolved.provider.id) YOUR_KEY")
            }

            var updatedConfig = AgentConfigFile.load()
            updatedConfig.activeModel = "\(resolved.provider.id)/\(resolved.model)"
            do {
                try updatedConfig.save()
            } catch {
                printColored("  ✗ Error saving: \(error)", color: .red)
            }

            config = AgentConfig.load()
            let providerName = AIProvider.find(id: config.providerId)?.name ?? config.providerId
            printColored("  ✓ Switched to \(providerName) / \(config.model)", color: .green)
            return .reload

        default:
            printColored("  Subcommands: show, list, use", color: .yellow)
            return .handled
        }
    }

    // MARK: - /mcp command

    static func handleMCP(args: [String], mcpManager: MCPManager) {
        let subcmd = args.first?.lowercased() ?? "list"

        switch subcmd {
        case "list":
            let configured = MCPManager.listConfiguredServers()
            if configured.isEmpty {
                printDim("  No MCP servers configured.")
                printHint("Add one: /mcp add <name> <command> [args...]")
                printDim("  Example: /mcp add chrome npx @anthropic-ai/mcp-chrome-devtools")
            } else {
                for (name, config) in configured {
                    let running = mcpManager.connectedServers.contains(name)
                    let status = running
                        ? "\u{001B}[32m●\u{001B}[0m"
                        : "\u{001B}[90m○\u{001B}[0m"
                    print("  \(status) \u{001B}[36m\(name)\u{001B}[0m \u{001B}[90m\(config.command) \(config.args?.joined(separator: " ") ?? "")\u{001B}[0m")
                }
            }
            let tools = mcpManager.availableTools
            if !tools.isEmpty {
                print()
                printDim("  \(tools.count) tools available")
                for tool in tools {
                    printDim("    \(tool.qualifiedName)")
                }
            }

        case "add":
            guard args.count >= 3 else {
                printColored("  Usage: /mcp add <name> <command> [args...]", color: .yellow)
                printDim("  Example: /mcp add chrome npx @anthropic-ai/mcp-chrome-devtools")
                return
            }
            let name = args[1]
            let command = args[2]
            let extraArgs = args.count > 3 ? Array(args[3...]) : []

            do {
                let config = try MCPManager.installServer(name: name, packageName: command, args: extraArgs)
                printColored("  ✓ MCP server '\(name)' added", color: .green)
                do {
                    try mcpManager.startServer(name: name, config: config)
                } catch {
                    printColored("  ⚠ Saved but failed to start: \(error)", color: .yellow)
                }
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        case "remove":
            guard args.count >= 2 else {
                printColored("  Usage: /mcp remove <name>", color: .yellow)
                return
            }
            mcpManager.stopServer(name: args[1])
            do {
                try MCPManager.removeServer(name: args[1])
                printColored("  ✓ Removed '\(args[1])'", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        case "start":
            guard args.count >= 2 else {
                printColored("  Usage: /mcp start <name>", color: .yellow)
                return
            }
            let name = args[1]
            let configured = MCPManager.listConfiguredServers()
            guard let (_, config) = configured.first(where: { $0.name == name }) else {
                printColored("  ✗ Server '\(name)' not found", color: .red)
                return
            }
            do {
                try mcpManager.startServer(name: name, config: config)
            } catch {
                printColored("  ✗ Failed to start: \(error)", color: .red)
            }

        case "stop":
            guard args.count >= 2 else {
                printColored("  Usage: /mcp stop <name>", color: .yellow)
                return
            }
            mcpManager.stopServer(name: args[1])
            printColored("  ✓ Stopped '\(args[1])'", color: .green)

        default:
            printColored("  Subcommands: list, add, remove, start, stop", color: .yellow)
        }
    }

    // MARK: - /plugin command

    static func handlePlugin(args: [String], agent: AgentLoop, config: AgentConfig, mcpManager: MCPManager) async {
        let subcmd = args.first?.lowercased() ?? "list"

        switch subcmd {
        case "list":
            let plugins = PluginManager.listPlugins()
            if plugins.isEmpty {
                printDim("  No plugins found.")
            } else {
                for p in plugins {
                    print("  \u{001B}[36m\(p.name)\u{001B}[0m \u{001B}[90m— \(p.description)\u{001B}[0m")
                    if let model = p.model {
                        printDim("    model: \(model)")
                    }
                }
            }

        case "run":
            guard args.count >= 3 else {
                printColored("  Usage: /plugin run <name> <your instruction>", color: .yellow)
                let plugins = PluginManager.listPlugins()
                if !plugins.isEmpty {
                    printDim("  Available: \(plugins.map { $0.name }.joined(separator: ", "))")
                }
                return
            }
            let pluginName = args[1]
            let instruction = args.dropFirst(2).joined(separator: " ")

            guard let plugin = PluginManager.loadPlugin(name: pluginName) else {
                printColored("  ✗ Plugin '\(pluginName)' not found", color: .red)
                return
            }

            printColored("  Running: \(plugin.name) — \(plugin.description)", color: .magenta)
            print()

            do {
                _ = try await agent.processWithPlugin(plugin, input: instruction)
                print()
            } catch {
                printColored("  Error: \(error)", color: .red)
            }

        case "create":
            guard args.count >= 3 else {
                printColored("  Usage: /plugin create <name> <description>", color: .yellow)
                return
            }
            let name = args[1]
            let desc = args.dropFirst(2).joined(separator: " ")

            let plugin = AgentPlugin(
                name: name, description: desc, model: nil, tools: nil,
                systemPrompt: "You are a specialized agent for: \(desc)\n\nAdd your detailed instructions here.",
                filePath: ""
            )
            do {
                try PluginManager.savePlugin(plugin)
                printColored("  ✓ Plugin '\(name)' created", color: .green)
                printDim("  Edit: ~/.desktop-agent/plugins/\(name).md")
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        case "delete":
            guard args.count >= 2 else {
                printColored("  Usage: /plugin delete <name>", color: .yellow)
                return
            }
            do {
                try PluginManager.deletePlugin(name: args[1])
                printColored("  ✓ Deleted '\(args[1])'", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        default:
            printColored("  Subcommands: list, run, create, delete", color: .yellow)
        }
    }

    // MARK: - /memory command

    static func handleMemory(args: [String]) {
        let memory = MemoryManager()
        let subcmd = args.first?.lowercased() ?? "list"

        switch subcmd {
        case "list":
            let files = memory.listMemoryFiles()
            if files.isEmpty {
                printDim("  No memory files yet.")
                printHint("The agent creates them as needed, or: /memory write <topic> <content>")
            } else {
                for f in files {
                    print("  \u{001B}[36m\(f.name)\u{001B}[0m \u{001B}[90m(\(f.size) bytes)\u{001B}[0m")
                }
            }

        case "read":
            guard args.count >= 2 else {
                printColored("  Usage: /memory read <topic>", color: .yellow)
                return
            }
            if let content = memory.readMemoryFile(name: args[1]) {
                print(content)
            } else {
                printColored("  Not found: \(args[1])", color: .red)
            }

        case "write":
            guard args.count >= 3 else {
                printColored("  Usage: /memory write <topic> <content...>", color: .yellow)
                return
            }
            let topic = args[1]
            let content = args.dropFirst(2).joined(separator: " ")
            do {
                try memory.writeMemoryFile(name: topic, content: content)
                printColored("  ✓ Saved to \(topic).md", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        case "delete":
            guard args.count >= 2 else {
                printColored("  Usage: /memory delete <topic>", color: .yellow)
                return
            }
            do {
                try memory.deleteMemoryFile(name: args[1])
                printColored("  ✓ Deleted \(args[1])", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        default:
            printColored("  Subcommands: list, read, write, delete", color: .yellow)
        }
    }

    // MARK: - /program command

    static func handleProgram(args: [String]) {
        let subcmd = args.first?.lowercased() ?? "show"

        switch subcmd {
        case "show", "read":
            if let content = AgentProgram.load() {
                print(content)
            } else {
                printDim("  No program.md found.")
            }

        case "edit":
            let path = AgentProgram.programPath
            printDim("  Opening \(path) in default editor...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-t", path]
            try? process.run()
            process.waitUntilExit()
            printColored("  ✓ Changes will take effect on next interaction.", color: .green)

        case "reset":
            try? FileManager.default.removeItem(atPath: AgentProgram.programPath)
            AgentProgram.installDefault()
            printColored("  ✓ Program reset to defaults.", color: .green)

        case "log":
            if let log = AgentProgram.readImprovementLog() {
                print(log)
            } else {
                printDim("  No improvement history yet.")
            }

        case "prompt":
            if let custom = AgentProgram.loadCustomSystemPrompt() {
                print(custom)
            } else {
                printDim("  Using default system prompt (no custom override).")
                printHint("The agent can set one with edit_system_prompt tool.")
            }

        case "reset-prompt":
            try? FileManager.default.removeItem(atPath: AgentProgram.systemPromptPath)
            printColored("  ✓ System prompt reset to default.", color: .green)

        default:
            printColored("  Subcommands: show, edit, reset, log, prompt, reset-prompt", color: .yellow)
        }
    }

    // MARK: - /skill command

    static func handleSkill(args: [String]) {
        let subcmd = args.first?.lowercased() ?? "list"

        switch subcmd {
        case "list":
            let skills = SkillManager.listSkills()
            if skills.isEmpty {
                printDim("  No skills installed.")
                printHint("Skills are auto-detected by keywords in your messages.")
                printHint("Dir: ~/.desktop-agent/skills/")
            } else {
                for s in skills {
                    let triggers = s.triggers.prefix(5).joined(separator: ", ")
                    print("  \u{001B}[36m\(s.name)\u{001B}[0m \u{001B}[90m— triggers: [\(triggers)]\u{001B}[0m")
                    if !s.description.isEmpty {
                        printDim("    \(s.description)")
                    }
                }
            }

        case "show", "read":
            guard args.count >= 2 else {
                printColored("  Usage: /skill show <name>", color: .yellow)
                return
            }
            if let skill = SkillManager.loadSkill(name: args[1]) {
                print("  \u{001B}[1m\(skill.name)\u{001B}[0m")
                if let mcp = skill.mcp { printDim("  MCP: \(mcp)") }
                printDim("  Triggers: \(skill.triggers.joined(separator: ", "))")
                print()
                print(skill.instructions)
            } else {
                printColored("  Skill '\(args[1])' not found.", color: .red)
            }

        case "delete", "remove":
            guard args.count >= 2 else {
                printColored("  Usage: /skill delete <name>", color: .yellow)
                return
            }
            do {
                try SkillManager.deleteSkill(name: args[1])
                printColored("  ✓ Deleted skill '\(args[1])'", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        default:
            printColored("  Subcommands: list, show, delete", color: .yellow)
        }
    }

    // MARK: - /task command

    static func handleTask(args: [String]) {
        let subcmd = args.first?.lowercased() ?? "list"

        switch subcmd {
        case "list":
            let tasks = TaskScheduler.listTasks()
            if tasks.isEmpty {
                printDim("  No scheduled tasks.")
                printHint("Ask the agent to schedule something: \"remind me every day at 8am to check email\"")
            } else {
                for t in tasks {
                    let status = t.enabled ? "\u{001B}[32m●\u{001B}[0m" : "\u{001B}[90m○\u{001B}[0m"
                    print("  \(status) \u{001B}[36m\(t.id)\u{001B}[0m \u{001B}[90m— \(t.schedule.displayString)\u{001B}[0m")
                    printDim("    \(t.description)")
                    printDim("    cmd: \(t.command)")
                    if let last = t.lastRun {
                        let fmt = DateFormatter()
                        fmt.dateFormat = "yyyy-MM-dd HH:mm"
                        printDim("    last run: \(fmt.string(from: last)) (×\(t.runCount))")
                    }
                }
            }

        case "cancel", "delete", "remove":
            guard args.count >= 2 else {
                printColored("  Usage: /task cancel <id>", color: .yellow)
                return
            }
            do {
                try TaskScheduler.cancelTask(id: args[1])
                printColored("  ✓ Cancelled task '\(args[1])'", color: .green)
            } catch {
                printColored("  ✗ Error: \(error)", color: .red)
            }

        default:
            printColored("  Subcommands: list, cancel", color: .yellow)
        }
    }

    // MARK: - API Key Validation

    static func validateAPIKey(key: String, provider: String) -> String? {
        let patterns: [String: (prefix: String, hint: String)] = [
            "anthropic": ("sk-ant-", "Anthropic keys start with 'sk-ant-'"),
            "openai":    ("sk-",     "OpenAI keys start with 'sk-'"),
            "google":    ("AIza",    "Google keys start with 'AIza'"),
        ]

        // Check if key looks like it belongs to a different provider
        let providerGuesses: [(prefix: String, name: String)] = [
            ("sk-ant-", "anthropic"),
            ("sk-proj-", "openai"),
            ("sk-", "openai"),
            ("AIza", "google"),
            ("gsk_", "groq"),
            ("xai-", "xai"),
        ]

        for guess in providerGuesses {
            if key.hasPrefix(guess.prefix) && guess.name != provider {
                let correctName = AIProvider.find(id: guess.name)?.name ?? guess.name
                return "This looks like a \(correctName) key (prefix '\(guess.prefix)'). Did you mean: /config set-key \(guess.name) ..."
            }
        }

        // Check expected prefix for known providers
        if let expected = patterns[provider] {
            if !key.hasPrefix(expected.prefix) && key.count > 10 {
                return "\(expected.hint). This key doesn't match the expected format."
            }
        }

        // Basic length check
        if key.count < 10 {
            return "Key seems too short. Check that you copied it correctly."
        }

        return nil
    }

    static func maskKey(_ key: String) -> String {
        if key.count <= 12 { return "****" }
        return String(key.prefix(8)) + "..." + String(key.suffix(4))
    }

    // MARK: - Print Helpers

    static func printDim(_ text: String) {
        TerminalDisplay.shared.writeLine("\u{001B}[90m\(text)\u{001B}[0m")
    }

    static func printHint(_ text: String) {
        TerminalDisplay.shared.writeLine("\u{001B}[90m  \(text)\u{001B}[0m")
    }

    // MARK: - Usage Display

    /// Format the usage line based on the current display level.
    /// Returns nil when display is off.
    static func formatUsageLine(context: ContextManager) -> String? {
        switch usageDisplayLevel {
        case .off:
            return nil
        case .tokens:
            let r = "\u{001B}[0m"
            let d = "\u{001B}[90m"
            let m = "\u{001B}[35m"
            var line = "\(d)Usage: \(context.fmtTokens(context.lastInputTokens)) in / \(context.fmtTokens(context.lastOutputTokens)) out\(r)"
            if context.lastCompactionSaved > 0 {
                line += " \(m)compacted -\(context.fmtTokens(context.lastCompactionSaved))\(r)"
            }
            return line
        case .full:
            return context.consumeTurnSummary()
        }
    }

    // MARK: - /status Command

    static func printStatus(agent: AgentLoop, config: AgentConfig) {
        let r = "\u{001B}[0m"
        let d = "\u{001B}[90m"
        let b = "\u{001B}[1m"
        let c = "\u{001B}[36m"
        let g = "\u{001B}[32m"
        let y = "\u{001B}[33m"

        let ctx = agent.context
        let providerName = AIProvider.find(id: config.providerId)?.name ?? config.providerId
        let profileLabel = config.profileName ?? "none"
        let dur = formatStatusDuration(ctx.sessionDuration)
        let pricing = ctx.pricing
        let ctxWindow = ctx.contextWindow
        let guard_ = agent.spendingGuard
        let fileConfig = AgentConfigFile.load()
        let limits = fileConfig.spendingLimits

        print()
        print("  \(b)Session Overview\(r)")
        print("  \(ctx.contextBar)")
        print()
        print("  \(d)Provider:\(r)  \(c)\(providerName)\(r)")
        print("  \(d)Model:\(r)    \(c)\(config.model)\(r)")
        print("  \(d)Pricing:\(r)  \(d)\(fmtStatusCost(pricing.inputPer1M))/1M in \u{00B7} \(fmtStatusCost(pricing.outputPer1M))/1M out \u{00B7} \(ctx.fmtTokens(ctxWindow)) ctx\(r)")
        print("  \(d)Profile:\(r)  \(profileLabel)")
        print()

        let totalTok = ctx.totalInputTokens + ctx.totalOutputTokens
        let avgCost = ctx.avgCostPerTurn
        print("  \(b)Session\(r)")
        print("  \(d)Turns:\(r)    \(ctx.turnCount)")
        print("  \(d)Duration:\(r) \(dur)")
        print("  \(d)Tokens:\(r)   \(d)\u{2191}\(ctx.fmtTokens(ctx.totalInputTokens)) \u{2193}\(ctx.fmtTokens(ctx.totalOutputTokens)) (\(ctx.fmtTokens(totalTok)) total)\(r)")
        print("  \(d)Cost:\(r)     \(g)\(fmtStatusCost(ctx.sessionCost))\(r)\(d) (\(fmtStatusCost(avgCost))/turn avg)\(r)")
        if ctx.compactionCount > 0 {
            print("  \(d)Compacted:\(r) \(y)\(ctx.compactionCount)x \u{00B7} saved ~\(ctx.fmtTokens(ctx.tokensSavedByCompaction)) tokens\(r)")
        }
        print()

        let dailyLimit = limits?.dailyUsd
        let monthlyLimit = limits?.monthlyUsd
        if dailyLimit != nil || monthlyLimit != nil {
            let statsText = guard_.stats
            let dailySpend = extractSpend(from: statsText, label: "Today:")
            let monthSpend = extractSpend(from: statsText, label: "Month:")
            print("  \(b)Limits\(r)")
            if let daily = dailyLimit {
                let pct = daily > 0 ? dailySpend / daily * 100 : 0
                print("  \(d)Daily:\(r)    \(fmtStatusCost(dailySpend)) / \(fmtStatusCost(daily)) (\(String(format: "%.1f", pct))%)")
            }
            if let monthly = monthlyLimit {
                let pct = monthly > 0 ? monthSpend / monthly * 100 : 0
                print("  \(d)Monthly:\(r)  \(fmtStatusCost(monthSpend)) / \(fmtStatusCost(monthly)) (\(String(format: "%.1f", pct))%)")
            }
            print()
        } else {
            print("  \(d)Limits:   none configured\(r)")
            print("  \(d)          Add \"spending_limits\" to ~/.desktop-agent/config.json\(r)")
            print()
        }

        print("  \(d)Usage display: \(usageDisplayLevel.label) (/usage to cycle)\(r)")
        print()
    }

    private static func extractSpend(from stats: String, label: String) -> Double {
        for line in stats.components(separatedBy: "\n") {
            if line.contains(label), let dollarIdx = line.firstIndex(of: "$") {
                let afterDollar = line[line.index(after: dollarIdx)...]
                let numStr = afterDollar.prefix(while: { $0.isNumber || $0 == "." })
                if let val = Double(numStr) { return val }
            }
        }
        return 0
    }

    private static func fmtStatusCost(_ usd: Double) -> String {
        if usd < 0.01 && usd > 0 { return String(format: "$%.4f", usd) }
        if usd < 1.00 { return String(format: "$%.3f", usd) }
        return String(format: "$%.2f", usd)
    }

    private static func formatStatusDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    // MARK: - Doctor (self-diagnosis)

    static func runDoctor() {
        let g = "\u{001B}[32m"
        let r = "\u{001B}[31m"
        let y = "\u{001B}[33m"
        let d = "\u{001B}[90m"
        let b = "\u{001B}[1m"
        let n = "\u{001B}[0m"

        Swift.print("\n  \(b)🩺 osai doctor\(n)\n")

        var issues = 0
        var warnings = 0

        func ok(_ msg: String) { Swift.print("  \(g)✓\(n) \(msg)") }
        func warn(_ msg: String) { Swift.print("  \(y)⚠\(n) \(msg)"); warnings += 1 }
        func fail(_ msg: String) { Swift.print("  \(r)✗\(n) \(msg)"); issues += 1 }

        // 1. Config file
        let configExists = FileManager.default.fileExists(atPath: AgentConfigFile.configPath)
        if configExists {
            ok("Config file exists at ~/.desktop-agent/config.json")
        } else {
            fail("No config file found. Run \(b)osai\(n) to start onboarding.")
        }

        // 2. API key
        let fileConfig = AgentConfigFile.load()
        let config = AgentConfig.load()
        if config.apiKey.isEmpty {
            fail("No API key configured for \(b)\(config.providerId)\(n). Set with: /config set-key \(config.providerId) YOUR_KEY")
        } else {
            let masked = String(config.apiKey.prefix(8)) + "..." + String(config.apiKey.suffix(4))
            ok("API key set for \(b)\(config.providerId)\(n) \(d)(\(masked))\(n)")
        }

        // 3. Model
        let pricing = ContextManager.lookupPricing(model: config.model)
        let isDefault = (pricing.inputPer1M == ContextManager.defaultPricing.inputPer1M
                      && pricing.outputPer1M == ContextManager.defaultPricing.outputPer1M)
        if isDefault {
            warn("Model \(b)\(config.model)\(n) not in pricing database — using default pricing ($\(String(format: "%.2f", pricing.inputPer1M))/$\(String(format: "%.2f", pricing.outputPer1M)))")
        } else {
            ok("Model \(b)\(config.model)\(n) — $\(String(format: "%.2f", pricing.inputPer1M))/$\(String(format: "%.2f", pricing.outputPer1M)) per 1M tokens")
        }

        // 4. Accessibility permissions
        let trusted = AXIsProcessTrusted()
        if trusted {
            ok("Accessibility permissions granted")
        } else {
            warn("Accessibility not granted — GUI automation will fail. Enable in System Settings > Privacy > Accessibility")
        }

        // 5. Screen recording
        let hasScreenRecording = CGPreflightScreenCaptureAccess()
        if hasScreenRecording {
            ok("Screen recording permissions granted")
        } else {
            warn("Screen recording not granted — screenshots will fail. Enable in System Settings > Privacy > Screen Recording")
        }

        // 6. Config directory structure
        let fm = FileManager.default
        let configDir = AgentConfigFile.configDir
        let dirs = ["plugins", "skills", "memory", "profiles"]
        var missingDirs: [String] = []
        for dir in dirs {
            if !fm.fileExists(atPath: configDir + "/" + dir) { missingDirs.append(dir) }
        }
        if missingDirs.isEmpty {
            ok("All directories present \(d)(plugins, skills, memory, profiles)\(n)")
        } else {
            warn("Missing directories: \(missingDirs.joined(separator: ", ")). They'll be created on first use.")
        }

        // 7. Spending limits
        if let limits = fileConfig.spendingLimits {
            let daily = limits.dailyUsd.map { "$\(String(format: "%.0f", $0))/day" } ?? "none"
            let monthly = limits.monthlyUsd.map { "$\(String(format: "%.0f", $0))/month" } ?? "none"
            ok("Spending limits: \(daily), \(monthly)")
        } else {
            warn("No spending limits configured. Set in config.json or during onboarding.")
        }

        // 8. wacli (WhatsApp)
        let wacliPaths = ["/opt/homebrew/bin/wacli", "/usr/local/bin/wacli"]
        if let wacliFound = wacliPaths.first(where: { fm.fileExists(atPath: $0) }) {
            ok("wacli found at \(wacliFound)")
        } else {
            // Only warn if gateway is configured for WhatsApp
            if fileConfig.gateways?.whatsapp != nil {
                warn("wacli not found — WhatsApp gateway won't work. Install from https://github.com/nicebyte/wacli")
            } else {
                Swift.print("  \(d)·\(n) wacli not installed \(d)(WhatsApp gateway not configured)\(n)")
            }
        }

        // 9. MCP servers
        let mcpCount = fileConfig.mcpServers?.count ?? 0
        if mcpCount > 0 {
            ok("\(mcpCount) MCP server(s) configured")
            for (name, server) in fileConfig.mcpServers ?? [:] {
                let cmd = server.command
                let exists = fm.fileExists(atPath: cmd) || (cmd.contains("/") == false)
                if exists {
                    Swift.print("    \(d)· \(name): \(cmd)\(n)")
                } else {
                    warn("  MCP server '\(name)': command not found at \(cmd)")
                }
            }
        } else {
            Swift.print("  \(d)·\(n) No MCP servers configured \(d)(optional)\(n)")
        }

        // 10. Disk space for spending log
        let spendingLogPath = configDir + "/spending.json"
        if fm.fileExists(atPath: spendingLogPath) {
            if let attrs = try? fm.attributesOfItem(atPath: spendingLogPath),
               let size = attrs[.size] as? UInt64 {
                let sizeKB = size / 1024
                if sizeKB > 1024 {
                    warn("Spending log is \(sizeKB)KB — consider pruning old entries")
                } else {
                    ok("Spending log: \(sizeKB)KB")
                }
            }
        }

        // Summary
        Swift.print()
        if issues == 0 && warnings == 0 {
            Swift.print("  \(g)\(b)All checks passed!\(n) osai is ready to use.\n")
        } else if issues == 0 {
            Swift.print("  \(y)\(b)\(warnings) warning(s)\(n) — osai will work but some features may be limited.\n")
        } else {
            Swift.print("  \(r)\(b)\(issues) issue(s)\(n), \(y)\(warnings) warning(s)\(n) — fix issues above to use osai.\n")
        }
    }

    // MARK: - Onboarding (first run)

    static func runOnboarding() {
        let r = "\u{001B}[0m"
        let b = "\u{001B}[1m"
        let c = "\u{001B}[36m"
        let g = "\u{001B}[32m"
        let y = "\u{001B}[33m"
        let d = "\u{001B}[90m"
        let m = "\u{001B}[35m"

        // Clear screen and show welcome
        Swift.print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)

        Swift.print("""

        \(b)\(c)  ┌─────────────────────────────────────────────┐
          │                                             │
          │   \(m)🤖  Welcome to osai\(c)                       │
          │   \(d)Your AI-powered macOS assistant\(c)            │
          │                                             │
          └─────────────────────────────────────────────┘\(r)

        """)

        Swift.print("  \(b)osai\(r) can control your Mac, automate tasks, send emails,")
        Swift.print("  browse the web, write code, and much more.\n")
        Swift.print("  \(d)Let's get you set up in 30 seconds.\(r)\n")

        // Step 1: Choose provider + model
        Swift.print("  \(b)\(y)Step 1/3:\(r) \(b)Choose your AI provider\(r)\n")

        let providerItems: [(String, String, String)] = [
            ("Google Gemini",  "google",    "Free tier available, great for starting out"),
            ("Anthropic",      "anthropic", "Claude — best tool use and reasoning"),
            ("OpenAI",         "openai",    "GPT-4.1, o3 — broad model selection"),
            ("DeepSeek",       "deepseek",  "Cheapest — $0.28/M tokens input"),
            ("Groq",           "groq",      "Fastest inference — free tier available"),
            ("xAI (Grok)",     "xai",       "Grok-4 — 2M context window"),
            ("Mistral",        "mistral",   "European — Mistral Large 3, Codestral"),
            ("OpenRouter",     "openrouter","Route to 200+ models from one key"),
        ]

        for (i, (name, _, desc)) in providerItems.enumerated() {
            let num = "\(c)\(i + 1)\(r)"
            Swift.print("  \(num)  \(b)\(name)\(r)  \(d)\(desc)\(r)")
        }
        Swift.print()
        Swift.print("  \(d)Enter number (1-\(providerItems.count)):\(r) ", terminator: "")
        fflush(stdout)

        var providerChoice = 0
        if let line = readLine(), let num = Int(line), num >= 1 && num <= providerItems.count {
            providerChoice = num - 1
        }

        let (providerName, providerId, _) = providerItems[providerChoice]
        let provider = AIProvider.find(id: providerId) ?? AIProvider.known[0]

        // Step 2: Choose model
        Swift.print("\n  \(b)\(y)Step 2/3:\(r) \(b)Choose a model\(r) \(d)(from \(providerName))\(r)\n")

        for (i, model) in provider.models.enumerated() {
            let pricing = ContextManager.lookupPricing(model: model)
            let costStr = String(format: "$%.2f/$%.2f per 1M", pricing.inputPer1M, pricing.outputPer1M)
            let ctxStr = pricing.contextWindow >= 1_000_000
                ? "\(pricing.contextWindow / 1_000_000)M ctx"
                : "\(pricing.contextWindow / 1_000)K ctx"
            Swift.print("  \(c)\(i + 1)\(r)  \(b)\(model)\(r)  \(d)\(costStr) · \(ctxStr)\(r)")
        }
        Swift.print()
        Swift.print("  \(d)Enter number (1-\(provider.models.count)) [1]:\(r) ", terminator: "")
        fflush(stdout)

        var modelChoice = 0
        if let line = readLine(), let num = Int(line), num >= 1 && num <= provider.models.count {
            modelChoice = num - 1
        }

        let selectedModel = provider.models[modelChoice]
        let modelString = "\(providerId)/\(selectedModel)"

        // Step 3: API Key
        Swift.print("\n  \(b)\(y)Step 3/3:\(r) \(b)API Key\(r)\n")

        // Check env vars first
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

        var apiKey = ""
        if let envName = envKeys[providerId],
           let envVal = ProcessInfo.processInfo.environment[envName], !envVal.isEmpty {
            apiKey = envVal
            Swift.print("  \(g)✓\(r) Found \(envName) in environment\n")
        } else {
            let keyHints: [String: String] = [
                "google":    "Get one at: https://aistudio.google.com/apikey",
                "anthropic":  "Get one at: https://console.anthropic.com/settings/keys",
                "openai":    "Get one at: https://platform.openai.com/api-keys",
                "deepseek":  "Get one at: https://platform.deepseek.com/api_keys",
                "groq":      "Get one at: https://console.groq.com/keys",
                "xai":       "Get one at: https://console.x.ai",
                "mistral":   "Get one at: https://console.mistral.ai/api-keys",
                "openrouter":"Get one at: https://openrouter.ai/settings/keys",
            ]
            if let hint = keyHints[providerId] {
                Swift.print("  \(d)\(hint)\(r)")
            }
            Swift.print("  \(d)Paste your API key (hidden):\(r) ", terminator: "")
            fflush(stdout)

            // Read key with echo disabled
            var originalTermios = termios()
            tcgetattr(STDIN_FILENO, &originalTermios)
            var noecho = originalTermios
            noecho.c_lflag &= ~UInt(ECHO)
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &noecho)
            apiKey = readLine() ?? ""
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
            Swift.print() // newline after hidden input

            if apiKey.isEmpty {
                Swift.print("  \(y)⚠ No key entered. You can set it later with: /config set-key \(providerId) YOUR_KEY\(r)\n")
            } else {
                Swift.print("  \(g)✓\(r) Key saved securely\n")
            }
        }

        // Save config
        var fileConfig = AgentConfigFile()
        fileConfig.activeModel = modelString
        if !apiKey.isEmpty {
            fileConfig.setAPIKey(provider: providerId, key: apiKey)
        }
        // Set sensible spending limits
        fileConfig.spendingLimits = SpendingLimits(dailyUsd: 5.0, monthlyUsd: 50.0, perSessionUsd: nil, warnAtPercent: 80)
        do {
            try fileConfig.save()
        } catch {
            Swift.print("  \(y)⚠ Could not save config: \(error)\(r)")
        }

        // Summary
        let pricing = ContextManager.lookupPricing(model: selectedModel)
        Swift.print("""
          \(b)━━━ Setup Complete ━━━\(r)

          \(d)Provider:\(r) \(b)\(providerName)\(r)
          \(d)Model:\(r)    \(b)\(selectedModel)\(r)
          \(d)Pricing:\(r)  \(g)$\(String(format: "%.2f", pricing.inputPer1M))\(r)/1M in · \(g)$\(String(format: "%.2f", pricing.outputPer1M))\(r)/1M out
          \(d)Limits:\(r)   $5/day · $50/month
          \(d)Config:\(r)   ~/.desktop-agent/config.json

          \(d)Quick tips:\(r)
          \(c)/model\(r)   — switch models    \(c)/context\(r) — see costs
          \(c)/help\(r)    — all commands      \(c)/yolo\(r)    — skip confirmations
          \(c)Ctrl+C\(r)   — cancel action     \(c)osai update\(r) — self-update

        """)
    }

    // MARK: - Self Update

    static func selfUpdate() {
        Swift.print("🔄 Actualizando osai...")

        // Determine source directory — check multiple locations
        let candidates = [
            ProcessInfo.processInfo.environment["OSAI_SRC"],
            "\(NSHomeDirectory())/Sites/osai",
            "\(NSHomeDirectory())/.osai-src"
        ].compactMap { $0 }

        let srcDir = candidates.first(where: { dir in
            FileManager.default.fileExists(atPath: "\(dir)/Package.swift")
        }) ?? candidates.last!

        if !FileManager.default.fileExists(atPath: "\(srcDir)/Package.swift") {
            Swift.print("📦 Clonando repo...")
            let clone = Process()
            clone.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            clone.arguments = ["clone", "--quiet", "https://github.com/elgatoflaco/osai.git", srcDir]
            try? clone.run()
            clone.waitUntilExit()
            guard clone.terminationStatus == 0 else {
                Swift.print("❌ Error clonando el repositorio")
                return
            }
        } else {
            Swift.print("📦 Actualizando desde \(srcDir)...")
            let pull = Process()
            pull.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            pull.arguments = ["-C", srcDir, "pull", "--quiet"]
            try? pull.run()
            pull.waitUntilExit()
            guard pull.terminationStatus == 0 else {
                Swift.print("❌ Error actualizando el repositorio")
                return
            }
        }

        // Get new version info
        let log = Process()
        let logPipe = Pipe()
        log.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        log.arguments = ["-C", srcDir, "log", "--oneline", "-1"]
        log.standardOutput = logPipe
        try? log.run()
        log.waitUntilExit()
        let commitMsg = String(data: logPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Swift.print("  📝 \(commitMsg)")

        // Build
        Swift.print("🔨 Compilando (puede tardar 1-2 min)...")
        let build = Process()
        let buildPipe = Pipe()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        build.arguments = ["swift", "build", "-c", "release"]
        build.currentDirectoryURL = URL(fileURLWithPath: srcDir)
        build.standardOutput = buildPipe
        build.standardError = buildPipe
        try? build.run()
        build.waitUntilExit()

        guard build.terminationStatus == 0 else {
            let output = String(data: buildPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Swift.print("❌ Build falló:")
            Swift.print(output.suffix(500))
            return
        }

        // Find binary
        let binaryPath = srcDir + "/.build/release/DesktopAgent"
        // Also check platform-specific path
        let platformBinary = srcDir + "/.build/arm64-apple-macosx/release/DesktopAgent"
        let actualBinary = FileManager.default.fileExists(atPath: binaryPath) ? binaryPath : platformBinary

        guard FileManager.default.fileExists(atPath: actualBinary) else {
            Swift.print("❌ Binario no encontrado")
            return
        }

        // Install — try without sudo first, then with sudo
        let installPath = "/usr/local/bin/osai"
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = [actualBinary, installPath]
        try? cp.run()
        cp.waitUntilExit()

        if cp.terminationStatus != 0 {
            // Need sudo
            Swift.print("🔑 Necesita permisos de administrador...")
            let sudo = Process()
            sudo.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            sudo.arguments = ["cp", actualBinary, installPath]
            try? sudo.run()
            sudo.waitUntilExit()
            guard sudo.terminationStatus == 0 else {
                Swift.print("❌ Error instalando")
                return
            }
        }

        // Codesign
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", installPath]
        try? sign.run()
        sign.waitUntilExit()

        Swift.print("✅ osai actualizado!")
    }

    static func buildHash() -> String {
        // Try to read git hash from embedded resource or use compile date
        let srcDir = "\(NSHomeDirectory())/.osai-src"
        let rev = Process()
        let pipe = Pipe()
        rev.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        rev.arguments = ["-C", srcDir, "rev-parse", "--short", "HEAD"]
        rev.standardOutput = pipe
        rev.standardError = FileHandle.nullDevice
        try? rev.run()
        rev.waitUntilExit()
        let hash = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        return hash
    }

    // MARK: - Help

    static func printHelp() {
        let b = ANSIColor.bold.rawValue
        let r = ANSIColor.reset.rawValue
        let d = "\u{001B}[90m"
        let c = "\u{001B}[36m"

        print("""

        \(b)USAGE\(r)
          \(c)osai\(r)                            Interactive mode (full UI)
          \(c)osai\(r) "do something"              Single command (no banner, just runs)
          \(c)echo\(r) "task" \(c)| osai\(r)               Pipe input
          \(c)osai watch\(r) "prompt" [--interval 5m]  Periodic monitoring mode
          \(c)osai --profile\(r) coding "task"      Use a specific profile
          \(c)osai gateway\(r)                    Start gateway (Telegram, WhatsApp, Slack, Discord, Watch)

        \(b)BASICS\(r)
          \(c)/help\(r)                          Show this help
          \(c)/clear\(r)                         Clear conversation history
          \(c)/watch\(r) <prompt> [--interval 5m]  Start periodic monitoring
          \(c)/quit\(r)                          Exit \(d)(also: /exit, /q, Ctrl+D)\(r)

        \(b)SESSIONS\(r) \(d)(save & resume conversations)\(r)
          \(c)/save\(r)                          Save current session with auto-name
          \(c)/sessions\(r)                      List saved sessions
          \(c)/session load\(r) <number-or-id>  Resume a saved session
          \(c)/session resume\(r)               Resume auto-saved session
          \(c)/session delete\(r) <number-or-id>  Delete a session
          \(c)/new\(r)                           Start fresh (clear history)
          \(d)Sessions auto-save to ~/.desktop-agent/sessions/cli/\(r)

        \(b)WHILE AGENT IS WORKING\(r) \(d)(aside)\(r)
          Just type and press Enter while the agent runs.
          Your message is injected as 💬 and the agent adapts.
          \(d)Use it to: correct, redirect, ask progress, add context.\(r)

        \(b)CONFIG & API KEYS\(r)
          \(c)/config list\(r)                   Show saved keys and settings
          \(c)/config set-key\(r) <prov> <key>   Save API key for a provider
          \(c)/config remove-key\(r) <provider>  Remove a saved API key
          \(c)/config set-url\(r) <prov> <url>   Custom endpoint (self-hosted)
          \(c)/config import-openclaw\(r)        Import keys from ~/.openclaw

        \(b)MODEL\(r)
          \(c)/model show\(r)                    Show current model
          \(c)/model list\(r)                    Interactive model selector
          \(c)/model use\(r) <provider/model>    Switch model directly

        \(b)FALLBACK MODELS\(r) \(d)(automatic failover)\(r)
          \(c)/fallback\(r)                      List current fallback chain
          \(c)/fallback add\(r) <provider/model> Add a fallback model
          \(c)/fallback remove\(r) <prov/model>  Remove a fallback
          \(c)/fallback clear\(r)                Clear all fallbacks
          \(d)When the primary model fails (rate limit, server error, auth),\(r)
          \(d)fallback models are tried in order automatically.\(r)

        \(b)MCP SERVERS\(r) \(d)(capability expansion)\(r)
          \(c)/mcp list\(r)                      Show configured servers & tools
          \(c)/mcp add\(r) <name> <cmd> [args]   Add and start a server
          \(c)/mcp remove\(r) <name>             Remove a server
          \(c)/mcp start\(r)|\(c)stop\(r) <name>         Control a server
          \(d)The agent can also auto-install MCPs when it needs new capabilities.\(r)

        \(b)PLUGINS\(r)
          \(c)/plugin list\(r)                   List available plugins
          \(c)/plugin run\(r) <name> <task>      Run a specialized plugin
          \(c)/plugin create\(r) <name> <desc>   Create a new plugin

        \(b)MEMORY\(r)
          \(c)/memory list\(r)                   List memory files
          \(c)/memory read\(r)|\(c)write\(r)|\(c)delete\(r)    Manage memory

        \(b)CONTEXT & SAFETY\(r)
          \(c)/context\(r)                       Token usage, context window, session stats
          \(c)/status\(r)                        Full system overview (provider, cost, limits)
          \(c)/usage\(r)                         Cycle usage display: off → tokens → full
          \(c)/compact\(r)                       Info about conversation compaction
          \(c)/yolo\(r)                          Toggle auto-approve all actions
          \(d)Context auto-compacts at 75% usage. Prompt shows ● with %.\(r)

        \(b)PROFILES\(r) \(d)(system prompt presets)\(r)
          \(c)/profile list\(r)                 List available profiles
          \(c)/profile use\(r) <name>           Switch to a profile (reloads agent)
          \(c)/profile show\(r)                 Show current profile content
          \(c)/profile edit\(r) <name>          Open profile in $EDITOR
          \(d)Profiles append extra instructions to the system prompt.\(r)
          \(d)Store as markdown: ~/.desktop-agent/profiles/<name>.md\(r)
          \(d)CLI flag: osai --profile coding "refactor this"\(r)

        \(b)SKILLS\(r) \(d)(contextual knowledge injection)\(r)
          \(c)/skill list\(r)                   List installed skills
          \(c)/skill show\(r) <name>            Show skill details & triggers
          \(c)/skill delete\(r) <name>          Remove a skill
          \(d)Skills auto-activate when your message matches trigger keywords.\(r)
          \(d)Add your own: ~/.desktop-agent/skills/<name>.md\(r)

        \(b)TASKS\(r) \(d)(scheduled automation via launchd)\(r)
          \(c)/task list\(r)                    List scheduled tasks
          \(c)/task cancel\(r) <id>             Cancel a scheduled task
          \(d)Ask the agent: "every day at 8am send me a briefing"\(r)
          \(d)Tasks run osai in headless mode via macOS LaunchAgents.\(r)

        \(b)SELF-IMPROVEMENT\(r)
          \(c)/program show\(r)                  Show agent's program.md
          \(c)/program edit\(r)                  Open program.md in editor
          \(c)/program log\(r)                   Show improvement history
          \(c)/program prompt\(r)                Show custom system prompt
          \(c)/program reset\(r)                 Reset program to defaults
          \(c)/improve\(r) [focus]                Ask the agent to improve itself

        \(b)WATCH\(r) \(d)(periodic monitoring)\(r)
          \(c)osai watch\(r) "prompt" [--interval 5m]
          \(c)/watch\(r) prompt [--interval 5m]
          \(d)Runs the prompt periodically (default every 5 minutes).\(r)
          \(d)Interval formats: 30s, 5m, 1h. Also: --every 30s\(r)
          \(d)Auto-approves all actions. Press Ctrl+C to stop.\(r)

        \(b)GATEWAY\(r) \(d)(multi-platform messaging bridge)\(r)
          \(c)osai gateway\(r)                  Start gateway server
          \(d)Bridges Telegram, WhatsApp, Slack, Discord, Apple Watch to osai.\(r)
          \(d)Configure in ~/.desktop-agent/config.json under "gateways".\(r)
          \(d)Each platform gets its own agent session per chat.\(r)
          \(d)Messages are serialized per chat (no race conditions).\(r)
          \(d)Auto typing indicator while processing. Session persistence.\(r)
          \(d)Watch: Bonjour auto-discovery on local network (port 8375).\(r)

        \(b)CLAUDE CODE DELEGATION\(r) \(d)(programming proxy)\(r)
          \(d)The agent delegates all programming tasks to Claude Code CLI.\(r)
          \(d)Requires: claude CLI installed (~/.local/bin/claude)\(r)
          \(d)Real-time streaming of Claude Code output to gateway.\(r)
          \(d)10-minute timeout with automatic process cleanup.\(r)
          \(d)Source code protection: osai cannot modify its own sources directly.\(r)

        \(b)INTELLIGENCE\(r) \(d)(adaptive systems)\(r)
          \(d)Tool Orchestrator: predicts next tools, caches results, batching hints.\(r)
          \(d)Error Recovery: auto-retry with backoff, fallback chains.\(r)
          \(d)UI Intelligence: caches app layouts, learns workflows.\(r)
          \(d)Context Detector: adapts output for terminal/gateway/pipe.\(r)
          \(d)Intent Analyzer: routes to optimal tools based on input.\(r)

        \(b)SYSTEM\(r)
          \(c)/apps\(r) \(c)/windows\(r) \(c)/screen\(r) \(c)/perms\(r) \(c)/verbose\(r)

        \(d)Tab to autocomplete · ↑/↓ history · Ctrl+A/E/K/U/W readline keys\(r)

        """)
    }

    // MARK: - Banner

    static func printBanner() {
        // Half-block pixel art ghost (Space Invaders style)
        // Each row pair becomes one line using ▀▄█
        // 0=empty  1=body(cyan)  2=eye(white)  3=pupil(dark blue)
        let sprite: [[Int]] = [
            [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],  // 0
            [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],  // 1
            [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],  // 2
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],  // 3
            [0,1,1,2,2,1,1,1,1,1,2,2,1,1,1,0],  // 4
            [0,1,2,2,3,3,1,1,1,2,2,3,3,1,1,0],  // 5
            [0,1,2,2,3,3,1,1,1,2,2,3,3,1,1,0],  // 6
            [0,1,1,2,2,1,1,1,1,1,2,2,1,1,1,0],  // 7
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],  // 8
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],  // 9
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],  // 10
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],  // 11
            [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],  // 12
            [0,1,0,0,0,0,1,0,0,0,1,0,0,0,1,0],  // 13
        ]

        let fieldW = 44
        let fieldH = 7
        let ghostX = 14

        // Random star field
        let stars: [Character] = ["✦","✧","⋆","·","∘","∙"]
        var sf = Array(repeating: Array(repeating: Character(" "), count: fieldW), count: 14)
        for r in 0..<14 { for c in 0..<fieldW { if Int.random(in: 0..<25) == 0 { sf[r][c] = stars.randomElement()! } } }
        // Clear star positions under ghost
        for r in 0..<14 { for c in 0..<16 { let gc = ghostX + c; if gc < fieldW && sprite[r][c] != 0 { sf[r][gc] = " " } } }

        let C  = "\u{001B}[1;36m"   // bright cyan
        let W  = "\u{001B}[97m"     // bright white
        let P  = "\u{001B}[1;34m"   // bright blue (pupil)
        let D  = "\u{001B}[90m"     // dim
        let M  = "\u{001B}[35m"     // magenta
        let Y  = "\u{001B}[33m"     // yellow
        let R  = "\u{001B}[0m"      // reset
        let BC = "\u{001B}[46m"     // bg cyan
        let BW = "\u{001B}[107m"    // bg bright white
        let BP = "\u{001B}[44m"     // bg blue

        func fg(_ px: Int) -> String { [C, C, W, P][min(px, 3)] }
        func bg(_ px: Int) -> String { ["", BC, BW, BP][min(px, 3)] }

        let sColors = [D, D, D, M, Y, "\u{001B}[36m"]

        print()
        for row in 0..<fieldH {
            let t = row * 2, b = row * 2 + 1
            var line = "    "
            for col in 0..<fieldW {
                let sc = col - ghostX
                let tp = (sc >= 0 && sc < 16 && t < sprite.count) ? sprite[t][sc] : 0
                let bp = (sc >= 0 && sc < 16 && b < sprite.count) ? sprite[b][sc] : 0

                switch (tp > 0, bp > 0) {
                case (true, true):
                    if tp == bp { line += "\(fg(tp))█\(R)" }
                    else { line += "\(fg(tp))\(bg(bp))▀\(R)" }
                case (true, false):  line += "\(fg(tp))▀\(R)"
                case (false, true):  line += "\(fg(bp))▄\(R)"
                case (false, false):
                    let ch = sf[t][col]
                    if ch != " " { line += "\(sColors.randomElement()!)\(ch)\(R)" }
                    else { line += " " }
                }
            }
            print(line)
        }
        print()
        print("    \(C)  Desktop Agent\(R) \(D)v3.0\(R)")
        print("    \(D)  AI-powered macOS desktop control\(R)")
        print()
    }

    static func printUsage() {
        print("""
        osai — AI-Powered macOS Desktop Agent

        USAGE:
          osai                                  Interactive mode (full UI)
          osai "open Safari"                    Single command (headless)
          osai --model openai/gpt-5 "task"      Use a specific model
          osai --profile coding "refactor X"    Use a profile
          echo "list my files" | osai           Pipe input

        COMMANDS:
          osai update                           Update to latest version
          osai version                          Show current version
          osai doctor                           Diagnose configuration issues
          osai run <file.md>                    Execute a script/macro file
          osai watch "prompt" [--interval 5m]   Periodic monitoring
          osai gateway                          Start messaging gateway

        OPTIONS:
          --model <provider/model>   Model override (e.g. anthropic/claude-sonnet-4.6)
          --profile <name>           Profile preset (stored in ~/.desktop-agent/profiles/)
          --deliver <target>         Deliver result to a gateway target
          --verbose, -v              Verbose output (token counts, iterations)
          --version, -V              Show version
          --help, -h                 Show this help

        INTERACTIVE COMMANDS:  Type /help once inside for full list

        DIRECTORIES:
          Config:   ~/.desktop-agent/config.json
          Plugins:  ~/.desktop-agent/plugins/
          Skills:   ~/.desktop-agent/skills/
          Tasks:    ~/.desktop-agent/tasks/
          Memory:   ~/.desktop-agent/memory/
          Sessions: ~/.desktop-agent/sessions/
          Profiles: ~/.desktop-agent/profiles/

        GATEWAY PLATFORMS:
          WhatsApp    wacli CLI polling           (wacli auth required)
          Discord     WebSocket Gateway v10      (bot_token required)
          Telegram    Bot API long polling       (bot_token required)
          Slack       Socket Mode WebSocket      (bot_token + app_token required)
          Watch       HTTP + Bonjour             (Apple Watch companion app)

        PROVIDERS (8 built-in):
          anthropic, openai, google, groq, mistral, openrouter, deepseek, xai

        FIRST RUN:
          Just run 'osai' — the onboarding wizard will guide you through setup.
          Or manually: /config set-key <provider> <key>

        EXAMPLES:
          osai "take a screenshot and describe what you see"
          osai "open Finder and organize my Desktop"
          osai "create an SVG logo for my startup"
          osai "every day at 9am check my email and summarize"
          osai doctor                  # Check your setup
          osai gateway                 # Start messaging bridge
          osai run ~/scripts/daily.md  # Run automation script
        """)
    }
}
