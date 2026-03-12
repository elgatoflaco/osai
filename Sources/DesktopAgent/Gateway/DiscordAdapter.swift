import Foundation

// MARK: - Discord Adapter (Bot via WebSocket Gateway)
//
// Requires:
//   - Discord Bot Token
//   - MESSAGE CONTENT intent enabled in Discord Developer Portal

final class DiscordAdapter: GatewayAdapter {
    let platform = "discord"
    private let config: DiscordGatewayConfig
    private var messageHandler: ((GatewayMessage) async -> Void)?
    private var running = false
    private var task: Task<Void, Never>?
    private var wsTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var sequenceNumber: Int?
    private var botUserId: String = ""

    // Reuse a single URLSession across reconnections to prevent resource leaks
    private let wsSession = URLSession(configuration: .default)

    var isRunning: Bool { running }

    init(config: DiscordGatewayConfig) {
        self.config = config
    }

    func onMessage(_ handler: @escaping (GatewayMessage) async -> Void) {
        self.messageHandler = handler
    }

    func sendMessage(chatId: String, text: String) async {
        let chunks = splitMessage(text, maxLength: 2000)
        for chunk in chunks {
            _ = try? await discordAPI("POST", path: "/channels/\(chatId)/messages",
                                      body: ["content": chunk])
        }
    }

    func start() async throws {
        running = true

        // Get gateway URL
        let gwURL = try await getGatewayURL()
        printColored("  ⏳ Discord: connecting...", color: .gray)

        task = Task { [weak self] in
            await self?.wsLoop(url: gwURL)
        }
    }

    func stop() {
        running = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        task?.cancel()
        task = nil
    }

    // MARK: - WebSocket

    private func wsLoop(url: URL) async {
        while running && !Task.isCancelled {
            // Cancel previous WebSocket before creating a new one to prevent leaks
            wsTask?.cancel(with: .goingAway, reason: nil)
            let ws = wsSession.webSocketTask(with: url)
            wsTask = ws
            ws.resume()

            do {
                while running {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        await handleGatewayMessage(text, ws: ws)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await handleGatewayMessage(text, ws: ws)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                if running {
                    printColored("  ⚠ Discord disconnected: \(error). Reconnecting...", color: .yellow)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    private func handleGatewayMessage(_ text: String, ws: URLSessionWebSocketTask) async {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }

        let op = json["op"] as? Int ?? -1
        if let s = json["s"] as? Int { sequenceNumber = s }

        switch op {
        case 10: // Hello — start heartbeat and identify
            let d = json["d"] as? [String: Any]
            let interval = d?["heartbeat_interval"] as? Int ?? 41250
            startHeartbeat(ws: ws, interval: interval)
            await identify(ws: ws)

        case 0: // Dispatch
            let t = json["t"] as? String ?? ""
            let d = json["d"] as? [String: Any] ?? [:]

            if t == "READY" {
                let user = d["user"] as? [String: Any] ?? [:]
                botUserId = user["id"] as? String ?? ""
                let username = user["username"] as? String ?? "bot"
                printColored("  ✓ Discord: \(username) connected", color: .green)
            }

            if t == "MESSAGE_CREATE" {
                await handleMessage(d)
            }

        case 11: // Heartbeat ACK
            break

        case 1: // Heartbeat request
            await sendHeartbeat(ws: ws)

        default:
            break
        }
    }

    private func handleMessage(_ d: [String: Any]) async {
        let author = d["author"] as? [String: Any] ?? [:]
        let authorId = author["id"] as? String ?? ""

        // Skip own messages and bots
        if authorId == botUserId { return }
        if author["bot"] as? Bool == true { return }

        let content = d["content"] as? String ?? ""
        if content.isEmpty { return }

        let channelId = d["channel_id"] as? String ?? ""
        let guildId = d["guild_id"] as? String

        // Check user whitelist
        if let allowedUsers = config.allowedUsers, !allowedUsers.isEmpty {
            if !allowedUsers.contains(authorId) {
                let name = author["username"] as? String ?? "unknown"
                printColored("  ⚠ Discord: blocked message from \(name) (id: \(authorId))", color: .yellow)
                return
            }
        }

        // Check guild whitelist
        if let allowed = config.allowedGuilds, !allowed.isEmpty {
            if let gid = guildId, !allowed.contains(gid) { return }
        }

        let userName = author["username"] as? String ?? "Unknown"

        let gwMessage = GatewayMessage(
            platform: "discord",
            chatId: channelId,
            userId: authorId,
            userName: userName,
            text: content,
            timestamp: Date(),
            replyToMessageId: nil
        )

        printColored("  📨 Discord [\(userName)]: \(String(content.prefix(80)))", color: .cyan)

        // Send typing indicator
        _ = try? await discordAPI("POST", path: "/channels/\(channelId)/typing")

        // Fire-and-forget: responses are sent via streaming callback + sendMessage
        if let handler = messageHandler {
            await handler(gwMessage)
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(ws: URLSessionWebSocketTask, interval: Int) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            let ns = UInt64(interval) * 1_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                guard let self = self, self.running else { return }
                await self.sendHeartbeat(ws: ws)
            }
        }
    }

    private func sendHeartbeat(ws: URLSessionWebSocketTask) async {
        let payload: [String: Any?] = ["op": 1, "d": sequenceNumber]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? await ws.send(.data(data))
        }
    }

    private func identify(ws: URLSessionWebSocketTask) async {
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": config.botToken,
                "intents": 37377,  // GUILDS(1) | GUILD_MESSAGES(512) | DIRECT_MESSAGES(4096) | MESSAGE_CONTENT(32768)
                "properties": [
                    "os": "macos",
                    "browser": "osai",
                    "device": "osai"
                ]
            ] as [String: Any]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? await ws.send(.data(data))
        }
    }

    // MARK: - API

    private func getGatewayURL() async throws -> URL {
        let result = try await discordAPI("GET", path: "/gateway/bot")
        guard let urlStr = result["url"] as? String,
              let url = URL(string: urlStr + "?v=10&encoding=json") else {
            throw GatewayError.authFailed("Discord: failed to get gateway URL")
        }
        return url
    }

    @discardableResult
    private func discordAPI(_ method: String, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let url = URL(string: "https://discord.com/api/v10\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bot \(config.botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func splitMessage(_ text: String, maxLength: Int) -> [String] {
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
}
