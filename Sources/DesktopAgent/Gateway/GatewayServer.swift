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

        // Setup adapters
        if let tg = gatewayConfig.telegram, tg.enabled {
            let adapter = TelegramAdapter(config: tg)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg) ?? "Error: gateway not available"
            }
            adapters.append(adapter)
        }

        if let wa = gatewayConfig.whatsapp, wa.enabled {
            let adapter = WhatsAppAdapter(config: wa)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg) ?? "Error: gateway not available"
            }
            adapters.append(adapter)
        }

        if let slack = gatewayConfig.slack, slack.enabled {
            let adapter = SlackAdapter(config: slack)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg) ?? "Error: gateway not available"
            }
            adapters.append(adapter)
        }

        if let discord = gatewayConfig.discord, discord.enabled {
            let adapter = DiscordAdapter(config: discord)
            adapter.onMessage { [weak self] msg in
                await self?.handleMessage(msg) ?? "Error: gateway not available"
            }
            adapters.append(adapter)
        }

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

    private func handleMessage(_ message: GatewayMessage) async -> String {
        let sessionKey = "\(message.platform):\(message.chatId)"

        // Get or create session (one AgentLoop per chat for conversation continuity)
        let agent: AgentLoop
        sessionsLock.lock()
        if let existing = sessions[sessionKey] {
            agent = existing
            sessionsLock.unlock()
        } else {
            let newAgent = AgentLoop(config: config, mcpManager: mcpManager)
            sessions[sessionKey] = newAgent
            agent = newAgent
            sessionsLock.unlock()
        }

        // Process message
        do {
            let contextPrefix = "[\(message.platform.uppercased()) from \(message.userName)]: "
            let response = try await agent.processUserInput(contextPrefix + message.text)
            return response.isEmpty ? "Done." : response
        } catch {
            printColored("  ✗ Error processing message: \(error)", color: .red)
            return "Sorry, I encountered an error: \(error.localizedDescription)"
        }
    }

    // MARK: - Wait

    private func waitForever() async {
        // Block until the process is killed
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // This continuation never resumes — keeps the gateway alive
            // Process termination (Ctrl+C) will kill it
            signal(SIGINT) { _ in
                print("\n")
                printColored("  Gateway shutting down...", color: .gray)
                exit(0)
            }
            signal(SIGTERM) { _ in
                exit(0)
            }
        }
    }
}
