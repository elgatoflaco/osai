import Foundation

// MARK: - Tool Category for Dynamic Loading

enum ToolCategory: String, CaseIterable {
    case core           // always loaded: take_screenshot, click_element, type_text, press_key, run_shell, read_file, write_file, clipboard_manager, send_notification, spotlight_search, file_manager, screen_capture, ocr_text
    case gui            // get_ui_elements, scroll, drag, mouse_move, wait, list_windows, move_window, resize_window, get_screen_size, window_manager
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
    case apps           // list_apps, get_frontmost_app, activate_app, open_app, calendar_control, reminders_control, contacts_lookup, imessage_send, notes_control, timer_control
    case files          // list_directory, file_info, read_clipboard, write_clipboard
    case system         // system_info, notify, web_search, process_manager, network_info, battery_info, media_control, text_to_speech, system_appearance
}

// MARK: - Tool Definitions for Claude

struct ToolDefinitions {

    // MARK: - Tool Category Map

    /// Maps each tool name to its category
    static let toolCategoryMap: [String: ToolCategory] = {
        var map: [String: ToolCategory] = [:]

        // Core (always loaded)
        for name in ["take_screenshot", "click_element", "type_text", "press_key", "run_shell", "read_file", "write_file", "clipboard_manager", "send_notification", "spotlight_search", "file_manager", "screen_capture", "ocr_text"] {
            map[name] = .core
        }

        // GUI
        for name in ["get_ui_elements", "scroll", "drag", "mouse_move", "wait", "list_windows", "move_window", "resize_window", "get_screen_size", "window_manager"] {
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
        for name in ["run_subagents", "batch_execute", "orchestrator_stats", "orchestrator_insights", "clear_tool_cache"] {
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
        for name in ["list_apps", "get_frontmost_app", "activate_app", "open_app", "calendar_control", "reminders_control", "contacts_lookup", "imessage_send", "notes_control", "timer_control"] {
            map[name] = .apps
        }

        // Files
        for name in ["list_directory", "file_info", "read_clipboard", "write_clipboard"] {
            map[name] = .files
        }

        // System
        for name in ["system_info", "notify", "web_search", "system_control", "media_control", "process_manager", "network_info", "battery_info", "text_to_speech", "system_appearance"] {
            map[name] = .system
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

    /// The continue_thinking tool — lets the agent extend its reasoning for complex tasks
    static let continueThinkingTool = ClaudeTool(
        name: "continue_thinking",
        description: "Use this when a task is complex and you need more reasoning steps. Call this to pause, reflect on your progress, identify what's missing, and plan next steps. This gives you another turn to continue working instead of giving a shallow answer.",
        inputSchema: InputSchema(
            type: "object",
            properties: [
                "progress": PropertySchema(type: "string", description: "What you've done so far", enumValues: nil),
                "remaining": PropertySchema(type: "string", description: "What still needs to be done", enumValues: nil),
                "reflection": PropertySchema(type: "string", description: "What could be improved or what you might be missing", enumValues: nil)
            ],
            required: ["progress", "remaining"]
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
            description: """
            Schedule a task to run automatically via macOS launchd. The task executes osai with the given command at the scheduled time.

            Types: "once" (run once at ISO 8601 datetime), "daily" (run every day at hour:minute), "interval" (run every N minutes).

            For delivery via Discord/WhatsApp/Telegram, add "deliver" field with format "platform:chatId" (e.g. "discord:dm:123456" or "whatsapp:34612345678@s.whatsapp.net").

            IMPORTANT: Always verify the task was created by calling list_tasks after schedule_task. The command field should be a natural language instruction that osai will execute autonomously.
            """,
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "id": PropertySchema(type: "string", description: "Unique task ID (lowercase, hyphens, e.g. 'morning-briefing', 'whatsapp-yan-2130')", enumValues: nil),
                    "description": PropertySchema(type: "string", description: "Human-readable description shown in Tasks view", enumValues: nil),
                    "command": PropertySchema(type: "string", description: "Natural language instruction for osai to execute (e.g. 'Send a WhatsApp message to Yan Adrover saying hello')", enumValues: nil),
                    "schedule_type": PropertySchema(type: "string", description: "Type of schedule", enumValues: ["once", "daily", "interval"]),
                    "hour": PropertySchema(type: "integer", description: "Hour (0-23) for daily schedule", enumValues: nil),
                    "minute": PropertySchema(type: "integer", description: "Minute (0-59) for daily schedule", enumValues: nil),
                    "minutes": PropertySchema(type: "integer", description: "Interval in minutes for recurring tasks", enumValues: nil),
                    "at": PropertySchema(type: "string", description: "ISO 8601 datetime for one-time tasks (e.g. '2026-03-22T21:28:00+01:00')", enumValues: nil),
                    "deliver": PropertySchema(type: "string", description: "Delivery target: 'discord:dm:userId', 'discord:channelId', 'whatsapp:phone@s.whatsapp.net', 'telegram:chatId'", enumValues: nil)
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

    static let batchExecuteTool = ClaudeTool(
        name: "batch_execute",
        description: "Execute multiple tool calls in parallel and return all results at once. Use this to run 2-25 independent operations simultaneously (e.g., read multiple files, run multiple shell commands, check multiple apps). Much faster than calling tools one at a time. Each call specifies the tool name and its parameters.",
        inputSchema: InputSchema(
            type: "object",
            properties: [
                "calls": PropertySchema(type: "string", description: "JSON array of tool calls: [{\"tool\": \"tool_name\", \"params\": {\"key\": \"value\"}}, ...]. Max 25 calls.", enumValues: nil)
            ],
            required: ["calls"]
        )
    )

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

    static let allTools: [ClaudeTool] = SelfModificationTools.tools + mcpManagementTools + schedulerTools + gatewayTools + claudeCodeTools + orchestratorTools + adaptiveTools + [batchExecuteTool] + [
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
            description: "Search files on macOS using Spotlight (mdfind). Searches file contents and metadata.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "query": PropertySchema(type: "string", description: "Search query (Spotlight syntax, e.g. 'kMDItemDisplayName == *.swift' or plain text)", enumValues: nil),
                    "folder": PropertySchema(type: "string", description: "Limit search to this folder path (optional)", enumValues: nil),
                    "max_results": PropertySchema(type: "integer", description: "Maximum number of results to return (default: 10)", enumValues: nil)
                ],
                required: ["query"]
            )
        ),

        // --- Notification ---
        ClaudeTool(
            name: "send_notification",
            description: "Send a macOS notification to the user with a title, message, and optional sound.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "title": PropertySchema(type: "string", description: "Notification title", enumValues: nil),
                    "message": PropertySchema(type: "string", description: "Notification body message", enumValues: nil),
                    "sound": PropertySchema(type: "string", description: "Sound name (default: \"default\")", enumValues: nil)
                ],
                required: ["title", "message"]
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

        // --- Calendar Control ---
        ClaudeTool(
            name: "calendar_control",
            description: "Control macOS Calendar app: list today's or this week's events, create/delete events, list calendars.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["list_today", "list_week", "create_event", "delete_event", "list_calendars"]),
                    "title": PropertySchema(type: "string", description: "Event title (for create_event, delete_event)", enumValues: nil),
                    "date": PropertySchema(type: "string", description: "Event date in ISO 8601 format, e.g. 2025-03-21T14:00:00 (for create_event)", enumValues: nil),
                    "duration": PropertySchema(type: "integer", description: "Event duration in minutes (default: 60, for create_event)", enumValues: nil),
                    "calendar_name": PropertySchema(type: "string", description: "Calendar name (for create_event; omit for default calendar)", enumValues: nil),
                    "notes": PropertySchema(type: "string", description: "Event notes (for create_event)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Reminders Control ---
        ClaudeTool(
            name: "reminders_control",
            description: "Control macOS Reminders app: list, create, complete, delete reminders, and list reminder lists.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["list", "create", "complete", "delete", "list_lists"]),
                    "title": PropertySchema(type: "string", description: "Reminder title (for create, complete, delete)", enumValues: nil),
                    "list_name": PropertySchema(type: "string", description: "Reminders list name (default: Reminders)", enumValues: nil),
                    "due_date": PropertySchema(type: "string", description: "Due date in ISO 8601 format (for create)", enumValues: nil),
                    "notes": PropertySchema(type: "string", description: "Reminder notes (for create)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Contacts Lookup ---
        ClaudeTool(
            name: "contacts_lookup",
            description: "Search and read macOS Contacts via AppleScript. Search by name or get full details for a contact.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["search", "get_details"]),
                    "query": PropertySchema(type: "string", description: "Name to search for (for search action)", enumValues: nil),
                    "contact_id": PropertySchema(type: "string", description: "Contact name to get full details for (for get_details action)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- iMessage Send ---
        ClaudeTool(
            name: "imessage_send",
            description: "Send iMessages or read recent messages via AppleScript.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["send", "read_recent"]),
                    "recipient": PropertySchema(type: "string", description: "Phone number or email of recipient (for send)", enumValues: nil),
                    "message": PropertySchema(type: "string", description: "Message text to send (for send)", enumValues: nil),
                    "count": PropertySchema(type: "integer", description: "Number of recent messages to read (default: 5, for read_recent)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Notes Control ---
        ClaudeTool(
            name: "notes_control",
            description: "Control macOS Notes app: list folders, list/read/create/append/search notes.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["list_folders", "list_notes", "read_note", "create_note", "append_note", "search"]),
                    "folder": PropertySchema(type: "string", description: "Folder name (default: Notes)", enumValues: nil),
                    "title": PropertySchema(type: "string", description: "Note title (for read_note, create_note, append_note)", enumValues: nil),
                    "content": PropertySchema(type: "string", description: "Note content/body (for create_note, append_note)", enumValues: nil),
                    "query": PropertySchema(type: "string", description: "Search query (for search action)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Timer Control ---
        ClaudeTool(
            name: "timer_control",
            description: "Set timers, alarms, and stopwatch. Timers and alarms show a macOS notification when done.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["set_timer", "set_alarm", "stopwatch_start", "stopwatch_stop"]),
                    "seconds": PropertySchema(type: "integer", description: "Timer duration in seconds (for set_timer)", enumValues: nil),
                    "time": PropertySchema(type: "string", description: "Alarm time in HH:MM 24h format (for set_alarm)", enumValues: nil),
                    "label": PropertySchema(type: "string", description: "Optional label for the timer/alarm", enumValues: nil)
                ],
                required: ["action"]
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
        ClaudeTool(
            name: "window_manager",
            description: "Advanced window management: list, focus, resize, move, minimize, close, tile, and fullscreen windows.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Window action to perform", enumValues: ["list_windows", "focus_window", "resize_window", "minimize_window", "close_window", "tile_left", "tile_right", "fullscreen"]),
                    "app_name": PropertySchema(type: "string", description: "Application name (for focus, resize, minimize, close)", enumValues: nil),
                    "title": PropertySchema(type: "string", description: "Window title filter (optional, for focus)", enumValues: nil),
                    "x": PropertySchema(type: "integer", description: "X position (for resize_window)", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y position (for resize_window)", enumValues: nil),
                    "width": PropertySchema(type: "integer", description: "Window width (for resize_window)", enumValues: nil),
                    "height": PropertySchema(type: "integer", description: "Window height (for resize_window)", enumValues: nil)
                ],
                required: ["action"]
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
            name: "clipboard_manager",
            description: "Manage the macOS clipboard: read text, write text, or copy an image file to clipboard.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["read", "write", "write_image"]),
                    "content": PropertySchema(type: "string", description: "Text to write (for 'write') or image file path (for 'write_image')", enumValues: nil)
                ],
                required: ["action"]
            )
        ),
        ClaudeTool(
            name: "file_manager",
            description: "Manage files and folders: list, find, get info, open, reveal in Finder, move, copy, trash, create folders, and get folder sizes.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["list", "find", "info", "open", "reveal", "move", "copy", "trash", "create_folder", "get_size"]),
                    "path": PropertySchema(type: "string", description: "File or directory path (required for most actions)", enumValues: nil),
                    "destination": PropertySchema(type: "string", description: "Destination path (for move and copy)", enumValues: nil),
                    "pattern": PropertySchema(type: "string", description: "File name pattern (for find, e.g. '*.swift')", enumValues: nil)
                ],
                required: ["action"]
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

        // --- System ---
        ClaudeTool(
            name: "system_info",
            description: "Get system information: macOS version, hostname, username, CPU usage, free memory, disk space, WiFi network, battery level.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),
        ClaudeTool(
            name: "notify",
            description: "Send a macOS notification with a title and body message.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "title": PropertySchema(type: "string", description: "Notification title", enumValues: nil),
                    "body": PropertySchema(type: "string", description: "Notification body text", enumValues: nil)
                ],
                required: ["title", "body"]
            )
        ),
        ClaudeTool(
            name: "web_search",
            description: "Search the web using DuckDuckGo and return titles and URLs of results.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "query": PropertySchema(type: "string", description: "Search query", enumValues: nil),
                    "max_results": PropertySchema(type: "integer", description: "Maximum number of results to return (default: 10)", enumValues: nil)
                ],
                required: ["query"]
            )
        ),

        // --- System Control ---
        ClaudeTool(
            name: "system_control",
            description: "Control macOS system settings: volume, WiFi, Bluetooth, Do Not Disturb, brightness, dark mode, lock screen, empty trash, sleep display.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "System action to perform", enumValues: ["set_volume", "toggle_wifi", "toggle_bluetooth", "toggle_dnd", "set_brightness", "toggle_dark_mode", "lock_screen", "empty_trash", "sleep_display"]),
                    "value": PropertySchema(type: "integer", description: "Value for set_volume (0-100) or set_brightness (0-100)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Media Control ---
        ClaudeTool(
            name: "media_control",
            description: "Control music/media playback on macOS. Automatically detects Spotify or Apple Music. Can also open URLs in the default browser.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Media action to perform", enumValues: ["play_pause", "next_track", "previous_track", "now_playing", "set_volume", "mute", "unmute", "open_url_in_browser"]),
                    "value": PropertySchema(type: "integer", description: "Volume level 0-100 (for set_volume)", enumValues: nil),
                    "url": PropertySchema(type: "string", description: "URL to open (for open_url_in_browser)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Process Manager ---
        ClaudeTool(
            name: "process_manager",
            description: "Manage macOS processes: list top CPU consumers, kill/launch/quit apps, get process info, check CPU/memory/disk usage.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Action to perform", enumValues: ["list", "kill", "launch", "quit", "info", "cpu_usage", "disk_usage"]),
                    "target": PropertySchema(type: "string", description: "App name or PID (required for kill, launch, quit, info)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Network Info ---
        ClaudeTool(
            name: "network_info",
            description: "Get network information: connection status, public/local IP, WiFi name, DNS servers, ping, or a quick download speed test.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "What network info to retrieve", enumValues: ["status", "ip", "wifi_name", "speed_test", "dns", "ping"]),
                    "target": PropertySchema(type: "string", description: "Host to ping (default: google.com)", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- Battery Info ---
        ClaudeTool(
            name: "battery_info",
            description: "Get battery and power information: percentage, charging status, and time remaining.",
            inputSchema: InputSchema(
                type: "object",
                properties: [:],
                required: nil
            )
        ),

        // --- Text to Speech ---
        ClaudeTool(
            name: "text_to_speech",
            description: "Read text aloud using macOS built-in speech synthesis. Runs in background so it doesn't block. Use action 'stop' to stop any ongoing speech.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "text": PropertySchema(type: "string", description: "Text to read aloud (required unless action is 'stop')", enumValues: nil),
                    "voice": PropertySchema(type: "string", description: "Voice name (e.g. 'Samantha', 'Alex', 'Daniel'). Uses system default if omitted.", enumValues: nil),
                    "rate": PropertySchema(type: "integer", description: "Speech rate in words per minute (e.g. 200). Uses system default if omitted.", enumValues: nil),
                    "action": PropertySchema(type: "string", description: "Set to 'stop' to kill any ongoing speech", enumValues: ["speak", "stop"])
                ],
                required: ["text"]
            )
        ),

        // --- System Appearance ---
        ClaudeTool(
            name: "system_appearance",
            description: "Control macOS appearance settings: get/set wallpaper, list desktops, get/set accent color, toggle Stage Manager.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Appearance action to perform", enumValues: ["get_wallpaper", "set_wallpaper", "list_desktops", "get_accent_color", "set_accent_color", "toggle_stage_manager"]),
                    "path": PropertySchema(type: "string", description: "Image file path (for set_wallpaper)", enumValues: nil),
                    "color": PropertySchema(type: "string", description: "Accent color name (for set_accent_color)", enumValues: ["blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite"])
                ],
                required: ["action"]
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

        // --- Screen Capture (advanced) ---
        ClaudeTool(
            name: "screen_capture",
            description: "Advanced screen capture: capture a region, capture a specific window, or start/stop screen recording. Goes beyond take_screenshot with window-level and video recording support.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "action": PropertySchema(type: "string", description: "Capture action to perform", enumValues: ["capture_region", "capture_window", "record_start", "record_stop"]),
                    "app_name": PropertySchema(type: "string", description: "Application name for capture_window action", enumValues: nil),
                    "x": PropertySchema(type: "integer", description: "X coordinate for capture_region", enumValues: nil),
                    "y": PropertySchema(type: "integer", description: "Y coordinate for capture_region", enumValues: nil),
                    "width": PropertySchema(type: "integer", description: "Width for capture_region", enumValues: nil),
                    "height": PropertySchema(type: "integer", description: "Height for capture_region", enumValues: nil)
                ],
                required: ["action"]
            )
        ),

        // --- OCR Text Extraction ---
        ClaudeTool(
            name: "ocr_text",
            description: "Extract text from an image file using macOS Vision framework OCR. Supports accurate text recognition in multiple languages.",
            inputSchema: InputSchema(
                type: "object",
                properties: [
                    "image_path": PropertySchema(type: "string", description: "Absolute path to the image file", enumValues: nil),
                    "language": PropertySchema(type: "string", description: "Recognition language code (default: \"en\"). Examples: en, es, fr, de, zh, ja", enumValues: nil)
                ],
                required: ["image_path"]
            )
        ),
    ]
}
