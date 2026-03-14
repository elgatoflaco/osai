import Foundation

// MARK: - MCP Client (JSON-RPC 2.0 over stdio)

final class MCPClient {
    let serverName: String
    let config: MCPServerConfig
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var nextId: Int = 1
    private let lock = NSLock()
    private var buffer = Data()

    // Buffer safety: prevent OOM from malicious/runaway MCP servers
    private static let maxBufferSize = 10 * 1024 * 1024  // 10 MB
    // Per-request timeout (overridable for slow tools)
    private let requestTimeout: TimeInterval

    /// Set to true to interrupt a blocking readResponse() call
    var interrupted = false

    var isRunning: Bool { process?.isRunning ?? false }

    init(serverName: String, config: MCPServerConfig, requestTimeout: TimeInterval = 30) {
        self.serverName = serverName
        self.config = config
        self.requestTimeout = requestTimeout
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() throws {
        let proc = Process()

        // Resolve command path
        if config.command.hasPrefix("/") {
            proc.executableURL = URL(fileURLWithPath: config.command)
            proc.arguments = config.args ?? []
        } else {
            // Use /usr/bin/env to search PATH for the command
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [config.command] + (config.args ?? [])
        }

        // Environment
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let extraEnv = config.env {
            for (k, v) in extraEnv { env[k] = v }
        }
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()

        self.process = proc
        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading

        // Capture stderr for diagnostics and to prevent pipe buffer deadlocks
        var stderrChunks: [String] = []
        let stderrLock = NSLock()
        let stderrHandle = stderrPipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            while true {
                let data = stderrHandle.availableData
                if data.isEmpty { break }  // EOF — process exited
                if let text = String(data: data, encoding: .utf8) {
                    stderrLock.lock()
                    stderrChunks.append(text)
                    stderrLock.unlock()
                }
            }
        }

        // Initialize MCP handshake — if this fails, clean up the process
        do {
            let initParams: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": [String: Any](),
                "clientInfo": [
                    "name": "DesktopAgent",
                    "version": "2.0"
                ]
            ]

            let response = try sendRequest(method: "initialize", params: initParams)

            // Send initialized notification
            sendNotification(method: "notifications/initialized")

            if response.error != nil {
                throw MCPError.initFailed(response.error?.message ?? "Unknown error")
            }
        } catch {
            // Clean up process to prevent zombies
            stderrLock.lock()
            let stderr = stderrChunks.joined()
            stderrLock.unlock()
            stop()
            // Include stderr in error message for diagnostics
            if !stderr.isEmpty {
                throw MCPError.initFailed("\(error) — stderr: \(stderr.prefix(500))")
            }
            throw error
        }
    }

    func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
        stdin = nil
        stdout = nil
    }

    // MARK: - Tool Discovery

    func listTools() throws -> [MCPToolInfo] {
        let response = try sendRequest(method: "tools/list", params: nil)

        guard let result = response.result?.value as? [String: Any],
              let toolsArray = result["tools"] as? [[String: Any]] else {
            return []
        }

        return toolsArray.compactMap { toolDict -> MCPToolInfo? in
            guard let name = toolDict["name"] as? String,
                  let description = toolDict["description"] as? String else { return nil }
            let inputSchema = toolDict["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [String: Any]()]
            return MCPToolInfo(
                serverName: serverName,
                name: name,
                description: description,
                inputSchema: inputSchema
            )
        }
    }

    // MARK: - Tool Execution

    func callTool(name: String, arguments: [String: Any]) throws -> String {
        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]

        let response = try sendRequest(method: "tools/call", params: params)

        if let error = response.error {
            return "MCP Error: \(error.message)"
        }

        guard let result = response.result?.value as? [String: Any],
              let content = result["content"] as? [[String: Any]] else {
            return "OK (no content)"
        }

        // Extract text from content blocks
        let texts = content.compactMap { block -> String? in
            if block["type"] as? String == "text" {
                return block["text"] as? String
            }
            return nil
        }

        return texts.joined(separator: "\n")
    }

    // MARK: - JSON-RPC Transport

    private func sendRequest(method: String, params: Any?) throws -> JSONRPCResponse {
        lock.lock()
        let id = nextId
        nextId += 1
        lock.unlock()

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)

        guard let stdin = stdin else {
            throw MCPError.notRunning
        }

        // Write request as a single line + newline
        var message = data
        message.append(contentsOf: [0x0A]) // newline
        stdin.write(message)

        // Read response
        return try readResponse(expectedId: id)
    }

    private func sendNotification(method: String) {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: notification),
              let stdin = stdin else { return }
        var message = data
        message.append(contentsOf: [0x0A])
        stdin.write(message)
    }

    private func readResponse(expectedId: Int) throws -> JSONRPCResponse {
        guard let stdout = stdout else {
            throw MCPError.notRunning
        }

        let fd = stdout.fileDescriptor
        let deadline = Date().addingTimeInterval(requestTimeout)

        while Date() < deadline {
            // Check for interruption (Ctrl+C cancel)
            if interrupted {
                interrupted = false
                throw MCPError.timeout
            }

            // Use poll() to check if data is available without blocking
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = deadline.timeIntervalSinceNow
            let timeoutMs = max(0, Int32(remaining * 1000))
            let ret = poll(&pfd, 1, min(timeoutMs, 200)) // check every 200ms for faster cancel

            if ret > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                // Data available — read it
                var readBuf = [UInt8](repeating: 0, count: 8192)
                let n = read(fd, &readBuf, readBuf.count)
                if n > 0 {
                    buffer.append(contentsOf: readBuf[0..<n])

                    // Guard against unbounded buffer growth (malicious/runaway server)
                    if buffer.count > Self.maxBufferSize {
                        buffer.removeAll()
                        throw MCPError.initFailed("Server exceeded \(Self.maxBufferSize / 1024 / 1024)MB buffer limit")
                    }

                    // Try to parse complete JSON lines
                    while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer[buffer.startIndex..<newlineIndex]
                        buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                        if lineData.isEmpty { continue }

                        if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: Data(lineData)) {
                            if response.id == expectedId {
                                return response
                            }
                            // Skip notifications or responses for other IDs
                        }
                    }
                } else if n == 0 {
                    // EOF — server closed
                    throw MCPError.initFailed("Server process exited unexpectedly")
                }
            } else if ret < 0 {
                throw MCPError.initFailed("poll() error: \(errno)")
            }
            // ret == 0 means timeout on this poll iteration, loop continues
        }

        throw MCPError.timeout
    }
}

// MARK: - Errors

enum MCPError: Error, CustomStringConvertible {
    case initFailed(String)
    case notRunning
    case timeout
    case serverNotFound(String)
    case toolNotFound(String)

    var description: String {
        switch self {
        case .initFailed(let msg): return "MCP init failed: \(msg)"
        case .notRunning: return "MCP server not running"
        case .timeout: return "MCP request timed out"
        case .serverNotFound(let name): return "MCP server '\(name)' not found in config"
        case .toolNotFound(let name): return "MCP tool '\(name)' not found"
        }
    }
}
