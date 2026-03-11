import Foundation

// MARK: - Slack Adapter (Socket Mode via WebSocket)
//
// Requires:
//   - Slack App with Socket Mode enabled
//   - Bot token (xoxb-...) with chat:write, im:history, im:read scopes
//   - App-level token (xapp-...) for Socket Mode connection

final class SlackAdapter: GatewayAdapter {
    let platform = "slack"
    private let config: SlackGatewayConfig
    private var messageHandler: ((GatewayMessage) async -> String)?
    private var running = false
    private var task: Task<Void, Never>?
    private var wsTask: URLSessionWebSocketTask?

    var isRunning: Bool { running }

    init(config: SlackGatewayConfig) {
        self.config = config
    }

    func onMessage(_ handler: @escaping (GatewayMessage) async -> String) {
        self.messageHandler = handler
    }

    func start() async throws {
        running = true

        // Get WebSocket URL via apps.connections.open
        let wsURL = try await getWebSocketURL()

        // Test auth
        let auth = try await slackAPI("auth.test")
        let botName = auth["user"] as? String ?? "bot"
        let botUserId = auth["user_id"] as? String ?? ""
        printColored("  ✓ Slack: @\(botName) connected (Socket Mode)", color: .green)

        // Connect WebSocket
        task = Task { [weak self] in
            await self?.wsLoop(url: wsURL, botUserId: botUserId)
        }
    }

    func stop() {
        running = false
        wsTask?.cancel(with: .goingAway, reason: nil)
        task?.cancel()
        task = nil
    }

    // MARK: - WebSocket

    private func wsLoop(url: URL, botUserId: String) async {
        while running && !Task.isCancelled {
            let session = URLSession(configuration: .default)
            let ws = session.webSocketTask(with: url)
            wsTask = ws
            ws.resume()

            do {
                while running {
                    let message = try await ws.receive()
                    switch message {
                    case .string(let text):
                        await handleWSMessage(text, botUserId: botUserId, ws: ws)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await handleWSMessage(text, botUserId: botUserId, ws: ws)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                if running {
                    printColored("  ⚠ Slack WebSocket disconnected: \(error). Reconnecting...", color: .yellow)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    private func handleWSMessage(_ text: String, botUserId: String, ws: URLSessionWebSocketTask) async {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""

        // Acknowledge envelope
        if let envelopeId = json["envelope_id"] as? String {
            let ack = try? JSONSerialization.data(withJSONObject: ["envelope_id": envelopeId])
            if let ack = ack {
                try? await ws.send(.data(ack))
            }
        }

        // Handle events
        if type == "events_api" {
            guard let payload = json["payload"] as? [String: Any],
                  let event = payload["event"] as? [String: Any] else { return }

            let eventType = event["type"] as? String ?? ""
            guard eventType == "message" else { return }

            // Skip bot's own messages
            let user = event["user"] as? String ?? ""
            if user == botUserId || user.isEmpty { return }
            if event["bot_id"] != nil { return }

            let msgText = event["text"] as? String ?? ""
            let channel = event["channel"] as? String ?? ""
            if msgText.isEmpty { return }

            // Check channel whitelist
            if let allowed = config.allowedChannels, !allowed.isEmpty, !allowed.contains(channel) { return }

            let gwMessage = GatewayMessage(
                platform: "slack",
                chatId: channel,
                userId: user,
                userName: user,
                text: msgText,
                timestamp: Date(),
                replyToMessageId: nil
            )

            printColored("  📨 Slack [\(user)]: \(String(msgText.prefix(80)))", color: .cyan)

            if let handler = messageHandler {
                let response = await handler(gwMessage)
                _ = try? await postMessage(channel: channel, text: response)
            }
        }
    }

    // MARK: - Slack API

    private func getWebSocketURL() async throws -> URL {
        let url = URL(string: "https://slack.com/api/apps.connections.open")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.appToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let urlStr = json["url"] as? String,
              let wsURL = URL(string: urlStr) else {
            throw GatewayError.authFailed("Slack: failed to get WebSocket URL. Check app_token.")
        }
        return wsURL
    }

    private func slackAPI(_ method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let url = URL(string: "https://slack.com/api/\(method)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        if let params = params {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GatewayError.apiError("Invalid Slack response")
        }
        return json
    }

    private func postMessage(channel: String, text: String) async throws -> [String: Any] {
        return try await slackAPI("chat.postMessage", params: [
            "channel": channel,
            "text": text
        ])
    }
}
