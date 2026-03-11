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
        let client = MCPClient(serverName: name, config: config)
        try client.start()
        clients[name] = client

        // Discover tools
        let tools = try client.listTools()
        for tool in tools {
            allTools[tool.qualifiedName] = (client, tool.name)
            toolInfos.append(tool)
        }

        printColored("  ✓ \(name): \(tools.count) tools loaded", color: .green)
        for tool in tools {
            printColored("    • \(tool.qualifiedName): \(tool.description.prefix(80))", color: .gray)
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

    func canHandle(toolName: String) -> Bool {
        allTools[toolName] != nil
    }

    func executeTool(qualifiedName: String, arguments: [String: Any]) -> ToolResult {
        guard let (client, originalName) = allTools[qualifiedName] else {
            return ToolResult(success: false, output: "MCP tool '\(qualifiedName)' not found", screenshot: nil)
        }

        do {
            let result = try client.callTool(name: originalName, arguments: arguments)
            return ToolResult(success: true, output: result, screenshot: nil)
        } catch {
            return ToolResult(success: false, output: "MCP error: \(error)", screenshot: nil)
        }
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
                description: "MCP server: \(name)"
            )
        } else {
            config = MCPServerConfig(
                command: packageName,
                args: args.isEmpty ? nil : args,
                env: env.isEmpty ? nil : env,
                description: "MCP server: \(name)"
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
}
