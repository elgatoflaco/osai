import Foundation

// MARK: - Self-Improvement System
// Inspired by Karpathy's autoresearch: constrained self-modification with metric-driven decisions

/// The agent's editable program — like autoresearch's program.md
/// Defines high-level objectives and behavioral guidelines
struct AgentProgram {
    static let programDir = NSHomeDirectory() + "/.desktop-agent"
    static let programPath = programDir + "/program.md"
    static let systemPromptPath = programDir + "/system-prompt.md"
    static let improvementLogPath = programDir + "/improvements.log"

    /// Load the program.md (user/agent-editable instructions)
    static func load() -> String? {
        try? String(contentsOfFile: programPath, encoding: .utf8)
    }

    /// Save the program
    static func save(_ content: String) throws {
        try FileManager.default.createDirectory(atPath: programDir, withIntermediateDirectories: true)
        try content.write(toFile: programPath, atomically: true, encoding: .utf8)
    }

    /// Load custom system prompt override (nil = use default)
    static func loadCustomSystemPrompt() -> String? {
        guard let content = try? String(contentsOfFile: systemPromptPath, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }

    /// Save custom system prompt
    static func saveCustomSystemPrompt(_ content: String) throws {
        try FileManager.default.createDirectory(atPath: programDir, withIntermediateDirectories: true)
        try content.write(toFile: systemPromptPath, atomically: true, encoding: .utf8)
    }

    /// Install default program.md if it doesn't exist
    static func installDefault() {
        guard !FileManager.default.fileExists(atPath: programPath) else { return }
        let defaultProgram = """
        # Desktop Agent Program

        ## Objectives
        - Help the user efficiently with macOS desktop automation
        - Choose the right tool for each task (shell for files, GUI for visual tasks)
        - Be concise and action-oriented
        - Learn from interactions and improve over time

        ## Preferences
        - Prefer shell commands over screenshots for non-visual tasks
        - Use sub-agents for parallel file analysis
        - Save important discoveries to memory
        - Explain actions before executing them

        ## Constraints
        - Never run destructive commands without confirmation
        - Never type passwords or credentials
        - Ask before modifying system settings
        - Keep responses focused and brief

        ## Self-Improvement
        - When you notice a pattern that could be improved, suggest it
        - Track what works well and what doesn't in memory
        - Adapt your approach based on user feedback
        """
        try? save(defaultProgram)
    }

    /// Log an improvement attempt
    static func logImprovement(description: String, success: Bool, details: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let icon = success ? "✓" : "✗"
        let entry = "\n[\(timestamp)] \(icon) \(description)\n  \(details)\n"
        if let existing = try? String(contentsOfFile: improvementLogPath, encoding: .utf8) {
            try? (existing + entry).write(toFile: improvementLogPath, atomically: true, encoding: .utf8)
        } else {
            try? ("# Improvement Log\n" + entry).write(toFile: improvementLogPath, atomically: true, encoding: .utf8)
        }
    }

    /// Read improvement history
    static func readImprovementLog() -> String? {
        try? String(contentsOfFile: improvementLogPath, encoding: .utf8)
    }
}

// MARK: - Self-Modification Tools

/// Tools the agent can use to modify its own behavior
struct SelfModificationTools {

