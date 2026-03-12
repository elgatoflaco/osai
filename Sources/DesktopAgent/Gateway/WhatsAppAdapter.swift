import Foundation

// MARK: - WhatsApp Adapter (via wacli CLI)

final class WhatsAppAdapter: GatewayAdapter {
    let platform = "whatsapp"
    private let config: WhatsAppGatewayConfig
    private var messageHandler: ((GatewayMessage) async -> Void)?
    private var running = false
    private var task: Task<Void, Never>?
    private var lastSeen: [String: Date] = [:]  // chatJID → last message timestamp
    private let wacliPath = "/opt/homebrew/bin/wacli"

    var isRunning: Bool { running }

    init(config: WhatsAppGatewayConfig) {
        self.config = config
    }

    func onMessage(_ handler: @escaping (GatewayMessage) async -> Void) {
        self.messageHandler = handler
    }

    func sendMessage(chatId: String, text: String) async {
        let sendResult = runWacli(["send", "text", "--to", chatId, "--message", text, "--json"])
        if sendResult.success {
            printColored("  ✓ WhatsApp → \(chatId): sent (\(text.count) chars)", color: .green)
        } else {
            printColored("  ✗ WhatsApp send failed: \(sendResult.output)", color: .red)
        }
    }

    func sendTypingIndicator(chatId: String) async {
        // WhatsApp via wacli doesn't support typing indicators
    }

    func start() async throws {
        // Check wacli exists
        guard FileManager.default.fileExists(atPath: wacliPath) else {
            throw GatewayError.authFailed("WhatsApp: wacli not found at \(wacliPath). Install from https://github.com/nicois/wacli")
        }

        // Check auth
        let result = runWacli(["chats", "list", "--limit", "1", "--json"])
        guard result.success else {
            throw GatewayError.authFailed("WhatsApp: wacli not authenticated. Run `wacli auth` first.")
        }

        // Sync to get latest messages
        printColored("  ⏳ WhatsApp: syncing...", color: .gray)
        _ = runWacli(["sync", "--json"])

        // Initialize lastSeen with current timestamps
        initializeLastSeen()

        running = true
        printColored("  ✓ WhatsApp: connected via wacli", color: .green)

        // Start polling
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
        let interval = UInt64((config.pollInterval ?? 5)) * 1_000_000_000
        while running && !Task.isCancelled {
            await checkNewMessages()
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    private func initializeLastSeen() {
        let result = runWacli(["chats", "list", "--limit", "50", "--json"])
        guard result.success,
              let json = parseJSON(result.output),
              let data = json["data"] as? [[String: Any]] else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()

        for chat in data {
            guard let jid = chat["JID"] as? String,
                  let ts = chat["LastMessageTS"] as? String else { continue }
            if let date = formatter.date(from: ts) ?? fallback.date(from: ts) {
                lastSeen[jid] = date
            }
        }
    }

    private func checkNewMessages() async {
        // Get recent chats
        let result = runWacli(["chats", "list", "--limit", "20", "--json"])
        guard result.success,
              let json = parseJSON(result.output),
              let chats = json["data"] as? [[String: Any]] else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()

        for chat in chats {
            guard let jid = chat["JID"] as? String,
                  let tsStr = chat["LastMessageTS"] as? String,
                  let msgDate = formatter.date(from: tsStr) ?? fallback.date(from: tsStr) else { continue }

            let lastDate = lastSeen[jid] ?? Date.distantPast

            // New message?
            if msgDate > lastDate {
                lastSeen[jid] = msgDate

                // Skip if we're just initializing
                if lastDate == Date.distantPast { continue }

                // Check whitelist
                if let allowed = config.allowedJIDs, !allowed.contains(jid) { continue }

                // Fetch the actual new messages
                await processNewMessages(chatJID: jid, after: lastDate, chatName: chat["Name"] as? String ?? jid)
            }
        }
    }

    private func processNewMessages(chatJID: String, after: Date, chatName: String) async {
        let afterStr = ISO8601DateFormatter().string(from: after)
        let result = runWacli(["messages", "list", "--chat", chatJID, "--after", afterStr, "--limit", "5", "--json"])
        guard result.success,
              let json = parseJSON(result.output),
              let messages = json["data"] as? [[String: Any]] else { return }

        for msg in messages {
            // Skip our own messages
            let isFromMe = msg["IsFromMe"] as? Bool ?? false
            if isFromMe { continue }

            let text = msg["Text"] as? String ?? msg["Body"] as? String ?? ""
            if text.isEmpty { continue }

            let senderJID = msg["SenderJID"] as? String ?? chatJID
            let senderName = msg["SenderName"] as? String ?? msg["PushName"] as? String ?? chatName

            // Check sender against whitelist (important for group chats)
            if let allowed = config.allowedJIDs, !allowed.isEmpty {
                if !allowed.contains(senderJID) && !allowed.contains(chatJID) {
                    printColored("  ⚠ WhatsApp: blocked message from \(senderName) (\(senderJID))", color: .yellow)
                    continue
                }
            }

            let gwMessage = GatewayMessage(
                platform: "whatsapp",
                chatId: chatJID,
                userId: senderJID,
                userName: senderName,
                text: text,
                timestamp: Date(),
                replyToMessageId: nil
            )

            printColored("  📨 WhatsApp [\(senderName)]: \(String(text.prefix(80)))", color: .cyan)

            // Fire-and-forget: responses are sent via streaming callback + sendMessage
            if let handler = messageHandler {
                await handler(gwMessage)
            }
        }
    }

    // MARK: - wacli execution

    private func runWacli(_ args: [String]) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: wacliPath)
        process.arguments = args

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, "Failed to run wacli: \(error)")
        }
    }

    private func parseJSON(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
