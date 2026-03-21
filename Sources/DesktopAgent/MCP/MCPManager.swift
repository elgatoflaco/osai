import Foundation

// MARK: - MCP Server Manager

final class MCPManager {
    private var clients: [String: MCPClient] = [:]
    private var allTools: [String: (client: MCPClient, toolName: String)] = [:]
    private var toolInfos: [MCPToolInfo] = []

    var connectedServers: [String] { Array(clients.keys) }
    var availableTools: [MCPToolInfo] { toolInfos }

    // MARK: - Server Management

    func startServer(name: String, config: MCPServerConfig) throws {
        if clients[name]?.isRunning == true {
            printColored("  MCP server '\(name)' already running", color: .yellow)
            return
        }

        printColored("  Starting MCP server: \(name)...", color: .gray)
        // Use config timeout, or auto-detect browser servers (120s default)
        let timeout: TimeInterval
        if let configTimeout = config.timeout {
            timeout = TimeInterval(configTimeout)
        } else if Self.isBrowserServer(name: name, config: config) {
            timeout = 120  // Browser tools need more time for page loads
        } else {
            timeout = 30
        }
        let client = MCPClient(serverName: name, config: config, requestTimeout: timeout)
        try client.start()
        clients[name] = client

        // Discover tools
        let tools = try client.listTools()
        for tool in tools {
            allTools[tool.qualifiedName] = (client, tool.name)
            toolInfos.append(tool)
        }

        // Compact display: animate tool names scrolling, then show summary
        if !tools.isEmpty {
            let toolNames = tools.map { $0.name }
            let maxShow = min(toolNames.count, 12)
            for i in 0..<maxShow {
                let preview = toolNames[i...].prefix(4).joined(separator: ", ")
                let progress = String(repeating: "█", count: (i + 1) * 20 / maxShow)
                let remaining = String(repeating: "░", count: 20 - progress.count)
                let out = "\r\u{001B}[2K  \u{001B}[90m[\(progress)\(remaining)] \(preview)…\u{001B}[0m"
                write(STDOUT_FILENO, out, out.utf8.count)
                fflush(stdout)
                Thread.sleep(forTimeInterval: 0.04)
            }
            // Final line: clean summary
            let out = "\r\u{001B}[2K  \u{001B}[32m✓ \(name)\u{001B}[0m \u{001B}[90m— \(tools.count) tools\u{001B}[0m\n"
            write(STDOUT_FILENO, out, out.utf8.count)
        } else {
            printColored("  ✓ \(name): connected (no tools)", color: .green)
        }
    }

    func stopServer(name: String) {
        clients[name]?.stop()
        clients.removeValue(forKey: name)
        toolInfos.removeAll { $0.serverName == name }
        allTools = allTools.filter { $0.value.client.serverName != name }
    }

    func stopAll() {
        for (_, client) in clients {
            client.stop()
        }
        clients.removeAll()
        allTools.removeAll()
        toolInfos.removeAll()
    }

    // MARK: - Start from config

    func startFromConfig(_ fileConfig: AgentConfigFile) {
        guard let servers = fileConfig.mcpServers else { return }

        for (name, config) in servers {
            do {
                try startServer(name: name, config: config)
            } catch {
                printColored("  ✗ Failed to start MCP server '\(name)': \(error)", color: .red)
            }
        }
    }

    // MARK: - Tool Execution

    /// Interrupt all active MCP calls (called on Ctrl+C cancel)
    func interruptActiveCalls() {
        for (_, client) in clients {
            client.interrupted = true
        }
    }

    func canHandle(toolName: String) -> Bool {
        allTools[toolName] != nil
    }

    func executeTool(qualifiedName: String, arguments: [String: Any]) -> ToolResult {
        guard let (client, originalName) = allTools[qualifiedName] else {
            return ToolResult(success: false, output: "MCP tool '\(qualifiedName)' not found", screenshot: nil)
        }

        // Auto-restart if server died
        if !client.isRunning {
            printColored("  ⚠ MCP server '\(client.serverName)' died, restarting...", color: .yellow)
            stopServer(name: client.serverName)
            do {
                try startServer(name: client.serverName, config: client.config)
            } catch {
                return ToolResult(success: false, output: "MCP server '\(client.serverName)' crashed and failed to restart: \(error)", screenshot: nil)
            }
            // Re-lookup after restart
            guard let (newClient, newName) = allTools[qualifiedName] else {
                return ToolResult(success: false, output: "MCP tool '\(qualifiedName)' not available after restart", screenshot: nil)
            }
            return executeToolCall(client: newClient, toolName: newName, qualifiedName: qualifiedName, arguments: arguments)
        }

        return executeToolCall(client: client, toolName: originalName, qualifiedName: qualifiedName, arguments: arguments)
    }

