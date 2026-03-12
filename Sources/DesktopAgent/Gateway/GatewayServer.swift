import Foundation

// MARK: - Gateway Error

enum GatewayError: Error, CustomStringConvertible {
    case authFailed(String)
    case networkError(String)
    case apiError(String)
    case notConfigured(String)

    var description: String {
        switch self {
        case .authFailed(let msg): return "Auth failed: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let msg): return "API error: \(msg)"
        case .notConfigured(let msg): return "Not configured: \(msg)"
        }
    }
}

// MARK: - Gateway Server

final class GatewayServer {
    private let config: AgentConfig
    private let mcpManager: MCPManager
    private let gatewayConfig: GatewayConfig
    private var adapters: [GatewayAdapter] = []
    private var sessions: [String: AgentLoop] = [:]  // chatId → agent session
    private let sessionsLock = NSLock()

    init(config: AgentConfig, mcpManager: MCPManager, gatewayConfig: GatewayConfig) {
        self.config = config
        self.mcpManager = mcpManager
        self.gatewayConfig = gatewayConfig
    }

    // MARK: - Start / Stop

    func start() async {
        printColored("\n  🌐 Starting Gateway Server...\n", color: .bold)

        // Setup adapters — fire-and-forget handlers (responses streamed via sendMessage)
        if let tg = gatewayConfig.telegram, tg.enabled {
            let adapter = TelegramAdapter(config: tg)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg, adapter: adapter)
            }
            adapters.append(adapter)
        }

        if let wa = gatewayConfig.whatsapp, wa.enabled {
            let adapter = WhatsAppAdapter(config: wa)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg, adapter: adapter)
            }
            adapters.append(adapter)
        }

        if let slack = gatewayConfig.slack, slack.enabled {
            let adapter = SlackAdapter(config: slack)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg, adapter: adapter)
            }
            adapters.append(adapter)
        }

        if let discord = gatewayConfig.discord, discord.enabled {
            let adapter = DiscordAdapter(config: discord)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg, adapter: adapter)
            }
            adapters.append(adapter)
        }

        // Security: warn about missing whitelists
        checkSecurityWhitelists()

        if adapters.isEmpty {
            printColored("  ⚠ No gateways configured.", color: .yellow)
            printColored("  Add gateway config to ~/.desktop-agent/config.json under \"gateways\"", color: .gray)
            printColored("  Example:", color: .gray)
            printColored("""
              {
                "gateways": {
                  "telegram": {
                    "enabled": true,
                    "bot_token": "123456:ABC-DEF..."
                  },
                  "whatsapp": {
                    "enabled": true
                  }
                }
              }
            """, color: .gray)
            return
        }

        // Start all adapters concurrently
        await withTaskGroup(of: Void.self) { group in
            for adapter in adapters {
                group.addTask {
                    do {
                        try await adapter.start()
                    } catch {
                        printColored("  ✗ \(adapter.platform): \(error)", color: .red)
                    }
                }
            }
        }

        let active = adapters.filter { $0.isRunning }.map { $0.platform }
        if !active.isEmpty {
            print()
            printColored("  🟢 Gateway active: \(active.joined(separator: ", "))", color: .green)
            printColored("  Listening for messages... (Ctrl+C to stop)\n", color: .gray)
        }

        // Keep running until interrupted
        await waitForever()
    }

    func stop() {
        for adapter in adapters {
            adapter.stop()
        }
        adapters.removeAll()

        sessionsLock.lock()
        sessions.removeAll()
        sessionsLock.unlock()
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: GatewayMessage, adapter: GatewayAdapter) async {
        let sessionKey = "\(message.platform):\(message.chatId)"

        // Get or create session (one AgentLoop per chat for conversation continuity)
        let agent: AgentLoop
        sessionsLock.lock()
        if let existing = sessions[sessionKey] {
            agent = existing
            sessionsLock.unlock()
        } else {
            let newAgent = AgentLoop(config: config, mcpManager: mcpManager)
            newAgent.approval.autoApprove = true  // Gateway mode: no terminal prompts
            newAgent.gatewayContext = GatewayDeliveryContext(
                platform: message.platform,
                chatId: message.chatId,
                userId: message.userId
            )
            // Restore previous session history if available
            let history = SessionStore.load(sessionKey: sessionKey)
            if !history.isEmpty {
                newAgent.restoreHistory(history)
            }
            sessions[sessionKey] = newAgent
            agent = newAgent
            sessionsLock.unlock()
        }

        // Wire streaming callback — send each text block to the chat as it arrives
        var didStream = false
        agent.onStreamText = { [weak adapter] text in
            didStream = true
            await adapter?.sendMessage(chatId: message.chatId, text: text)
        }

        // Process message (runs in the adapter's fire-and-forget task)
        do {
            let contextPrefix = "[Gateway: \(message.platform.uppercased()), user: \(message.userName)] "
            var gatewayHint = ""
            if agent.context.turnCount == 0 {
                gatewayHint = """
                [System: You are responding via \(message.platform) messaging to user \(message.userName).
                - Keep replies concise and natural for chat. Reply in the same language the user writes in.
                - You have full osai capabilities: shell commands, screenshots, file access, web scraping, MCP tools.
                - TASK SCHEDULING WORKS: When you schedule_task, results are automatically delivered back to this \(message.platform) chat. The delivery mechanism uses --deliver flag with the Discord/Telegram API. Tasks run via macOS launchd and ARE reliable.
                - For "once" tasks, use schedule_type "once" with "minutes" (minutes from now) — this is the most reliable for short delays.
                - Do NOT tell the user that scheduling has limitations or doesn't work. It works.
                - Do NOT suggest running things "live" instead of scheduling — scheduling is a feature the user wants.
                - You can manage scheduled tasks: use list_tasks to show active tasks, cancel_task to remove one, run_task to trigger one immediately.
                - When creating tasks with schedule_task, the delivery to this chat is automatic — you don't need to mention Discord/Telegram in the command.]\n
                """
            }
            let response = try await agent.processUserInput(gatewayHint + contextPrefix + message.text)
            // Persist session history after each message
            SessionStore.save(sessionKey: sessionKey, messages: agent.currentHistory)

            // If nothing was streamed (e.g. very short response), send the final response
            if !didStream && !response.isEmpty {
                await adapter.sendMessage(chatId: message.chatId, text: response)
            } else if !didStream {
                await adapter.sendMessage(chatId: message.chatId, text: "Done.")
            }
        } catch {
            printColored("  ✗ Error processing message: \(error)", color: .red)
            SessionStore.save(sessionKey: sessionKey, messages: agent.currentHistory)
            await adapter.sendMessage(chatId: message.chatId, text: "Sorry, I encountered an error: \(error.localizedDescription)")
        }

        // Clear streaming callback
        agent.onStreamText = nil
    }

    // MARK: - Security

    private func checkSecurityWhitelists() {
        var warnings: [String] = []

        if let tg = gatewayConfig.telegram, tg.enabled {
            if tg.allowedUsers == nil || tg.allowedUsers?.isEmpty == true {
                warnings.append("Telegram: no allowed_users — ANYONE can talk to your bot")
            }
        }
        if let wa = gatewayConfig.whatsapp, wa.enabled {
            if wa.allowedJIDs == nil || wa.allowedJIDs?.isEmpty == true {
                warnings.append("WhatsApp: no allowed_jids — ANYONE can trigger responses")
            }
        }
        if let slack = gatewayConfig.slack, slack.enabled {
            if (slack.allowedUsers == nil || slack.allowedUsers?.isEmpty == true) &&
               (slack.allowedChannels == nil || slack.allowedChannels?.isEmpty == true) {
                warnings.append("Slack: no allowed_users or allowed_channels — open to all workspace members")
            }
        }
        if let discord = gatewayConfig.discord, discord.enabled {
            if (discord.allowedUsers == nil || discord.allowedUsers?.isEmpty == true) &&
               (discord.allowedGuilds == nil || discord.allowedGuilds?.isEmpty == true) {
                warnings.append("Discord: no allowed_users or allowed_guilds — ANYONE can talk to your bot")
            }
        }

        if !warnings.isEmpty {
            print()
            printColored("  ⚠  SECURITY WARNING — Prompt Injection Risk", color: .red)
            printColored("  ─────────────────────────────────────────────", color: .red)
            printColored("  Without a user whitelist, anyone can send messages to your", color: .yellow)
            printColored("  agent. Malicious users can use prompt injection to make", color: .yellow)
            printColored("  it execute commands, read files, or access your system.", color: .yellow)
            print()
            for w in warnings {
                printColored("  • \(w)", color: .yellow)
            }
            print()
            printColored("  Fix: add allowed_users to your gateway config in", color: .gray)
            printColored("  ~/.desktop-agent/config.json or ask the agent to configure it.", color: .gray)
            print()

            // Ask for confirmation
            printColored("  Continue anyway? (y/N) ", color: .red)
            fflush(stdout)
            if let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" {
                printColored("  Proceeding with open access...\n", color: .yellow)
            } else {
                printColored("  Aborted. Configure whitelists first.\n", color: .gray)
                exit(1)
            }
        }
    }

    // MARK: - Wait

    private func waitForever() async {
        // Setup signal handlers
        signal(SIGINT) { _ in
            print("\n")
            printColored("  Gateway shutting down...", color: .gray)
            exit(0)
        }
        signal(SIGTERM) { _ in
            exit(0)
        }

        // Keep alive by sleeping in a loop
        while true {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
        }
    }
}
