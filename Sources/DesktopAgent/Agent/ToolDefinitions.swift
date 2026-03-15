import Foundation

// MARK: - Tool Category for Dynamic Loading

enum ToolCategory: String, CaseIterable {
    case core           // always loaded: take_screenshot, click_element, type_text, press_key, run_shell, read_file, write_file
    case gui            // get_ui_elements, scroll, drag, mouse_move, wait, list_windows, move_window, resize_window, get_screen_size
    case web            // open_url (MCP chrome tools handled separately)
    case email          // send_email
    case scheduling     // schedule_task, list_tasks, cancel_task, run_task
    case gateway        // configure_gateway, import_gateway_config
    case memory         // save_memory, read_memory
    case config         // read_program, edit_program, read_system_prompt, edit_system_prompt, log_improvement, read_improvement_log, modify_config
    case plugin         // create_plugin
    case mcp            // mcp_search, mcp_install
    case orchestrator   // run_subagents, orchestrator_stats, orchestrator_insights, clear_tool_cache
    case applescript    // run_applescript
    case adaptive       // adaptive_stats, ui_cache_lookup, clear_ui_cache
    case claudeCode     // claude_code
    case apps           // list_apps, get_frontmost_app, activate_app, open_app, spotlight_search
    case files          // list_directory, file_info, read_clipboard, write_clipboard
}

// MARK: - Tool Definitions for Claude

struct ToolDefinitions {

    // MARK: - Tool Category Map

    /// Maps each tool name to its category
    static let toolCategoryMap: [String: ToolCategory] = {
        var map: [String: ToolCategory] = [:]

        // Core (always loaded)
        for name in ["take_screenshot", "click_element", "type_text", "press_key", "run_shell", "read_file", "write_file"] {
            map[name] = .core
        }

        // GUI
        for name in ["get_ui_elements", "scroll", "drag", "mouse_move", "wait", "list_windows", "move_window", "resize_window", "get_screen_size"] {
            map[name] = .gui
        }

        // Web
        map["open_url"] = .web

        // Email
        map["send_email"] = .email

        // Scheduling
        for name in ["schedule_task", "list_tasks", "cancel_task", "run_task"] {
            map[name] = .scheduling
        }

        // Gateway
        for name in ["configure_gateway", "import_gateway_config"] {
            map[name] = .gateway
        }

        // Memory
        for name in ["save_memory", "read_memory"] {
            map[name] = .memory
        }

        // Config / Self-modification
        for name in ["read_program", "edit_program", "read_system_prompt", "edit_system_prompt", "log_improvement", "read_improvement_log", "modify_config"] {
            map[name] = .config
        }

        // Plugin
        map["create_plugin"] = .plugin

        // MCP management
        for name in ["mcp_search", "mcp_install"] {
            map[name] = .mcp
        }

        // Orchestrator
        for name in ["run_subagents", "orchestrator_stats", "orchestrator_insights", "clear_tool_cache"] {
            map[name] = .orchestrator
        }

        // AppleScript
        map["run_applescript"] = .applescript

        // Adaptive
        for name in ["adaptive_stats", "ui_cache_lookup", "clear_ui_cache"] {
            map[name] = .adaptive
        }

        // Claude Code
        map["claude_code"] = .claudeCode

        // Apps
        for name in ["list_apps", "get_frontmost_app", "activate_app", "open_app", "spotlight_search"] {
            map[name] = .apps
        }

        // Files
        for name in ["list_directory", "file_info", "read_clipboard", "write_clipboard"] {
            map[name] = .files
        }

        return map
    }()

    // MARK: - Dynamic Tool Loading

    /// Returns tools filtered by the requested categories. Always includes .core.
    static func tools(for categories: Set<ToolCategory>) -> [ClaudeTool] {
        var cats = categories
        cats.insert(.core) // always include core

        return allTools.filter { tool in
            guard let category = toolCategoryMap[tool.name] else {
                // Unknown tool — include it to be safe
                return true
            }
            return cats.contains(category)
        }
    }

