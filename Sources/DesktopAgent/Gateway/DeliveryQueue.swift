import Foundation

// MARK: - Delivery Queue (disk-based retry queue for reliable message delivery)

final class DeliveryQueue {
    static let queueDir = NSHomeDirectory() + "/.desktop-agent/delivery-queue"

    struct PendingDelivery: Codable {
        let id: String
        let target: String      // "discord:channelId" or "telegram:chatId"
        let message: String
        let created: Date
        var attempts: Int
        var lastAttempt: Date?
    }

    // MARK: - Queue Operations

    /// Enqueue a delivery (write to disk before attempting send)
    @discardableResult
    static func enqueue(target: String, message: String) -> PendingDelivery {
        ensureDir()
        let delivery = PendingDelivery(
            id: UUID().uuidString,
            target: target,
            message: message,
            created: Date(),
            attempts: 0,
            lastAttempt: nil
        )
        let path = filePath(for: delivery.id)
        if let data = try? JSONEncoder().encode(delivery) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        return delivery
    }

    /// Mark delivery as completed (delete from disk)
    static func complete(id: String) {
        let path = filePath(for: id)
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Mark delivery as failed (update attempt count)
    static func fail(id: String) {
        let path = filePath(for: id)
        guard let data = FileManager.default.contents(atPath: path),
              var delivery = try? JSONDecoder().decode(PendingDelivery.self, from: data) else {
            return
        }
        delivery.attempts += 1
        delivery.lastAttempt = Date()
        if let updated = try? JSONEncoder().encode(delivery) {
            try? updated.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Get all pending deliveries (for retry on startup)
    static func pending() -> [PendingDelivery] {
        ensureDir()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: queueDir) else { return [] }
        var deliveries: [PendingDelivery] = []
        for file in files where file.hasSuffix(".json") {
            let path = queueDir + "/" + file
            if let data = fm.contents(atPath: path),
               let delivery = try? JSONDecoder().decode(PendingDelivery.self, from: data) {
                deliveries.append(delivery)
            }
        }
        return deliveries.sorted { $0.created < $1.created }
    }

    /// Retry failed deliveries (call on startup). Returns count of retried items.
    static func retryPending() async -> Int {
        let items = pending()
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        var retried = 0

        for item in items {
            // Skip items older than 24 hours
            if item.created < cutoff {
                complete(id: item.id)
                continue
            }
            // Skip items with too many attempts
            if item.attempts >= 5 {
                complete(id: item.id)
                continue
            }

            let success = await deliverDirectly(target: item.target, message: item.message)
            if success {
                complete(id: item.id)
                retried += 1
            } else {
                fail(id: item.id)
            }
        }
        return retried
    }

    // MARK: - Direct Delivery (duplicated HTTP logic for retry independence)

    /// Send a message directly via REST API. Returns true on success.
    private static func deliverDirectly(target: String, message: String) async -> Bool {
        let parts = target.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let platform = String(parts[0])
        let chatId = String(parts[1])

        let fileConfig = AgentConfigFile.load()

        switch platform {
        case "discord":
            guard let discord = fileConfig.gateways?.discord else { return false }
            do {
                let url = URL(string: "https://discord.com/api/v10/channels/\(chatId)/messages")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bot \(discord.botToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                // For retry, just send as plain content (truncated to 2000 if needed)
                let truncated = String(message.prefix(2000))
                request.httpBody = try JSONSerialization.data(withJSONObject: ["content": truncated])
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode < 300 {
                    return true
                }
            } catch {}
            return false

        case "telegram":
            guard let tg = fileConfig.gateways?.telegram else { return false }
            do {
                let url = URL(string: "https://api.telegram.org/bot\(tg.botToken)/sendMessage")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let truncated = String(message.prefix(4096))
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "chat_id": chatId, "text": truncated, "parse_mode": "Markdown"
                ] as [String: Any])
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode < 300 {
                    return true
                }
            } catch {}
            return false

        case "slack":
            guard let slack = fileConfig.gateways?.slack else { return false }
            do {
                let url = URL(string: "https://slack.com/api/chat.postMessage")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(slack.botToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "channel": chatId, "text": message
                ])
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode < 300 {
                    return true
                }
            } catch {}
            return false

        case "whatsapp":
            let wacliPath = "/opt/homebrew/bin/wacli"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: wacliPath)
            process.arguments = ["send", "text", "--to", chatId, "--message", message, "--json"]
            try? process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0

        default:
            return false
        }
    }

    // MARK: - Helpers

    private static func filePath(for id: String) -> String {
        return queueDir + "/" + id + ".json"
    }

    private static func ensureDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: queueDir) {
            try? fm.createDirectory(atPath: queueDir, withIntermediateDirectories: true)
        }
    }
}
