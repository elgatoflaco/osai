import Foundation

// MARK: - WhatsApp Adapter (via wacli CLI)
//
// Architecture: All wacli operations are serialized in a single loop to avoid
// lock contention. wacli uses an exclusive file lock per store — only one wacli
// process can access the store at a time. The loop is: sync → check → respond → wait.
// Outbound messages are queued and sent during the "respond" phase of the loop.

final class WhatsAppAdapter: GatewayAdapter {
    let platform = "whatsapp"
    private let config: WhatsAppGatewayConfig
    private var messageHandler: ((GatewayMessage) async -> Void)?
    private var running = false
    private var task: Task<Void, Never>?
    private var lastSeen: [String: Date] = [:]  // chatJID → last message timestamp
    private let wacliPath = "/opt/homebrew/bin/wacli"

    /// Track message IDs sent by osai to avoid responding to our own replies
    private var sentMessageIds: Set<String> = []
    private let maxSentIds = 200

    /// Outbound message queue — messages are queued here and drained in the main loop
    /// after sync completes, so send and sync never hold the lock simultaneously.
    private var outboundQueue: [(chatId: String, text: String)] = []
    private let queueLock = NSLock()

    var isRunning: Bool { running }

    init(config: WhatsAppGatewayConfig) {
        self.config = config
    }

    func onMessage(_ handler: @escaping (GatewayMessage) async -> Void) {
        self.messageHandler = handler
    }

    func sendMessage(chatId: String, text: String) async {
        // Queue the message — the main loop will drain it after sync.
        // NSLock is safe here: the lock is held for a trivial append, no awaits inside.
        enqueueOutbound(chatId: chatId, text: text)
    }

    /// Thread-safe enqueue (non-async to avoid Swift 6 NSLock warning)
    private nonisolated func enqueueOutbound(chatId: String, text: String) {
        queueLock.lock()
        outboundQueue.append((chatId: chatId, text: text))
        queueLock.unlock()
    }

    func sendTypingIndicator(chatId: String) async {
        // WhatsApp via wacli doesn't support typing indicators
    }

    func start() async throws {
        // Check wacli exists
        guard FileManager.default.fileExists(atPath: wacliPath) else {
            throw GatewayError.authFailed("WhatsApp: wacli not found at \(wacliPath). Install from https://github.com/steipete/wacli")
        }

        // Kill any stale wacli processes that hold the lock
        killStaleWacli()

        // Check auth (read-only, no lock needed since no sync is running)
        let result = runWacli(["chats", "list", "--limit", "1", "--json"])
        guard result.success else {
            throw GatewayError.authFailed("WhatsApp: wacli not authenticated. Run `wacli auth` first.")
        }

        // Initialize lastSeen from local DB (no sync needed)
        initializeLastSeen()

        running = true
        printColored("  ✓ WhatsApp: connected via wacli", color: .green)

        // Single serialized loop: sync → drain outbound → check inbound → wait
        task = Task { [weak self] in
            await self?.mainLoop()
        }
    }

    func stop() {
        running = false
        task?.cancel()
        task = nil
        killStaleWacli()
    }

    /// Kill orphaned wacli processes that hold the store lock
    private func killStaleWacli() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        proc.arguments = ["-f", "wacli sync"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.3)
    }

    // MARK: - Serialized Main Loop

    /// Single loop that serializes all wacli access: sync → send → check → wait.
    /// This prevents lock contention since only one wacli process runs at a time.
    private func mainLoop() async {
        let interval = UInt64(max(config.pollInterval ?? 8, 3)) * 1_000_000_000

        while running && !Task.isCancelled {
            // Phase 1: Sync new messages from WhatsApp servers
            _ = runWacli(["sync", "--once", "--idle-exit", "5s", "--json"])

            // Phase 2: Drain outbound message queue (send doesn't need sync running)
            drainOutboundQueue()

            // Phase 3: Check for new inbound messages
            await checkNewMessages()

            // Phase 4: Wait before next cycle
            try? await Task.sleep(nanoseconds: interval)
        }
    }

    /// Send all queued outbound messages. Called after sync finishes so no lock conflict.
    private func drainOutboundQueue() {
        queueLock.lock()
        let messages = outboundQueue
        outboundQueue.removeAll()
        queueLock.unlock()

        for msg in messages {
            let sendResult = runWacli(["send", "text", "--to", msg.chatId, "--message", msg.text, "--json"])
            if sendResult.success {
                // Track sent message ID to skip during polling
                if let json = parseJSON(sendResult.output),
                   let data = json["data"] as? [String: Any],
                   let msgId = data["id"] as? String {
                    sentMessageIds.insert(msgId)
                    if sentMessageIds.count > maxSentIds {
                        sentMessageIds.removeFirst()
                    }
                }
                printColored("  ✓ WhatsApp → \(msg.chatId): sent (\(msg.text.count) chars)", color: .green)
            } else {
                printColored("  ✗ WhatsApp send failed: \(sendResult.output)", color: .red)
            }
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

                // Check whitelist (skip if wildcard "*")
                if let allowed = config.allowedJIDs, !allowed.isEmpty, !allowed.contains("*"), !allowed.contains(jid) { continue }

                // Fetch the actual new messages
                await processNewMessages(chatJID: jid, after: lastDate, chatName: chat["Name"] as? String ?? jid)
            }
        }
    }

    private func processNewMessages(chatJID: String, after: Date, chatName: String) async {
        let afterStr = ISO8601DateFormatter().string(from: after)
        let result = runWacli(["messages", "list", "--chat", chatJID, "--after", afterStr, "--limit", "5", "--json"])
        guard result.success,
              let json = parseJSON(result.output) else { return }
        // wacli returns messages as data.messages or data directly
        let dataObj = json["data"]
        let messages: [[String: Any]]
        if let dataDict = dataObj as? [String: Any], let msgs = dataDict["messages"] as? [[String: Any]] {
            messages = msgs
        } else if let msgs = dataObj as? [[String: Any]] {
            messages = msgs
        } else {
            return
        }

        for msg in messages {
            let msgId = msg["MsgID"] as? String ?? msg["ID"] as? String ?? ""

            // Skip messages sent by osai (tracked by ID)
            if sentMessageIds.contains(msgId) {
                sentMessageIds.remove(msgId)
                continue
            }

            // For IsFromMe messages: allow them (user sending from phone)
            // but skip if they look like osai responses (no msgId tracked = old safety net)

            let text = msg["Text"] as? String ?? msg["Body"] as? String ?? ""
            if text.isEmpty { continue }

            let isFromMe = msg["FromMe"] as? Bool ?? msg["IsFromMe"] as? Bool ?? false
            let senderJID = msg["SenderJID"] as? String ?? chatJID
            let senderName: String
            if isFromMe {
                senderName = "Me"
            } else {
                senderName = msg["SenderName"] as? String ?? msg["PushName"] as? String ?? chatName
            }

            // Check sender against whitelist (important for group chats, skip for own messages)
            if !isFromMe, let allowed = config.allowedJIDs, !allowed.isEmpty, !allowed.contains("*") {
                if !allowed.contains(senderJID) && !allowed.contains(chatJID) {
                    printColored("  ⚠ WhatsApp: blocked message from \(senderName) (\(senderJID))", color: .yellow)
                    continue
                }
            }

            let gwMessage = GatewayMessage(
                platform: "whatsapp",
                chatId: chatJID,
                userId: isFromMe ? "me" : senderJID,
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