    /// The discover_tools meta-tool definition
    static let discoverToolsTool = ClaudeTool(
        name: "discover_tools",
        description: "Search for additional tools not currently loaded. Returns matching tools available in your next response.",
        inputSchema: InputSchema(
            type: "object",
            properties: [
                "query": PropertySchema(type: "string", description: "Capability needed", enumValues: nil)
            ],
            required: ["query"]
        )
    )

    static let mcpManagementTools: [ClaudeTool] = [
        ClaudeTool(
            name: "mcp_search",
            description: "Search npm registry for MCP server packages to add capabilities.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "query": PropertySchema(type: "string", description: "Search keywords", enumValues: nil)
                ],
                required: ["query"]
            )
        ),
        ClaudeTool(
            name: "mcp_install",
            description: "Install and start an MCP server, making its tools available immediately.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "package": PropertySchema(type: "string", description: "npm package name", enumValues: nil),
                    "name": PropertySchema(type: "string", description: "Short server name", enumValues: nil),
                    "args": PropertySchema(type: "string", description: "Additional arguments (space-separated)", enumValues: nil)
                ],
                required: ["package"]
            )
        ),
    ]


    static let schedulerTools: [ClaudeTool] = [
        ClaudeTool(
            name: "schedule_task",
            description: "Schedule a task to run osai in headless mode. Types: \"once\" (provide \"at\" as ISO 8601), \"daily\" (provide hour/minute), \"interval\" (provide minutes).",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "id": PropertySchema(type: "string", description: "Unique task ID (lowercase, hyphens)", enumValues: nil),
                    "description": PropertySchema(type: "string", description: "Human-readable description", enumValues: nil),
                    "command": PropertySchema(type: "string", description: "Prompt/instruction to execute when task runs", enumValues: nil),
                    "schedule_type": PropertySchema(type: "string", description: "Type of schedule", enumValues: ["once", "daily", "interval"]),
                    "hour": PropertySchema(type: "integer", description: "Hour (0-23) for daily schedule", enumValues: nil),
                    "minute": PropertySchema(type: "integer", description: "Minute (0-59) for daily schedule", enumValues: nil),
                    "minutes": PropertySchema(type: "integer", description: "Interval in minutes for recurring tasks", enumValues: nil),
                    "at": PropertySchema(type: "string", description: "ISO 8601 datetime for one-time tasks", enumValues: nil)
                ],
                required: ["id", "description", "command", "schedule_type"]
            )
        ),
        ClaudeTool(
            name: "list_tasks",
            description: "List all scheduled tasks with status and last run time.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "cancel_task",
            description: "Cancel a scheduled task by ID.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "id": PropertySchema(type: "string", description: "Task ID to cancel", enumValues: nil)
                ],
                required: ["id"]
            )
        ),
        ClaudeTool(
            name: "run_task",
            description: "Trigger a scheduled task to run immediately.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "task_id": PropertySchema(type: "string", description: "ID of the task to run", enumValues: nil)
                ],
                required: ["task_id"]
            )
        ),
    ]

    static let gatewayTools: [ClaudeTool] = [
        ClaudeTool(
            name: "configure_gateway",
            description: "Configure a messaging gateway (Telegram, WhatsApp, Slack, Discord). Run `osai gateway` to start after configuring.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "platform": PropertySchema(type: "string", description: "Platform to configure", enumValues: ["telegram", "whatsapp", "slack", "discord"]),
                    "enabled": PropertySchema(type: "string", description: "Enable or disable", enumValues: ["true", "false"]),
                    "bot_token": PropertySchema(type: "string", description: "Bot token (Telegram, Slack, Discord)", enumValues: nil),
                    "app_token": PropertySchema(type: "string", description: "App-level token (Slack Socket Mode)", enumValues: nil),
                    "allowed_users": PropertySchema(type: "string", description: "Comma-separated allowed user IDs", enumValues: nil),
                ],
                required: ["platform", "enabled"]
            )
        ),
        ClaudeTool(
            name: "import_gateway_config",
            description: "Import gateway config from OpenClaw (~/.openclaw/openclaw.json).",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "platform": PropertySchema(type: "string", description: "Platform to import, or 'all'", enumValues: ["discord", "telegram", "slack", "whatsapp", "all"]),
                ],
                required: ["platform"]
            )
        ),
    ]

    static let claudeCodeTools: [ClaudeTool] = [
        ClaudeTool(
            name: "claude_code",
            description: "Delegate a programming task to Claude Code CLI. Use for all code changes, debugging, refactoring, and engineering tasks.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "prompt": PropertySchema(type: "string", description: "Detailed prompt describing the programming task", enumValues: nil),
                    "workdir": PropertySchema(type: "string", description: "Working directory (default: ~/Sites/osai)", enumValues: nil),
                ],
                required: ["prompt"]
            )
        ),
    ]

    static let orchestratorTools: [ClaudeTool] = [
        ClaudeTool(
            name: "orchestrator_stats",
            description: "View tool orchestrator stats: cache hit rates, prediction accuracy, batching efficiency.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
        ClaudeTool(
            name: "orchestrator_insights",
            description: "Get insights on tool usage patterns: common sequences, slowest tools, batching opportunities.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
        ClaudeTool(
            name: "clear_tool_cache",
            description: "Clear the tool result cache.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
    ]

    static let adaptiveTools: [ClaudeTool] = [
        ClaudeTool(
            name: "adaptive_stats",
            description: "View adaptive response system stats: context detection, UI cache, intent analysis.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
        ClaudeTool(
            name: "ui_cache_lookup",
            description: "Look up cached UI element positions and workflows for an app.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "Application name to look up", enumValues: nil)
                ],
                required: ["app_name"]
            )
        ),
        ClaudeTool(
            name: "clear_ui_cache",
            description: "Clear UI intelligence cache for all or a specific app.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "App name to clear cache for (omit to clear all)", enumValues: nil)
                ],
                required: nil
            )
        ),
    ]

    static let allTools: [ClaudeTool] = SelfModificationTools.tools + mcpManagementTools + schedulerTools + gatewayTools + claudeCodeTools + orchestratorTools + adaptiveTools + [
        // --- AppleScript ---
        ClaudeTool(
            name: "run_applescript",
            description: "Execute AppleScript to control macOS applications and System Events.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "script": PropertySchema(type: "string", description: "AppleScript code to execute", enumValues: nil)
                ],
                required: ["script"]
            )
        ),

        // --- Shell ---
        ClaudeTool(
            name: "run_shell",
            description: "Execute a zsh command and return output. Use for file ops, process management, system info, scripts.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "command": PropertySchema(type: "string", description: "Shell command to execute", enumValues: nil),
                    "timeout": PropertySchema(type: "integer", description: "Max seconds to wait (default: 30, max: 120)", enumValues: nil)
                ],
                required: ["command"]
            )
        ),

        // --- Spotlight ---
        ClaudeTool(
            name: "spotlight_search",
            description: "Search for files, apps, or folders using macOS Spotlight.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "query": PropertySchema(type: "string", description: "Search query", enumValues: nil),
                    "kind": PropertySchema(type: "string", description: "Filter by type", enumValues: ["application", "document", "folder", "image", "any"])
                ],
                required: ["query"]
            )
        ),

        // --- App Management ---
        ClaudeTool(
            name: "list_apps",
            description: "List running applications with names, PIDs, and bundle IDs.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "get_frontmost_app",
            description: "Get the currently active (frontmost) application.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "activate_app",
            description: "Bring an application to the foreground.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "name": PropertySchema(type: "string", description: "Application name", enumValues: nil)
                ],
                required: ["name"]
            )
        ),
        ClaudeTool(
            name: "open_app",
            description: "Launch and activate an application by name.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "name": PropertySchema(type: "string", description: "Application name", enumValues: nil)
                ],
                required: ["name"]
            )
        ),

        // --- UI Inspection ---
        ClaudeTool(
            name: "get_ui_elements",
            description: "Get accessibility tree of an app: buttons, fields, labels with positions and center coordinates.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "Application name or PID", enumValues: nil),
                    "max_depth": PropertySchema(type: "integer", description: "Max UI tree depth (default: 3, max: 5)", enumValues: nil)
                ],
                required: ["app_name"]
            )
        ),

        // --- Mouse ---
        ClaudeTool(
            name: "click_element",
            description: "Click at screen coordinates. Use get_ui_elements first to find coordinates.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "x": PropertySchema(type: "integer", description: "X coordinate", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y coordinate", enumValues: nil),
                    "button": PropertySchema(type: "string", description: "Mouse button (default: left)", enumValues: ["left", "right"]),
                    "double_click": PropertySchema(type: "boolean", description: "Double-click (default: false)", enumValues: nil)
                ],
                required: ["x", "y"]
            )
        ),
        ClaudeTool(
            name: "mouse_move",
            description: "Move mouse cursor to a position without clicking.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "x": PropertySchema(type: "integer", description: "X coordinate", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y coordinate", enumValues: nil)
                ],
                required: ["x", "y"]
            )
        ),
        ClaudeTool(
            name: "scroll",
            description: "Scroll at a specific screen position.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "x": PropertySchema(type: "integer", description: "X coordinate", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y coordinate", enumValues: nil),
                    "direction": PropertySchema(type: "string", description: "Scroll direction", enumValues: ["up", "down", "left", "right"]),
                    "amount": PropertySchema(type: "integer", description: "Scroll ticks (default: 3)", enumValues: nil)
                ],
                required: ["x", "y", "direction"]
            )
        ),
        ClaudeTool(
            name: "drag",
            description: "Click and drag from one position to another.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "from_x": PropertySchema(type: "integer", description: "Starting X", enumValues: nil),
                    "from_y": PropertySchema(type: "integer", description: "Starting Y", enumValues: nil),
                    "to_x": PropertySchema(type: "integer", description: "Ending X", enumValues: nil),
                    "to_y": PropertySchema(type: "integer", description: "Ending Y", enumValues: nil),
                    "duration": PropertySchema(type: "number", description: "Drag duration in seconds (default: 0.5)", enumValues: nil)
                ],
                required: ["from_x", "from_y", "to_x", "to_y"]
            )
        ),

        // --- Keyboard ---
        ClaudeTool(
            name: "type_text",
            description: "Type text character by character into the focused element.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "text": PropertySchema(type: "string", description: "Text to type", enumValues: nil)
                ],
                required: ["text"]
            )
        ),
        ClaudeTool(
            name: "press_key",
            description: "Press a key or shortcut. Combine modifiers with '+' (e.g. 'command+c', 'return').",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "key": PropertySchema(type: "string", description: "Key combination", enumValues: nil)
                ],
                required: ["key"]
            )
        ),

        // --- Vision ---
        ClaudeTool(
            name: "take_screenshot",
            description: "Capture screenshot of the screen or a region. Downscaled to 1280px wide.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "x": PropertySchema(type: "integer", description: "Region X (omit for full screen)", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Region Y", enumValues: nil),
                    "width": PropertySchema(type: "integer", description: "Region width", enumValues: nil),
                    "height": PropertySchema(type: "integer", description: "Region height", enumValues: nil)
                ],
                required: nil
            )
        ),

        // --- Window Management ---
        ClaudeTool(
            name: "list_windows",
            description: "List visible windows with owner app, title, position, and size.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "Filter by app name (optional)", enumValues: nil)
                ],
                required: nil
            )
        ),
        ClaudeTool(
            name: "move_window",
            description: "Move an app's window to a new position.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "Application name", enumValues: nil),
                    "x": PropertySchema(type: "integer", description: "New X position", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "New Y position", enumValues: nil)
                ],
                required: ["app_name", "x", "y"]
            )
        ),
        ClaudeTool(
            name: "resize_window",
            description: "Resize an app's window.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "Application name", enumValues: nil),
                    "width": PropertySchema(type: "integer", description: "New width", enumValues: nil),
                    "height": PropertySchema(type: "integer", description: "New height", enumValues: nil)
                ],
                required: ["app_name", "width", "height"]
            )
        ),

        // --- Utilities ---
        ClaudeTool(
            name: "open_url",
            description: "Open a URL in the default browser.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "url": PropertySchema(type: "string", description: "URL to open", enumValues: nil)
                ],
                required: ["url"]
            )
        ),
        ClaudeTool(
            name: "read_clipboard",
            description: "Read current clipboard contents.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "write_clipboard",
            description: "Write text to the clipboard.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "text": PropertySchema(type: "string", description: "Text to copy to clipboard", enumValues: nil)
                ],
                required: ["text"]
            )
        ),
        ClaudeTool(
            name: "get_screen_size",
            description: "Get screen dimensions in pixels.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "wait",
            description: "Pause for a duration to let UI update.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "seconds": PropertySchema(type: "number", description: "Seconds to wait (0.1 to 10)", enumValues: nil)
                ],
                required: ["seconds"]
            )
        ),

        // --- File Operations ---
        ClaudeTool(
            name: "read_file",
            description: "Read a file's contents (up to 500 lines).",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "path": PropertySchema(type: "string", description: "File path (supports ~)", enumValues: nil),
                    "max_lines": PropertySchema(type: "integer", description: "Max lines to read (default: 500)", enumValues: nil)
                ],
                required: ["path"]
            )
        ),
        ClaudeTool(
            name: "write_file",
            description: "Write content to a file. Creates or overwrites.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "path": PropertySchema(type: "string", description: "File path", enumValues: nil),
                    "content": PropertySchema(type: "string", description: "Content to write", enumValues: nil)
                ],
                required: ["path", "content"]
            )
        ),
        ClaudeTool(
            name: "list_directory",
            description: "List files and folders in a directory.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "path": PropertySchema(type: "string", description: "Directory path (supports ~)", enumValues: nil),
                    "recursive": PropertySchema(type: "boolean", description: "List recursively (default: false)", enumValues: nil)
                ],
                required: ["path"]
            )
        ),
        ClaudeTool(
            name: "file_info",
            description: "Get file metadata: size, dates, type, line count.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "path": PropertySchema(type: "string", description: "File path", enumValues: nil)
                ],
                required: ["path"]
            )
        ),

        // --- Memory ---
        ClaudeTool(
            name: "save_memory",
            description: "Save information to persistent memory across sessions.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "topic": PropertySchema(type: "string", description: "Topic/filename for the memory", enumValues: nil),
                    "content": PropertySchema(type: "string", description: "Content to save (markdown)", enumValues: nil),
                    "append": PropertySchema(type: "boolean", description: "Append instead of overwrite (default: false)", enumValues: nil)
                ],
                required: ["topic", "content"]
            )
        ),
        ClaudeTool(
            name: "read_memory",
            description: "Read from persistent memory. Omit topic to list all files.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "topic": PropertySchema(type: "string", description: "Topic to read (omit for list)", enumValues: nil)
                ],
                required: nil
            )
        ),

        // --- Sub-Agents ---
        ClaudeTool(
            name: "run_subagents",
            description: "Run multiple sub-tasks in parallel via separate AI agents. Types: general (full access), explore (read-only research), analyze (deep analysis), execute (action-oriented, no sub-agents).",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "tasks": PropertySchema(type: "string", description: "JSON array of tasks: [{id, description, prompt, type}]", enumValues: nil),
                    "context": PropertySchema(type: "string", description: "Shared context for all sub-agents", enumValues: nil)
                ],
                required: ["tasks"]
            )
        ),

        // --- Email (via gws CLI) ---
        ClaudeTool(
            name: "send_email",
            description: "Send an email with to, subject, and body.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "to": PropertySchema(type: "string", description: "Recipient email", enumValues: nil),
                    "subject": PropertySchema(type: "string", description: "Subject line", enumValues: nil),
                    "body": PropertySchema(type: "string", description: "Body text (plain text)", enumValues: nil)
                ],
                required: ["to", "subject", "body"]
            )
        ),
    ]
}
