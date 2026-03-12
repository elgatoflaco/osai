import Foundation

// MARK: - Apple Watch Gateway Adapter (Bonjour + HTTP)
//
// Runs a lightweight HTTP server on the local network with Bonjour/mDNS
// auto-discovery. The companion watchOS app finds this service via
// NetServiceBrowser and sends messages as HTTP POST requests.
//
// Protocol:
//   POST /message   { "device_id": "...", "user_name": "...", "text": "..." }
//   → 200           { "status": "received" }
//   Responses streamed back via:
//   POST /poll       { "device_id": "..." }
//   → 200           { "messages": [ { "text": "..." } ] }
//
//   GET  /ping      → 200 { "status": "ok", "service": "osai" }

final class WatchGatewayAdapter: GatewayAdapter {
    let platform = "watch"
    private let config: WatchGatewayConfig
    private var messageHandler: ((GatewayMessage) async -> Void)?
    private var running = false
    private var serverSocket: Int32 = -1
    private var netService: NetService?
    private var listenTask: Task<Void, Never>?

    // Pending responses per device (accumulated until polled)
    private var pendingResponses: [String: [String]] = [:]
    private let pendingLock = NSLock()
    private let featureEndpoints = WatchFeatureEndpoints()

    var isRunning: Bool { running }

    init(config: WatchGatewayConfig) {
        self.config = config
    }

    func onMessage(_ handler: @escaping (GatewayMessage) async -> Void) {
        self.messageHandler = handler
    }

    func sendMessage(chatId: String, text: String) async {
        // Format for watch: truncate long responses, simplify markdown
        let formatted = formatForWatch(text)
        pendingLock.lock()
        pendingResponses[chatId, default: []].append(formatted)
        pendingLock.unlock()
    }

    func sendTypingIndicator(chatId: String) async {
        // Watch polls for responses; no push typing indicator needed
    }

    func start() async throws {
        let port = config.port ?? 8375

        // Create TCP socket
        serverSocket = socket(AF_INET6, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw GatewayError.networkError("Watch: failed to create socket")
        }

        var yes: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Allow both IPv4 and IPv6
        var no: Int32 = 0
        setsockopt(serverSocket, IPPROTO_IPV6, IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = UInt16(port).bigEndian
        addr.sin6_addr = in6addr_any

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverSocket)
            throw GatewayError.networkError("Watch: failed to bind port \(port) (errno \(errno))")
        }

        guard listen(serverSocket, 8) == 0 else {
            close(serverSocket)
            throw GatewayError.networkError("Watch: failed to listen")
        }

        running = true

        // Publish Bonjour service for auto-discovery
        let serviceName = config.serviceName ?? "osai"
        netService = NetService(domain: "local.", type: "_osai._tcp.", name: serviceName, port: Int32(port))
        netService?.publish()

        printColored("  ✓ Watch: listening on port \(port) (Bonjour: \(serviceName)._osai._tcp.local.)", color: .green)