    /// Get all self-modification tool definitions
    static var tools: [ClaudeTool] {
        return [
            ClaudeTool(
                name: "read_program",
                description: "Read the agent's program.md behavioral guidelines.",
                inputSchema: InputSchema(type: "object", properties: [:], required: nil)
            ),
            ClaudeTool(
                name: "edit_program",
                description: "Modify the agent's program.md behavioral guidelines. Changes take effect next interaction.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "content": PropertySchema(type: "string", description: "New program.md content (markdown)", enumValues: nil)
                    ],
                    required: ["content"]
                )
            ),
            ClaudeTool(
                name: "read_system_prompt",
                description: "Read current custom system prompt override.",
                inputSchema: InputSchema(type: "object", properties: [:], required: nil)
            ),
            ClaudeTool(
                name: "edit_system_prompt",
                description: "Modify system prompt override. Changes take effect next conversation.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "content": PropertySchema(type: "string", description: "New system prompt (empty to reset)", enumValues: nil)
                    ],
                    required: ["content"]
                )
            ),
            ClaudeTool(
                name: "log_improvement",
                description: "Log an improvement attempt to improvements.log.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "description": PropertySchema(type: "string", description: "Short description", enumValues: nil),
                        "success": PropertySchema(type: "boolean", description: "Whether it was successful", enumValues: nil),
                        "details": PropertySchema(type: "string", description: "What changed and the outcome", enumValues: nil)
                    ],
                    required: ["description", "success", "details"]
                )
            ),
            ClaudeTool(
                name: "read_improvement_log",
                description: "Read the improvement attempt history.",
                inputSchema: InputSchema(type: "object", properties: [:], required: nil)
            ),
            ClaudeTool(
                name: "modify_config",
                description: "Modify agent configuration. Can change: active model, max tokens, API keys, MCP servers, spending limits. Use `action` to specify the operation.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "action": PropertySchema(type: "string", description: "Operation: set_model, set_max_tokens, set_api_key, remove_api_key, add_mcp_server, remove_mcp_server, set_spending_limits, show_config", enumValues: nil),
                        "active_model": PropertySchema(type: "string", description: "Model in provider/model format (e.g. anthropic/claude-haiku-4-5-20251001)", enumValues: nil),
                        "max_tokens": PropertySchema(type: "integer", description: "Max tokens per response (1024-32768)", enumValues: nil),
                        "max_screenshot_width": PropertySchema(type: "integer", description: "Max screenshot width in pixels (640-2560)", enumValues: nil),
                        "provider": PropertySchema(type: "string", description: "Provider name for API key operations (anthropic, openai, openrouter, google, etc.)", enumValues: nil),
                        "api_key": PropertySchema(type: "string", description: "API key value", enumValues: nil),
                        "server_name": PropertySchema(type: "string", description: "MCP server name for add/remove operations", enumValues: nil),
                        "server_command": PropertySchema(type: "string", description: "Command for MCP server (e.g. npx)", enumValues: nil),
                        "server_args": PropertySchema(type: "string", description: "Comma-separated args for MCP server", enumValues: nil),
                        "daily_usd": PropertySchema(type: "number", description: "Daily spending limit in USD", enumValues: nil),
                        "monthly_usd": PropertySchema(type: "number", description: "Monthly spending limit in USD", enumValues: nil)
                    ],
                    required: nil
                )
            ),
            ClaudeTool(
                name: "create_plugin",
                description: "Create or update a plugin with its own system prompt and optional model.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "name": PropertySchema(type: "string", description: "Plugin name (lowercase, hyphens ok)", enumValues: nil),
                        "description": PropertySchema(type: "string", description: "Short plugin description", enumValues: nil),
                        "system_prompt": PropertySchema(type: "string", description: "Plugin system prompt", enumValues: nil),
                        "model": PropertySchema(type: "string", description: "Specific model (provider/model format)", enumValues: nil)
                    ],
                    required: ["name", "description", "system_prompt"]
                )
            ),
        ]
    }

    /// Execute a self-modification tool
    static func execute(toolName: String, input: [String: AnyCodable]) -> ToolResult {
        switch toolName {

        case "read_program":
            if let content = AgentProgram.load() {
                return ToolResult(success: true, output: content, screenshot: nil)
            }
            return ToolResult(success: true, output: "(No program.md found — using defaults)", screenshot: nil)

        case "edit_program":
            let content = input["content"]?.stringValue ?? ""
            do {
                // Backup current version
                if let existing = AgentProgram.load() {
                    let backupPath = AgentProgram.programDir + "/program.md.bak"
                    try existing.write(toFile: backupPath, atomically: true, encoding: .utf8)
                }
                try AgentProgram.save(content)
                return ToolResult(success: true, output: "Program updated. Changes take effect on next interaction.", screenshot: nil)
            } catch {
                return ToolResult(success: false, output: "Error saving program: \(error)", screenshot: nil)
            }

        case "read_system_prompt":
            if let custom = AgentProgram.loadCustomSystemPrompt() {
                return ToolResult(success: true, output: custom, screenshot: nil)
            }
            return ToolResult(success: true, output: "(Using default system prompt — no custom override set)", screenshot: nil)

        case "edit_system_prompt":
            let content = input["content"]?.stringValue ?? ""
            do {
                if content.isEmpty {
                    // Reset to default
                    try? FileManager.default.removeItem(atPath: AgentProgram.systemPromptPath)
                    return ToolResult(success: true, output: "System prompt reset to default.", screenshot: nil)
                }
                // Backup current
                if let existing = AgentProgram.loadCustomSystemPrompt() {
                    let backupPath = AgentProgram.programDir + "/system-prompt.md.bak"
                    try existing.write(toFile: backupPath, atomically: true, encoding: .utf8)
                }
                try AgentProgram.saveCustomSystemPrompt(content)
                return ToolResult(success: true, output: "System prompt updated. Takes effect on next conversation.", screenshot: nil)
            } catch {
                return ToolResult(success: false, output: "Error: \(error)", screenshot: nil)
            }

        case "log_improvement":
            let desc = input["description"]?.stringValue ?? ""
            let success = input["success"]?.boolValue ?? false
            let details = input["details"]?.stringValue ?? ""
            AgentProgram.logImprovement(description: desc, success: success, details: details)
            return ToolResult(success: true, output: "Improvement logged.", screenshot: nil)

        case "read_improvement_log":
            if let log = AgentProgram.readImprovementLog() {
                return ToolResult(success: true, output: log, screenshot: nil)
            }
            return ToolResult(success: true, output: "(No improvement history yet)", screenshot: nil)

        case "modify_config":
            var fileConfig = AgentConfigFile.load()
            let action = input["action"]?.stringValue ?? ""
            var changes: [String] = []

            switch action {
            case "show_config":
                // Return sanitized config (mask API keys)
                var info: [String] = []
                info.append("activeModel: \(fileConfig.activeModel ?? "default")")
                info.append("maxTokens: \(fileConfig.maxTokens ?? 8192)")
                info.append("apiKeys: \((fileConfig.apiKeys ?? [:]).keys.sorted().joined(separator: ", "))")
                info.append("mcpServers: \((fileConfig.mcpServers ?? [:]).keys.sorted().joined(separator: ", "))")
                if let limits = fileConfig.spendingLimits {
                    info.append("spending: daily=$\(limits.dailyUsd ?? 0), monthly=$\(limits.monthlyUsd ?? 0)")
                }
                return ToolResult(success: true, output: info.joined(separator: "\n"), screenshot: nil)

            case "set_model":
                guard let model = input["active_model"]?.stringValue else {
                    return ToolResult(success: false, output: "Missing active_model parameter", screenshot: nil)
                }
                fileConfig.activeModel = model
                changes.append("active_model: \(model)")

            case "set_max_tokens":
                guard let maxTokens = input["max_tokens"]?.intValue else {
                    return ToolResult(success: false, output: "Missing max_tokens parameter", screenshot: nil)
                }
                let clamped = max(1024, min(32768, maxTokens))
                fileConfig.maxTokens = clamped
                changes.append("max_tokens: \(clamped)")

            case "set_api_key":
                guard let provider = input["provider"]?.stringValue,
                      let key = input["api_key"]?.stringValue else {
                    return ToolResult(success: false, output: "Missing provider or api_key", screenshot: nil)
                }
                let authType = key.hasPrefix("sk-ant-oat") ? "bearer" : nil
                fileConfig.setAPIKey(provider: provider, key: key, authType: authType)
                changes.append("api_key for \(provider): set")

            case "remove_api_key":
                guard let provider = input["provider"]?.stringValue else {
                    return ToolResult(success: false, output: "Missing provider", screenshot: nil)
                }
                fileConfig.removeAPIKey(provider: provider)
                changes.append("api_key for \(provider): removed")

            case "add_mcp_server":
                guard let name = input["server_name"]?.stringValue,
                      let command = input["server_command"]?.stringValue else {
                    return ToolResult(success: false, output: "Missing server_name or server_command", screenshot: nil)
                }
                let args = input["server_args"]?.stringValue?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                let config = MCPServerConfig(command: command, args: args, env: nil, description: "Added via modify_config", timeout: nil)
                if fileConfig.mcpServers == nil { fileConfig.mcpServers = [:] }
                fileConfig.mcpServers?[name] = config
                changes.append("mcp_server \(name): added")

            case "remove_mcp_server":
                guard let name = input["server_name"]?.stringValue else {
                    return ToolResult(success: false, output: "Missing server_name", screenshot: nil)
                }
                fileConfig.mcpServers?.removeValue(forKey: name)
                changes.append("mcp_server \(name): removed")

            case "set_spending_limits":
                let daily = input["daily_usd"]?.doubleValue
                let monthly = input["monthly_usd"]?.doubleValue
                if daily == nil && monthly == nil {
                    return ToolResult(success: false, output: "Specify daily_usd or monthly_usd", screenshot: nil)
                }
                var limits = fileConfig.spendingLimits ?? SpendingLimits()
                if let d = daily { limits.dailyUsd = d; changes.append("daily_usd: $\(d)") }
                if let m = monthly { limits.monthlyUsd = m; changes.append("monthly_usd: $\(m)") }
                fileConfig.spendingLimits = limits

            default:
                // Legacy: support direct params without action
                if let maxTokens = input["max_tokens"]?.intValue {
                    let clamped = max(1024, min(32768, maxTokens))
                    fileConfig.maxTokens = clamped
                    changes.append("max_tokens: \(clamped)")
                }
                if let maxWidth = input["max_screenshot_width"]?.intValue {
                    let clamped = max(640, min(2560, maxWidth))
                    fileConfig.maxScreenshotWidth = clamped
                    changes.append("max_screenshot_width: \(clamped)")
                }
                if let model = input["active_model"]?.stringValue {
                    fileConfig.activeModel = model
                    changes.append("active_model: \(model)")
                }
            }

            if changes.isEmpty {
                return ToolResult(success: false, output: "No valid changes specified. Use action: show_config to see current config.", screenshot: nil)
            }

            do {
                try fileConfig.save()
                return ToolResult(success: true, output: "Config updated: \(changes.joined(separator: ", ")). Changes take effect on next interaction.", screenshot: nil)
            } catch {
                return ToolResult(success: false, output: "Error saving config: \(error)", screenshot: nil)
            }

        case "create_plugin":
            let name = input["name"]?.stringValue ?? ""
            let desc = input["description"]?.stringValue ?? ""
            let systemPrompt = input["system_prompt"]?.stringValue ?? ""
            let model = input["model"]?.stringValue

            let plugin = AgentPlugin(
                name: name, description: desc, model: model, tools: nil,
                systemPrompt: systemPrompt, filePath: ""
            )
            do {
                try PluginManager.savePlugin(plugin)
                return ToolResult(success: true, output: "Plugin '\(name)' created at ~/.desktop-agent/plugins/\(name).md", screenshot: nil)
            } catch {
                return ToolResult(success: false, output: "Error: \(error)", screenshot: nil)
            }

        default:
            return ToolResult(success: false, output: "Unknown self-modification tool: \(toolName)", screenshot: nil)
        }
    }

    /// Check if a tool name is a self-modification tool
    static func canHandle(_ toolName: String) -> Bool {
        let selfTools: Set<String> = [
            "read_program", "edit_program", "read_system_prompt", "edit_system_prompt",
            "log_improvement", "read_improvement_log", "modify_config", "create_plugin"
        ]
        return selfTools.contains(toolName)
    }
}
