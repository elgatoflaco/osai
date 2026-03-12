import Foundation

// MARK: - Telegram Bot API Adapter (Long Polling)

final class TelegramAdapter: GatewayAdapter {
    let platform = "telegram"
    private let config: TelegramGatewayConfig
    private let baseURL: String
    private var offset: Int = 0
    private var messageHandler: ((GatewayMessage) async -> Void)?
    private var running = false
    private var task: Task<Void, Never>?

    var isRunning: Bool { running }

    init(config: TelegramGatewayConfig) {
        self.config = config
        self.baseURL = "https://api.telegram.org/bot\(config.botToken)"
    }

    func onMessage(_ handler: @escaping (GatewayMessage) async -> Void) {
        self.messageHandler = handler
    }

    func sendMessage(chatId: String, text: String) async {
        guard let chatIdInt = Int(chatId) else { return }
        let chunks = splitMessage(text, maxLength: 4096)
        for chunk in chunks {
            _ = try? await sendMessage(chatId: chatIdInt, text: chunk)
        }
    }

    func start() async throws {
        running = true

        // Verify bot token
        let me = try await apiCall("getMe")
        guard let result = me["result"] as? [String: Any],
              let botName = result["username"] as? String else {
            throw GatewayError.authFailed("Telegram: invalid bot token")
        }
        printColored("  ✓ Telegram: @\(botName) connected", color: .green)

        // Start polling loop
        task = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        running = false
        task?.cancel()
        task = nil
    }

    // MARK: - Polling

    private func pollLoop() async {
        while running && !Task.isCancelled {
            do {
                let updates = try await getUpdates()
                for update in updates {
                    await processUpdate(update)
                }
            } catch {
                if running {
                    printColored("  ⚠ Telegram poll error: \(error)", color: .yellow)
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s backoff
                }
            }
        }
    }

    private func getUpdates() async throws -> [[String: Any]] {
        let params: [String: Any] = [
            "offset": offset,
            "timeout": 30,
            "allowed_updates": ["message"]
        ]
        let response = try await apiCall("getUpdates", params: params)

        guard let results = response["result"] as? [[String: Any]] else {
            return []
        }
        return results
    }

    private func processUpdate(_ update: [String: Any]) async {
        guard let updateId = update["update_id"] as? Int else { return }
        offset = updateId + 1

        guard let message = update["message"] as? [String: Any],
              let text = message["text"] as? String,
              let from = message["from"] as? [String: Any],
              let chat = message["chat"] as? [String: Any],
              let chatId = chat["id"] as? Int else { return }

        let userId = from["id"] as? Int ?? 0
        let userName = from["first_name"] as? String ?? "Unknown"

        // Check whitelist
        if let allowed = config.allowedUsers, !allowed.contains(userId) {
            printColored("  ⚠ Telegram: blocked message from \(userName) (id: \(userId))", color: .yellow)
            return
        }

        // Skip commands that aren't for us
        if text.hasPrefix("/start") {
            _ = try? await sendMessage(chatId: chatId, text: "👋 Hey! I'm your AI assistant. Send me anything and I'll help.\n\nPowered by osai — Desktop Agent")
            return
        }

        let gwMessage = GatewayMessage(
            platform: "telegram",
            chatId: String(chatId),
            userId: String(userId),
            userName: userName,
            text: text,
            timestamp: Date(),
            replyToMessageId: nil
        )

        printColored("  📨 Telegram [\(userName)]: \(String(text.prefix(80)))", color: .cyan)

        // Send typing indicator
        _ = try? await apiCall("sendChatAction", params: ["chat_id": chatId, "action": "typing"])

        // Fire-and-forget: responses are sent via streaming callback + sendMessage
        if let handler = messageHandler {
            await handler(gwMessage)
        }
    }

    // MARK: - API

    private func sendMessage(chatId: Int, text: String) async throws -> [String: Any] {
        return try await apiCall("sendMessage", params: [
            "chat_id": chatId,
            "text": text,
            "parse_mode": "Markdown"
        ])
    }

    @discardableResult
    private func apiCall(_ method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = method == "getUpdates" ? 35 : 15

        if let params = params {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayError.networkError("No HTTP response")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GatewayError.networkError("Invalid JSON response")
        }

        if httpResponse.statusCode != 200 {
            let desc = json["description"] as? String ?? "HTTP \(httpResponse.statusCode)"
            throw GatewayError.apiError(desc)
        }

        return json
    }

    private func splitMessage(_ text: String, maxLength: Int) -> [String] {
        if text.count <= maxLength { return [text] }
        var chunks: [String] = []
        var remaining = text
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(maxLength, remaining.count))
            // Try to split at a newline
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