        // Accept connections in background
        listenTask = Task { [weak self] in
            await self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        listenTask?.cancel()
        listenTask = nil
        netService?.stop()
        netService = nil
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    // MARK: - HTTP Server

    private func acceptLoop() async {
        // Make socket non-blocking for cancellation checks
        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        while running && !Task.isCancelled {
            var clientAddr = sockaddr_in6()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in6>.size)

            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &addrLen)
                }
            }

            if clientFd >= 0 {
                // Handle each connection concurrently
                Task { [weak self] in
                    await self?.handleConnection(clientFd)
                }
            } else {
                // No pending connection, short sleep to avoid busy-wait
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    private func handleConnection(_ fd: Int32) async {
        defer { close(fd) }

        // Set socket timeout
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Read request
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = recv(fd, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let requestData = Data(buffer[0..<bytesRead])
        guard let requestStr = String(data: requestData, encoding: .utf8) else { return }

        // Parse HTTP request line
        let lines = requestStr.split(separator: "\r\n", maxSplits: 1)
        guard let requestLine = lines.first else { return }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return }

        let method = String(parts[0])
        let path = String(parts[1])

        // Extract body (after \r\n\r\n)
        let body: String?
        if let range = requestStr.range(of: "\r\n\r\n") {
            let bodyStr = String(requestStr[range.upperBound...])
            body = bodyStr.isEmpty ? nil : bodyStr
        } else {
            body = nil
        }

        // Route requests
        switch (method, path) {
        case ("GET", "/ping"):
            let response = """
            {"status":"ok","service":"osai","platform":"watch"}
            """
            sendHTTPResponse(fd: fd, status: 200, body: response)

        case ("POST", "/message"):
            await handleIncomingMessage(fd: fd, body: body)

        case ("POST", "/poll"):
            handlePoll(fd: fd, body: body)

        case ("GET", "/status"), ("GET", "/complications"), ("GET", "/geofences"):
            let (status, responseBody) = featureEndpoints.handleRequest(method: method, path: path, body: body, deviceId: nil)
            sendHTTPResponse(fd: fd, status: status, body: responseBody)

        case ("POST", "/health"), ("POST", "/location"), ("POST", "/geofence"), ("DELETE", "/geofence"),
             ("POST", "/geofence/trigger"), ("POST", "/shortcut"):
            // Extract device_id from body for POST requests
            var deviceId: String? = nil
            if let body = body, let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                deviceId = json["device_id"] as? String
            }
            // Check device whitelist
            if let deviceId = deviceId, let allowed = config.allowedDevices, !allowed.contains(deviceId) {
                sendHTTPResponse(fd: fd, status: 403, body: "{\"error\":\"device not allowed\"}")
                return
            }
            let (status, responseBody) = featureEndpoints.handleRequest(method: method, path: path, body: body, deviceId: deviceId)
            sendHTTPResponse(fd: fd, status: status, body: responseBody)

            // If shortcut returned a command, inject as message
            if path == "/shortcut", let responseData = responseBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let command = json["command"] as? String, !command.isEmpty,
               let deviceId = deviceId {
                let message = GatewayMessage(
                    platform: "watch",
                    chatId: deviceId,
                    userId: deviceId,
                    userName: "Watch Shortcut",
                    text: command,
                    timestamp: Date(),
                    replyToMessageId: nil
                )
                if let handler = messageHandler {
                    await handler(message)
                }
            }

        default:
            sendHTTPResponse(fd: fd, status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    private func handleIncomingMessage(fd: Int32, body: String?) async {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceId = json["device_id"] as? String,
              let text = json["text"] as? String else {
            sendHTTPResponse(fd: fd, status: 400, body: "{\"error\":\"invalid request\"}")
            return
        }

        let userName = json["user_name"] as? String ?? "Watch User"

        // Check device whitelist
        if let allowed = config.allowedDevices, !allowed.contains(deviceId) {
            printColored("  ⚠ Watch: blocked message from device \(deviceId)", color: .yellow)
            sendHTTPResponse(fd: fd, status: 403, body: "{\"error\":\"device not allowed\"}")
            return
        }

        // Respond immediately to prevent watch timeout
        sendHTTPResponse(fd: fd, status: 200, body: "{\"status\":\"received\"}")

        let message = GatewayMessage(
            platform: "watch",
            chatId: deviceId,
            userId: deviceId,
            userName: userName,
            text: text,
            timestamp: Date(),
            replyToMessageId: nil
        )

        printColored("  ⌚ Watch [\(userName)]: \(String(text.prefix(80)))", color: .cyan)

        if let handler = messageHandler {
            await handler(message)
        }
    }

    private func handlePoll(fd: Int32, body: String?) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceId = json["device_id"] as? String else {
            sendHTTPResponse(fd: fd, status: 400, body: "{\"error\":\"invalid request\"}")
            return
        }

        // Check device whitelist
        if let allowed = config.allowedDevices, !allowed.contains(deviceId) {
            sendHTTPResponse(fd: fd, status: 403, body: "{\"error\":\"device not allowed\"}")
            return
        }

        // Drain pending messages for this device
        pendingLock.lock()
        let messages = pendingResponses[deviceId] ?? []
        pendingResponses[deviceId] = nil
        pendingLock.unlock()

        let responseMessages = messages.map { ["text": $0] }
        if let responseData = try? JSONSerialization.data(withJSONObject: ["messages": responseMessages]),
           let responseStr = String(data: responseData, encoding: .utf8) {
            sendHTTPResponse(fd: fd, status: 200, body: responseStr)
        } else {
            sendHTTPResponse(fd: fd, status: 200, body: "{\"messages\":[]}")
        }
    }

    // MARK: - HTTP Response

    private func sendHTTPResponse(fd: Int32, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(body)
        """

        _ = response.withCString { ptr in
            send(fd, ptr, strlen(ptr), 0)
        }
    }

    // MARK: - Watch Response Formatting

    private func formatForWatch(_ text: String) -> String {
        var result = text

        // Strip markdown formatting that doesn't render well on watch
        result = result.replacingOccurrences(of: "```[a-zA-Z]*\n", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "```", with: "")
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "##", with: "")

        // Truncate for watch display (configurable, default 500 chars)
        let maxLen = config.maxResponseLength ?? 500
        if result.count > maxLen {
            let truncIndex = result.index(result.startIndex, offsetBy: maxLen)
            // Try to break at a sentence or newline
            let truncated = String(result[..<truncIndex])
            if let lastPeriod = truncated.lastIndex(of: ".") {
                result = String(truncated[...lastPeriod]) + "\n[truncated]"
            } else if let lastNewline = truncated.lastIndex(of: "\n") {
                result = String(truncated[...lastNewline]) + "[truncated]"
            } else {
                result = truncated + "…"
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
