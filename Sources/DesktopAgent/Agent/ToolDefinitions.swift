import Foundation

// MARK: - Tool Definitions for Claude

struct ToolDefinitions {

    static let mcpManagementTools: [ClaudeTool] = [
        ClaudeTool(
            name: "mcp_search",
            description: "Search npm registry for MCP (Model Context Protocol) server packages. Use this when the user needs a capability you don't have — search for an MCP server that provides it, then install it with mcp_install.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "query": PropertySchema(type: "string", description: "Search keywords (e.g., 'chrome devtools', 'github', 'slack', 'database', 'filesystem')", enumValues: nil)
                ],
                required: ["query"]
            )
        ),
        ClaudeTool(
            name: "mcp_install",
            description: "Install and start an MCP server. This adds it to the agent's config and connects to it immediately. Once connected, the server's tools become available. Use npx-compatible package names.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "package": PropertySchema(type: "string", description: "npm package name (e.g., 'chrome-devtools-mcp', '@anthropic-ai/mcp-github', '@anthropic-ai/mcp-filesystem')", enumValues: nil),
                    "name": PropertySchema(type: "string", description: "Short name for this server (e.g., 'chrome', 'github', 'fs')", enumValues: nil),
                    "args": PropertySchema(type: "string", description: "Additional arguments (space-separated, e.g., '/Users/user/projects' for filesystem MCP)", enumValues: nil)
                ],
                required: ["package"]
            )
        ),
    ]


    static let schedulerTools: [ClaudeTool] = [
        ClaudeTool(
            name: "schedule_task",
            description: """
            Schedule a task to run automatically. The task runs `osai` in headless mode at the scheduled time.
            Use this when the user asks you to do something later, on a schedule, or repeatedly.
            Examples: "remind me in 5 minutes", "send me a daily briefing at 8am", "check my emails every hour".

            Schedule types:
            - "once": Run once at a specific time. Provide "at" as ISO 8601 datetime.
            - "daily": Run every day. Provide "hour" (0-23) and "minute" (0-59).
            - "interval": Run every N minutes. Provide "minutes".
            """,
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "id": PropertySchema(type: "string", description: "Unique task ID (lowercase, hyphens, e.g., 'daily-briefing', 'check-emails')", enumValues: nil),
                    "description": PropertySchema(type: "string", description: "Human-readable description", enumValues: nil),
                    "command": PropertySchema(type: "string", description: "The prompt/instruction to execute (what osai will do when the task runs)", enumValues: nil),
                    "schedule_type": PropertySchema(type: "string", description: "Type of schedule", enumValues: ["once", "daily", "interval"]),
                    "hour": PropertySchema(type: "integer", description: "Hour (0-23) for daily schedule", enumValues: nil),
                    "minute": PropertySchema(type: "integer", description: "Minute (0-59) for daily schedule", enumValues: nil),
                    "minutes": PropertySchema(type: "integer", description: "Interval in minutes for recurring tasks", enumValues: nil),
                    "at": PropertySchema(type: "string", description: "ISO 8601 datetime for one-time tasks (e.g., '2025-03-11T16:30:00')", enumValues: nil)
                ],
                required: ["id", "description", "command", "schedule_type"]
            )
        ),
        ClaudeTool(
            name: "list_tasks",
            description: "List all scheduled tasks with their status, schedule, and last run time.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "cancel_task",
            description: "Cancel and remove a scheduled task by its ID.",
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
            description: "Trigger an existing scheduled task to run immediately. Results will be delivered to the configured destination.",
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
            description: """
            Configure a messaging gateway (Telegram, WhatsApp, Slack, Discord) so the user can talk to osai from those platforms.
            Use this when the user wants to set up a bot/bridge. After configuring, tell the user to run `osai gateway` to start it.
            For Telegram: user needs a bot token from @BotFather.
            For WhatsApp: just enable it (uses wacli, must be authenticated).
            For Slack: needs bot_token (xoxb-) and app_token (xapp-).
            For Discord: needs bot token from Discord Developer Portal.
            """,
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "platform": PropertySchema(type: "string", description: "Platform to configure: telegram, whatsapp, slack, discord", enumValues: ["telegram", "whatsapp", "slack", "discord"]),
                    "enabled": PropertySchema(type: "string", description: "Enable or disable: true/false", enumValues: ["true", "false"]),
                    "bot_token": PropertySchema(type: "string", description: "Bot token (required for Telegram, Slack, Discord)", enumValues: nil),
                    "app_token": PropertySchema(type: "string", description: "App-level token (required for Slack Socket Mode)", enumValues: nil),
                    "allowed_users": PropertySchema(type: "string", description: "Comma-separated list of allowed user IDs (for whitelisting)", enumValues: nil),
                ],
                required: ["platform", "enabled"]
            )
        ),
        ClaudeTool(
            name: "import_gateway_config",
            description: """
            Import gateway/channel configuration from OpenClaw (~/.openclaw/openclaw.json).
            This reads existing Discord, Telegram, Slack, or WhatsApp configs and copies them to osai's gateway config.
            Use this when the user says they have OpenClaw configured and want to reuse those settings.
            """,
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "platform": PropertySchema(type: "string", description: "Platform to import: discord, telegram, slack, whatsapp, or 'all' to import everything", enumValues: ["discord", "telegram", "slack", "whatsapp", "all"]),
                ],
                required: ["platform"]
            )
        ),
    ]

    static let claudeCodeTools: [ClaudeTool] = [
        ClaudeTool(
            name: "claude_code",
            description: """
            Delegate a programming task to Claude Code (claude CLI). Use this for ALL code changes, file creation, \
            refactoring, debugging, and software engineering tasks. Claude Code has full access to the codebase, \
            can read/write files, run tests, and make commits. \
            You MUST use this tool instead of writing code yourself — Claude Code is the expert programmer. \
            Write a clear, professional prompt describing exactly what needs to be done. \
            Include relevant context: file paths, error messages, desired behavior. \
            Claude Code works in the project directory and has full shell access.
            """,
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "prompt": PropertySchema(type: "string", description: "A clear, detailed prompt for Claude Code describing the programming task. Be specific about what files to change, what behavior is expected, and any constraints.", enumValues: nil),
                    "workdir": PropertySchema(type: "string", description: "Working directory for Claude Code (default: ~/Sites/osai)", enumValues: nil),
                ],
                required: ["prompt"]
            )
        ),
    ]

    static let orchestratorTools: [ClaudeTool] = [
        ClaudeTool(
            name: "orchestrator_stats",
            description: "View tool orchestrator statistics: cache hit rates, prediction accuracy, common tool sequences, batching efficiency. Use this to understand your own performance patterns and identify optimization opportunities.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
        ClaudeTool(
            name: "orchestrator_insights",
            description: "Get detailed insights about tool usage patterns: most common sequences, slowest tools, batching opportunities. Use this for self-reflection on efficiency.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
        ClaudeTool(
            name: "clear_tool_cache",
            description: "Clear the tool result cache. Use when you suspect cached data is stale or after significant system state changes.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
    ]

    static let adaptiveTools: [ClaudeTool] = [
        ClaudeTool(
            name: "adaptive_stats",
            description: "View adaptive response system statistics: detected context, UI intelligence cache, intent analysis. Useful for understanding how the system adapts to your current environment.",
            inputSchema: InputSchema(type: "object", properties: [:], required: nil)
        ),
        ClaudeTool(
            name: "ui_cache_lookup",
            description: "Look up cached UI element positions and workflows for an app. Avoids the need to call get_ui_elements if the layout is cached. Returns frequently used elements and known workflows.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "Application name to look up cached UI data for", enumValues: nil)
                ],
                required: ["app_name"]
            )
        ),
        ClaudeTool(
            name: "clear_ui_cache",
            description: "Clear the UI intelligence cache for all apps or a specific app. Use when cached positions seem stale or after app updates.",
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
            description: "Execute AppleScript code to control macOS applications. Use for app-specific automation like telling Safari to open a URL, controlling Finder, managing windows, interacting with menus via System Events, etc. This is the most reliable way to interact with apps that support it.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "script": PropertySchema(type: "string", description: "The AppleScript code to execute", enumValues: nil)
                ],
                required: ["script"]
            )
        ),

        // --- Shell ---
        ClaudeTool(
            name: "run_shell",
            description: "Execute a shell command (zsh) and return the output. Use for file operations (ls, cat, cp, mv), process management (ps, kill), system info, installing packages, running scripts, or ANYTHING that can be done from a terminal. Very powerful — use it when other tools can't do the job.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "command": PropertySchema(type: "string", description: "The shell command to execute", enumValues: nil),
                    "timeout": PropertySchema(type: "integer", description: "Maximum seconds to wait (default: 30, max: 120)", enumValues: nil)
                ],
                required: ["command"]
            )
        ),

        // --- Spotlight ---
        ClaudeTool(
            name: "spotlight_search",
            description: "Search for files, apps, or folders using macOS Spotlight (mdfind). Use this to find applications before opening them, or to locate files/folders.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "query": PropertySchema(type: "string", description: "Search query (app name, file name, etc.)", enumValues: nil),
                    "kind": PropertySchema(type: "string", description: "Filter by type", enumValues: ["application", "document", "folder", "image", "any"])
                ],
                required: ["query"]
            )
        ),

        // --- App Management ---
        ClaudeTool(
            name: "list_apps",
            description: "List all currently running applications with their names, PIDs, and bundle IDs.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "get_frontmost_app",
            description: "Get information about the currently active (frontmost) application.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "activate_app",
            description: "Bring a running application to the foreground by its name.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "name": PropertySchema(type: "string", description: "The application name", enumValues: nil)
                ],
                required: ["name"]
            )
        ),
        ClaudeTool(
            name: "open_app",
            description: "Launch and activate an application by name. Uses 'open -a' which works with any app including those not currently running.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "name": PropertySchema(type: "string", description: "The application name to open", enumValues: nil)
                ],
                required: ["name"]
            )
        ),

        // --- UI Inspection ---
        ClaudeTool(
            name: "get_ui_elements",
            description: "Get the accessibility tree of a running application. Returns buttons, text fields, labels, and other UI elements with their positions, sizes, center coordinates, and available actions. Use this to find clickable targets before clicking. Elements include center coordinates for easy clicking.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "The application name or PID to inspect", enumValues: nil),
                    "max_depth": PropertySchema(type: "integer", description: "Maximum depth to traverse the UI tree (default: 3, max: 5)", enumValues: nil)
                ],
                required: ["app_name"]
            )
        ),

        // --- Mouse ---
        ClaudeTool(
            name: "click_element",
            description: "Click at specific screen coordinates. Use get_ui_elements first to find the exact coordinates of the element you want to click.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "x": PropertySchema(type: "integer", description: "X coordinate (screen pixels)", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y coordinate (screen pixels)", enumValues: nil),
                    "button": PropertySchema(type: "string", description: "Mouse button (default: left)", enumValues: ["left", "right"]),
                    "double_click": PropertySchema(type: "boolean", description: "Double-click (default: false)", enumValues: nil)
                ],
                required: ["x", "y"]
            )
        ),
        ClaudeTool(
            name: "mouse_move",
            description: "Move the mouse cursor to a specific position without clicking.",
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
            description: "Scroll at a specific position. Move the mouse to the position and scroll in the specified direction.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "x": PropertySchema(type: "integer", description: "X coordinate to scroll at", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y coordinate to scroll at", enumValues: nil),
                    "direction": PropertySchema(type: "string", description: "Scroll direction", enumValues: ["up", "down", "left", "right"]),
                    "amount": PropertySchema(type: "integer", description: "Number of scroll ticks (default: 3)", enumValues: nil)
                ],
                required: ["x", "y", "direction"]
            )
        ),
        ClaudeTool(
            name: "drag",
            description: "Click and drag from one position to another. Useful for moving windows, slider controls, drawing, etc.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "from_x": PropertySchema(type: "integer", description: "Starting X coordinate", enumValues: nil),
                    "from_y": PropertySchema(type: "integer", description: "Starting Y coordinate", enumValues: nil),
                    "to_x": PropertySchema(type: "integer", description: "Ending X coordinate", enumValues: nil),
                    "to_y": PropertySchema(type: "integer", description: "Ending Y coordinate", enumValues: nil),
                    "duration": PropertySchema(type: "number", description: "Duration of drag in seconds (default: 0.5)", enumValues: nil)
                ],
                required: ["from_x", "from_y", "to_x", "to_y"]
            )
        ),

        // --- Keyboard ---
        ClaudeTool(
            name: "type_text",
            description: "Type text character by character into the currently focused element. The text appears as if typed on the keyboard.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "text": PropertySchema(type: "string", description: "The text to type", enumValues: nil)
                ],
                required: ["text"]
            )
        ),
        ClaudeTool(
            name: "press_key",
            description: "Press a keyboard shortcut. Combine modifiers with '+'. Examples: 'command+c', 'command+shift+s', 'return', 'tab', 'escape', 'command+a', 'command+space' (Spotlight).",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "key": PropertySchema(type: "string", description: "Key combination (e.g., 'command+c', 'return', 'tab')", enumValues: nil)
                ],
                required: ["key"]
            )
        ),

        // --- Vision ---
        ClaudeTool(
            name: "take_screenshot",
            description: "Capture a screenshot of the screen or a specific region. The screenshot is sent to you as an image so you can SEE what's on screen. Use this frequently to verify your actions and understand the current state. Screenshots are downscaled to 1280px wide to save tokens.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "x": PropertySchema(type: "integer", description: "X coordinate of region (optional, omit for full screen)", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y coordinate of region (optional)", enumValues: nil),
                    "width": PropertySchema(type: "integer", description: "Width of region (optional)", enumValues: nil),
                    "height": PropertySchema(type: "integer", description: "Height of region (optional)", enumValues: nil)
                ],
                required: nil
            )
        ),

        // --- Window Management ---
        ClaudeTool(
            name: "list_windows",
            description: "List all visible windows with their owner app, title, position, and size. Useful for finding windows to interact with.",
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
            description: "Move an application's window to a new position.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "The application name", enumValues: nil),
                    "x": PropertySchema(type: "integer", description: "New X position", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "New Y position", enumValues: nil)
                ],
                required: ["app_name", "x", "y"]
            )
        ),
        ClaudeTool(
            name: "resize_window",
            description: "Resize an application's window.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "app_name": PropertySchema(type: "string", description: "The application name", enumValues: nil),
                    "width": PropertySchema(type: "integer", description: "New width", enumValues: nil),
                    "height": PropertySchema(type: "integer", description: "New height", enumValues: nil)
                ],
                required: ["app_name", "width", "height"]
            )
        ),

        // --- Utilities ---
        ClaudeTool(
            name: "open_url",
            description: "Open a URL in the default web browser.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "url": PropertySchema(type: "string", description: "The URL to open", enumValues: nil)
                ],
                required: ["url"]
            )
        ),
        ClaudeTool(
            name: "read_clipboard",
            description: "Read the current contents of the system clipboard.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "write_clipboard",
            description: "Write text to the system clipboard.",
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
            description: "Get the current screen dimensions in pixels.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "wait",
            description: "Pause for a specified duration. Use after clicking or typing to let the UI update before taking a screenshot.",
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
            description: "Read a file's contents. Supports text files up to 500 lines. Use for code, config, documents, data files, etc.",
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
            description: "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
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
            description: "List files and folders in a directory with sizes and types.",
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
            description: "Get detailed info about a file: size, dates, type, line count.",
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
            description: "Save information to persistent memory that survives across sessions. Use for remembering user preferences, project details, important findings, etc.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "topic": PropertySchema(type: "string", description: "Topic/filename for the memory (e.g., 'preferences', 'project-notes')", enumValues: nil),
                    "content": PropertySchema(type: "string", description: "Content to save (markdown format)", enumValues: nil),
                    "append": PropertySchema(type: "boolean", description: "Append to existing file instead of overwriting (default: false)", enumValues: nil)
                ],
                required: ["topic", "content"]
            )
        ),
        ClaudeTool(
            name: "read_memory",
            description: "Read from persistent memory. Returns the contents of a memory file.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "topic": PropertySchema(type: "string", description: "Topic/filename to read (omit for list of all memory files)", enumValues: nil)
                ],
                required: nil
            )
        ),

        // --- Sub-Agents ---
        ClaudeTool(
            name: "run_subagents",
            description: """
            Run multiple sub-tasks in PARALLEL, each handled by a separate AI agent with its own conversation.
            Use this when you need to: analyze multiple files, research multiple topics, perform independent tasks simultaneously.

            Agent types:
            - "general": Full tool access, general purpose tasks
            - "explore": Fast read-only research (shell, read files, spotlight) — no writes or GUI
            - "analyze": Deep analysis of files/data — read-only, no GUI
            - "execute": Action-oriented — can use GUI, shell, AppleScript, everything except spawning more sub-agents

            Each task needs: id (unique), description (short), prompt (detailed instructions), type (agent type).
            Pass tasks as a JSON array string.
            """,
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "tasks": PropertySchema(type: "string", description: "JSON array of tasks. Each: {\"id\": \"t1\", \"description\": \"short desc\", \"prompt\": \"detailed instructions for the sub-agent\", \"type\": \"explore|analyze|execute|general\"}", enumValues: nil),
                    "context": PropertySchema(type: "string", description: "Optional context from the current conversation to share with all sub-agents (e.g., what you've found so far, the user's goal)", enumValues: nil)
                ],
                required: ["tasks"]
            )
        ),
    ]
}