    private func executeToolCall(client: MCPClient, toolName: String, qualifiedName: String, arguments: [String: Any]) -> ToolResult {
        // Coerce argument types to match the tool's input schema.
        let coercedArgs = coerceArguments(arguments, forTool: qualifiedName)

        do {
            let result = try client.callTool(name: toolName, arguments: coercedArgs)
            return ToolResult(success: true, output: result, screenshot: nil)
        } catch MCPError.timeout {
            let currentTimeout = Int(client.config.timeout.map { TimeInterval($0) } ?? (Self.isBrowserServer(name: client.serverName, config: client.config) ? 120 : 30))
            return ToolResult(success: false, output: "MCP request timed out after \(currentTimeout)s. The server '\(client.serverName)' took too long to respond. You can increase the timeout by adding \"timeout\": \(currentTimeout * 2) to the server config in ~/.desktop-agent/config.json", screenshot: nil)
        } catch {
            return ToolResult(success: false, output: "MCP error: \(error)", screenshot: nil)
        }
    }

    /// Coerce argument values to match the MCP tool's declared schema types.
    /// Handles common AI model mismatches like sending Int 0/1 for boolean parameters.
    private func coerceArguments(_ arguments: [String: Any], forTool qualifiedName: String) -> [String: Any] {
        guard let toolInfo = toolInfos.first(where: { $0.qualifiedName == qualifiedName }),
              let properties = toolInfo.inputSchema["properties"] as? [String: Any] else {
            return arguments
        }

        var result = arguments
        for (key, value) in arguments {
            guard let propSchema = properties[key] as? [String: Any],
                  let expectedType = propSchema["type"] as? String else {
                continue
            }

            switch expectedType {
            case "boolean":
                // Coerce Int/Double 0/1 to Bool
                if let intVal = value as? Int {
                    result[key] = intVal != 0
                } else if let doubleVal = value as? Double {
                    result[key] = doubleVal != 0
                } else if let strVal = value as? String {
                    switch strVal.lowercased() {
                    case "true", "1", "yes": result[key] = true
                    case "false", "0", "no": result[key] = false
                    default: break
                    }
                }
            case "integer":
                if let boolVal = value as? Bool {
                    result[key] = boolVal ? 1 : 0
                } else if let doubleVal = value as? Double {
                    result[key] = Int(doubleVal)
                } else if let strVal = value as? String, let intVal = Int(strVal) {
                    result[key] = intVal
                }
            case "number":
                if let boolVal = value as? Bool {
                    result[key] = boolVal ? 1.0 : 0.0
                } else if let intVal = value as? Int {
                    result[key] = Double(intVal)
                } else if let strVal = value as? String, let dblVal = Double(strVal) {
                    result[key] = dblVal
                }
            case "string":
                if !(value is String) {
                    result[key] = "\(value)"
                }
            default:
                break
            }
        }
        return result
    }

    // MARK: - Get Claude tools for all MCP servers

    func getClaudeTools() -> [ClaudeTool] {
        toolInfos.map { $0.toClaudeTool() }
    }

    // MARK: - Install MCP server

    static func installServer(name: String, packageName: String, args: [String] = [], env: [String: String] = [:]) throws -> MCPServerConfig {
        // Determine if it's an npm package or a binary
        let isNpm = packageName.contains("/") || packageName.hasPrefix("@")

        let config: MCPServerConfig
        if isNpm {
            config = MCPServerConfig(
                command: "npx",
                args: ["-y", packageName] + args,
                env: env.isEmpty ? nil : env,
                description: "MCP server: \(name)",
                timeout: nil
            )
        } else {
            config = MCPServerConfig(
                command: packageName,
                args: args.isEmpty ? nil : args,
                env: env.isEmpty ? nil : env,
                description: "MCP server: \(name)",
                timeout: nil
            )
        }

        // Save to config file
        var fileConfig = AgentConfigFile.load()
        if fileConfig.mcpServers == nil {
            fileConfig.mcpServers = [:]
        }
        fileConfig.mcpServers?[name] = config
        try fileConfig.save()

        return config
    }

    static func removeServer(name: String) throws {
        var fileConfig = AgentConfigFile.load()
        fileConfig.mcpServers?.removeValue(forKey: name)
        try fileConfig.save()
    }

    static func listConfiguredServers() -> [(name: String, config: MCPServerConfig)] {
        let fileConfig = AgentConfigFile.load()
        return (fileConfig.mcpServers ?? [:]).map { ($0.key, $0.value) }
            .sorted { $0.name < $1.name }
    }

    /// Detect if this MCP server is a browser automation tool (needs longer timeouts)
    private static func isBrowserServer(name: String, config: MCPServerConfig) -> Bool {
        let indicators = ["chrome", "browser", "playwright", "puppeteer", "selenium", "web"]
        let nameLower = name.lowercased()
        let commandLower = config.command.lowercased()
        let argsJoined = (config.args ?? []).joined(separator: " ").lowercased()
        return indicators.contains { nameLower.contains($0) || commandLower.contains($0) || argsJoined.contains($0) }
    }
}
