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
                description: "Read the agent's program.md — the high-level instructions that guide your behavior. This file can be edited by you or the user to change how you operate.",
                inputSchema: InputSchema(type: "object", properties: [:], required: nil)
            ),
            ClaudeTool(
                name: "edit_program",
                description: "Modify the agent's program.md to change behavioral guidelines. Use this to improve how you work based on user feedback or self-reflection. Changes take effect on next interaction.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "content": PropertySchema(type: "string", description: "The new program.md content (markdown format)", enumValues: nil)
                    ],
                    required: ["content"]
                )
            ),
            ClaudeTool(
                name: "read_system_prompt",
                description: "Read your current custom system prompt override. Returns empty if using the default system prompt.",
                inputSchema: InputSchema(type: "object", properties: [:], required: nil)
            ),
            ClaudeTool(
                name: "edit_system_prompt",
                description: "Modify your system prompt to change how you fundamentally operate. WARNING: Use carefully — a broken system prompt can impair your functionality. Changes take effect on next conversation.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "content": PropertySchema(type: "string", description: "The new system prompt (empty string to reset to default)", enumValues: nil)
                    ],
                    required: ["content"]
                )
            ),
            ClaudeTool(
                name: "log_improvement",
                description: "Log an improvement attempt to the improvements.log for tracking what changes work and what doesn't.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "description": PropertySchema(type: "string", description: "Short description of the improvement", enumValues: nil),
                        "success": PropertySchema(type: "boolean", description: "Whether the improvement was successful", enumValues: nil),
                        "details": PropertySchema(type: "string", description: "Details about what changed and the outcome", enumValues: nil)
                    ],
                    required: ["description", "success", "details"]
                )
            ),
            ClaudeTool(
                name: "read_improvement_log",
                description: "Read the history of improvement attempts to understand what has worked and what hasn't.",
                inputSchema: InputSchema(type: "object", properties: [:], required: nil)
            ),
            ClaudeTool(
                name: "modify_config",
                description: "Modify agent configuration (max tokens, screenshot width, active model). For API keys, user must use /config set-key.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "max_tokens": PropertySchema(type: "integer", description: "Max tokens per response (1024-32768)", enumValues: nil),
                        "max_screenshot_width": PropertySchema(type: "integer", description: "Max screenshot width in pixels (640-2560)", enumValues: nil),
                        "active_model": PropertySchema(type: "string", description: "Active model in provider/model format (e.g. anthropic/claude-sonnet-4-20250514)", enumValues: nil)
                    ],
                    required: nil
                )
            ),
            ClaudeTool(
                name: "create_plugin",
                description: "Create or update a specialized plugin that extends your capabilities. Plugins have their own system prompt and can use different models.",
                inputSchema: InputSchema(
                    type: "object",
                    properties: [
                        "name": PropertySchema(type: "string", description: "Plugin name (lowercase, hyphens ok)", enumValues: nil),
                        "description": PropertySchema(type: "string", description: "Short description of what the plugin does", enumValues: nil),
                        "system_prompt": PropertySchema(type: "string", description: "The plugin's system prompt defining its behavior", enumValues: nil),
                        "model": PropertySchema(type: "string", description: "Optional: specific model for this plugin (provider/model format)", enumValues: nil)
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
            var changes: [String] = []

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
                if AIProvider.resolve(modelString: model) != nil {
                    fileConfig.activeModel = model
                    changes.append("active_model: \(model)")
                } else {
                    return ToolResult(success: false, output: "Unknown model: \(model)", screenshot: nil)
                }
            }

            if changes.isEmpty {
                return ToolResult(success: false, output: "No valid changes specified", screenshot: nil)
            }

            do {
                try fileConfig.save()
                return ToolResult(success: true, output: "Config updated: \(changes.joined(separator: ", ")). Restart for changes to take effect.", screenshot: nil)
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
