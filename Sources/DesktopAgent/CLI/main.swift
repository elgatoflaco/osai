import Foundation
import AppKit

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

        let config = AgentConfig.load()

        // Install built-in plugins & skills
        PluginManager.installBuiltins()
        SkillManager.installBuiltins()

        // Start MCP servers from config
        let mcpManager = MCPManager()
        let fileConfig = AgentConfigFile.load()
        mcpManager.startFromConfig(fileConfig)

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
        // echo "do something" | osai
        var commandArgs: [String] = []
        var skipNext = false
        for (i, arg) in args.enumerated() {
            if i == 0 { continue }
            if skipNext { skipNext = false; continue }
            if arg == "--model" { skipNext = true; continue }
            if arg == "--verbose" || arg == "-v" { continue }
            if arg == "gateway" { continue }
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
            do {
                _ = try await agent.processUserInput(command)
            } catch {
                printColored("Error: \(error)", color: .red)
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
        printDim("  \(providerName) / \(config.model)")

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

    static func runInteractive(config: AgentConfig, mcpManager: MCPManager) async {
        var currentConfig = config
        var agent = AgentLoop(config: currentConfig, mcpManager: mcpManager)

        while true {
            let prompt = buildPrompt(config: currentConfig, context: agent.context)

            guard let inputResult = lineEditor.readInput(prompt: prompt) else {
                // EOF (Ctrl+D)
                print()
                printColored("  Goodbye!", color: .gray)
                return
            }
            let input = inputResult.text
            if input.isEmpty && !inputResult.hasImages { continue }

            // Show paste summary if large paste was collapsed
            if inputResult.pastedLines > 0 {
                printDim("  📋 Pasted \(inputResult.pastedLines) lines (\(input.count) chars)")
            }

            // Show image attachment info
            for img in inputResult.images {
                let filename = (img.path as NSString).lastPathComponent
                let size = (try? FileManager.default.attributesOfItem(atPath: img.path)[.size] as? Int) ?? 0
                let sizeStr = size > 1_000_000 ? "\(size / 1_000_000)MB" : "\(size / 1_000)KB"
                printColored("  📎 \(filename) (\(sizeStr), \(img.mediaType))", color: .magenta)
            }

            // --- Slash Commands ---
            if input.hasPrefix("/") && !inputResult.hasImages {
                let result = await handleSlashCommand(input, agent: agent, config: &currentConfig, mcpManager: mcpManager)
                if result == .quit { return }
                if result == .handled { continue }
                if result == .reload {
                    agent = AgentLoop(config: currentConfig, mcpManager: mcpManager)
                    continue
                }
                // .passthrough — unknown slash command
                if result == .passthrough {
                    let suggestion = suggestCommand(input)
                    if let s = suggestion {
                        printColored("  Unknown command. Did you mean \u{001B}[1m\(s)\u{001B}[0m\u{001B}[33m?\u{001B}[0m", color: .yellow)
                    } else {
                        printColored("  Unknown command. Type /help for available commands.", color: .yellow)
                    }
                    continue
                }
            }

            // Check API key before sending
            if currentConfig.apiKey.isEmpty {
                printColored("  No API key set.", color: .red)
                printHint("Use: /config set-key \(currentConfig.providerId) YOUR_KEY")
                continue
            }

            // Process with agent
            do {
                print()
                if inputResult.hasImages {
                    _ = try await agent.processUserInputWithImages(input, images: inputResult.images)
                } else {
                    _ = try await agent.processUserInput(input)
                }
                // Show token usage + cost after response
                if agent.context.turnCount > 0 {
                    print("  \(agent.context.turnSummary)")
                }
                print()
            } catch let error as AgentError {
                printColored("\n  Error: \(error.description)\n", color: .red)
            } catch {
                printColored("\n  Error: \(error.localizedDescription)\n", color: .red)
            }
        }
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
                       "/mcp", "/plugin", "/memory", "/skill", "/task",
                       "/apps", "/windows", "/screen", "/perms",
                       "/verbose", "/yolo", "/context", "/compact"]

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

        case "/context", "/ctx":
            print()
            print(agent.context.fullStatus)
            printDim("  Model: \(config.model)")
            printDim("  Messages: \(agent.historyCount)")
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

        default:
            return .passthrough
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

            if imported > 0 {
                do {
                    try fileConfig.save()
                    printColored("\n  Imported \(imported) API key\(imported == 1 ? "" : "s") from OpenClaw.", color: .green)
                    config = AgentConfig.load()
                    return .reload
                } catch {
                    printColored("  ✗ Error saving: \(error)", color: .red)
                }
            } else {
                printDim("  No API keys found in openclaw config.")
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
        print("\u{001B}[90m\(text)\u{001B}[0m")
        fflush(stdout)
    }

    static func printHint(_ text: String) {
        print("\u{001B}[90m  \(text)\u{001B}[0m")
        fflush(stdout)
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
          \(c)osai gateway\(r)                    Start gateway (Telegram, WhatsApp, Slack, Discord)

        \(b)BASICS\(r)
          \(c)/help\(r)                          Show this help
          \(c)/clear\(r)                         Clear conversation history
          \(c)/quit\(r)                          Exit \(d)(also: /exit, /q, Ctrl+D)\(r)

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
          \(c)/compact\(r)                       Info about conversation compaction
          \(c)/yolo\(r)                          Toggle auto-approve all actions
          \(d)Context auto-compacts at 75% usage. Prompt shows ● with %.\(r)

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

        \(b)GATEWAY\(r) \(d)(multi-platform messaging bridge)\(r)
          \(c)osai gateway\(r)                  Start gateway server
          \(d)Bridges Telegram, WhatsApp, Slack, Discord to osai.\(r)
          \(d)Configure in ~/.desktop-agent/config.json under "gateways".\(r)
          \(d)Each platform gets its own agent session per chat.\(r)

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
          osai                           Interactive mode (full UI)
          osai "open Safari"             Single command (headless, just runs)
          osai --model openai/gpt-4o "translate this"
          echo "list my files" | osai    Pipe input
          osai gateway                   Start multi-platform gateway

        OPTIONS:
          --model <provider/model>   Model to use (default: anthropic/claude-sonnet-4-20250514)
          --verbose, -v              Verbose output (show token counts, iterations)
          --help, -h                 Show this help

        INTERACTIVE COMMANDS:  /help (once inside)
        CONFIG:   ~/.desktop-agent/config.json
        PLUGINS:  ~/.desktop-agent/plugins/
        SKILLS:   ~/.desktop-agent/skills/
        TASKS:    ~/.desktop-agent/tasks/
        MEMORY:   ~/.desktop-agent/memory/

        FIRST RUN:
          osai
          /config set-key anthropic sk-ant-...
          /config import-openclaw

        EXAMPLES:
          osai "take a screenshot and describe what you see"
          osai "open Finder and organize my Desktop"
          osai "create an SVG logo for my startup"
        """)
    }
}
