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

// MARK: - Per-Session Message Queue
// Serializes messages per chat to prevent concurrent processUserInput on the same AgentLoop.
// Each session gets its own actor so messages from different chats run concurrently,
// but messages within the same chat are strictly serialized.

private actor SessionQueue {
    private var processing = false
    private var pending: [() async -> Void] = []

    func enqueue(_ work: @escaping () async -> Void) {
        pending.append(work)
        if !processing {
            processing = true
            Task { await drain() }
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let next = pending.removeFirst()
            await next()
        }
        processing = false
    }
}

// MARK: - Gateway Server

final class GatewayServer {
    private let config: AgentConfig
    private let mcpManager: MCPManager
    private let gatewayConfig: GatewayConfig
    private var adapters: [GatewayAdapter] = []
    private var sessions: [String: SessionEntry] = [:]  // chatId → session entry with last-active timestamp
    private var sessionQueues: [String: SessionQueue] = [:]  // chatId → message serializer
    private let sessionsLock = NSLock()

    // Session idle timeout: evict sessions unused for this duration to prevent unbounded memory growth
    private static let sessionIdleTimeout: TimeInterval = 4 * 60 * 60  // 4 hours
    private static let evictionInterval: TimeInterval = 10 * 60         // check every 10 minutes

    /// Wraps an AgentLoop with a last-active timestamp for idle eviction
    private struct SessionEntry {
        let agent: AgentLoop
        var lastActive: Date

        init(agent: AgentLoop) {
            self.agent = agent
            self.lastActive = Date()
        }

        mutating func touch() {
            lastActive = Date()
        }
    }

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

        if let watch = gatewayConfig.watch, watch.enabled {
            let adapter = WatchGatewayAdapter(config: watch)
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

        // Start background session eviction to prevent unbounded memory growth
        startSessionEviction()

        // Keep running until interrupted
        await waitForever()
    }

    /// Periodically evicts idle sessions to prevent unbounded memory growth
    private func startSessionEviction() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(Self.evictionInterval * 1_000_000_000))
                let now = Date()
                sessionsLock.lock()
                let before = sessions.count
                let evictedKeys = sessions.filter { _, entry in
                    now.timeIntervalSince(entry.lastActive) >= Self.sessionIdleTimeout
                }.map { $0.key }
                for key in evictedKeys {
                    sessions.removeValue(forKey: key)
                    sessionQueues.removeValue(forKey: key)
                }
                let evicted = evictedKeys.count
                sessionsLock.unlock()
                if evicted > 0 {
                    printColored("  🧹 Evicted \(evicted) idle session(s) (\(sessions.count) active)", color: .gray)
                }
            }
        }
    }

    func stop() {
        for adapter in adapters {
            adapter.stop()
        }
        adapters.removeAll()

        sessionsLock.lock()
        sessions.removeAll()
        sessionQueues.removeAll()
        sessionsLock.unlock()
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: GatewayMessage, adapter: GatewayAdapter) async {
        let sessionKey = "\(message.platform):\(message.chatId)"

        // Get or create the per-session message queue to serialize messages
        sessionsLock.lock()
        let queue = sessionQueues[sessionKey] ?? SessionQueue()
        sessionQueues[sessionKey] = queue
        sessionsLock.unlock()

        // Enqueue the message — only one message per chat processes at a time
        await queue.enqueue { [weak self] in
            guard let self = self else { return }
            await self.processMessage(message, adapter: adapter, sessionKey: sessionKey)
        }
    }

    private func processMessage(_ message: GatewayMessage, adapter: GatewayAdapter, sessionKey: String) async {
        // Get or create session (one AgentLoop per chat for conversation continuity)
        let agent: AgentLoop
        sessionsLock.lock()
        if var existing = sessions[sessionKey] {
            existing.touch()
            sessions[sessionKey] = existing
            agent = existing.agent
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
            sessions[sessionKey] = SessionEntry(agent: newAgent)
            agent = newAgent
            sessionsLock.unlock()
        }

        // Start periodic typing indicator (Discord resets after 5s, Telegram after 5s)
        let typingTask = Task {
            while !Task.isCancelled {
                await adapter.sendTypingIndicator(chatId: message.chatId)
                try? await Task.sleep(nanoseconds: 8_000_000_000) // every 8s
            }
        }

        // Wire streaming callback — send each text block to the chat as it arrives
        var didStream = false
        agent.onStreamText = { [weak adapter] text in
            didStream = true
            await adapter?.sendMessage(chatId: message.chatId, text: text)
        }

        // Process message
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
                - When creating tasks with schedule_task, the delivery to this chat is automatic — you don't need to mention Discord/Telegram in the command.
                - IMPORTANT: Your text responses are automatically sent to the user via the gateway. NEVER use run_shell with wacli/telegram/discord to send messages — the gateway handles delivery. Just respond with text.
                - NEVER use run_shell to run wacli commands — wacli has a lock that blocks concurrent access.]\n
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

        // Stop typing indicator and clear streaming callback
        typingTask.cancel()
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
        if let watch = gatewayConfig.watch, watch.enabled {
            if watch.allowedDevices == nil || watch.allowedDevices?.isEmpty == true {
                warnings.append("Watch: no allowed_devices — ANY device on local network can send messages")
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
