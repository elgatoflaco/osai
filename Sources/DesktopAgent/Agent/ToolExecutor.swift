import Foundation
import AppKit

// MARK: - Tool Handler Type

/// Closure type for handling tool execution
/// Returns (ToolResult, optional screenshot base64)
private typealias ToolHandler = (ToolExecutor, [String: AnyCodable]) -> (ToolResult, String?)

// MARK: - Tool Executor

final class ToolExecutor {
    let applescript: AppleScriptDriver
    let accessibility: AccessibilityDriver
    let keyboard: KeyboardDriver
    let vision: VisionDriver
    let shell: ShellDriver
    let file: FileDriver
    let memory: MemoryManager
    var mcpManager: MCPManager?
    var subAgentConfig: AgentConfig?
    var approvalSystem: ApprovalSystem?

    /// Track the last app the agent interacted with (open_app, activate_app, get_ui_elements)
    /// so we can re-activate it before type_text/press_key to avoid typing in the terminal.
    private var lastTargetApp: String?

    /// Lazy-loaded tool handler registry (O(1) lookup instead of O(n) switch)
    private lazy var toolHandlers: [String: ToolHandler] = buildToolHandlers()

    init() {
        self.applescript = AppleScriptDriver()
        self.accessibility = AccessibilityDriver()
        self.keyboard = KeyboardDriver()
        self.vision = VisionDriver()
        self.shell = ShellDriver()
        self.file = FileDriver()
        self.memory = MemoryManager()
    }

    /// Ensure the target app has focus before keyboard input.
    /// Without this, keystrokes can go to the terminal instead of the intended app.
    private func ensureAppFocus() {
        guard let app = lastTargetApp, !app.isEmpty else { return }
        // Use NSWorkspace to activate without side effects
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == app.lowercased() ||
            $0.localizedName?.lowercased().contains(app.lowercased()) == true
        }) {
            running.activate()
            Thread.sleep(forTimeInterval: 0.1)  // Brief wait for activation
        }
    }

    /// Main tool executor - checks priority handlers, then uses O(1) dictionary dispatch
    func execute(toolName: String, input: [String: AnyCodable]) -> (result: ToolResult, screenshotBase64: String?) {
        // Priority 1: Self-modification tools
        if SelfModificationTools.canHandle(toolName) {
            return (SelfModificationTools.execute(toolName: toolName, input: input), nil)
        }

        // Priority 2: MCP tools
        if let mcp = mcpManager, mcp.canHandle(toolName: toolName) {
            let args = input.mapValues { $0.value }
            return (mcp.executeTool(qualifiedName: toolName, arguments: args), nil)
        }

        // Priority 3: Built-in tools via registry (O(1) lookup)
        if let handler = toolHandlers[toolName] {
            return handler(self, input)
        }

        // Unknown tool
        return (ToolResult(success: false, output: "Unknown tool: \(toolName)", screenshot: nil), nil)
    }

    // MARK: - Tool Handler Registry

    /// Build the tool handler dictionary for O(1) lookup
    /// This is called once via lazy initialization
    private func buildToolHandlers() -> [String: ToolHandler] {
        var handlers: [String: ToolHandler] = [:]

        // --- AppleScript ---
        handlers["run_applescript"] = { exe, input in
            let script = input["script"]?.stringValue ?? ""
            exe.vision.invalidateCache()  // AppleScript may change screen state
            return (exe.applescript.execute(script), nil)
        }

        // --- Shell ---
        handlers["run_shell"] = { exe, input in
            let command = input["command"]?.stringValue ?? ""
            let timeout = input["timeout"]?.intValue ?? 30
            // Protect osai source code from direct modification via shell
            let sourcePatterns = ["/Sites/osai/Sources/", "/Sites/osai/Package.swift"]
            let writeCommands = ["sed -i", "tee ", "> ", ">> ", "cat >", "echo >", "cp ", "mv ", "rm ", "git checkout", "git reset"]
            let isSourceWrite = sourcePatterns.contains { srcP in
                writeCommands.contains { wc in command.contains(srcP) && command.contains(wc) }
            }
            if isSourceWrite {
                return (ToolResult(success: false, output: "⛔ Cannot modify osai source code via shell. Use the `claude_code` tool to delegate programming tasks to Claude Code.", screenshot: nil), nil)
            }
            // wacli is allowed — it's the WhatsApp CLI tool for sending/reading messages
            // Block email via shell — must use send_email tool
            let emailPatterns = ["gmail +send", "gmail send", "gmail.*send", "sendmail", "mail -s", "gws.*mail.*send"]
            let lowerCmd = command.lowercased()
            if emailPatterns.contains(where: { lowerCmd.contains($0) }) || (lowerCmd.contains("email") && (lowerCmd.contains("export") || lowerCmd.contains("echo") || lowerCmd.contains("python"))) {
                return (ToolResult(success: false, output: "⛔ Do NOT send email via shell. Use the send_email tool instead: send_email(to: \"address\", subject: \"subject\", body: \"body\"). This is simpler and more reliable.", screenshot: nil), nil)
            }
            // --- Dangerous command guard ---
            // Block destructive commands unless yolo mode is active.
            // Instead of blocking the thread for input (LineEditor is on another thread),
            // we reject with a helpful message so the model can adjust.
            if let matched = exe.matchesDangerousPattern(lowerCmd) {
                let isYolo = exe.approvalSystem?.autoApprove ?? false
                if !isYolo {
                    return (ToolResult(success: false, output: "⚠️ Dangerous command detected: `\(command)`\nMatched pattern: \(matched)\n\nThis command could cause irreversible damage. Either:\n• Use a safer alternative\n• Ask the user to enable /yolo mode if they trust this action", screenshot: nil), nil)
                }
            }
            return (exe.shell.execute(command: command, timeout: timeout), nil)
        }

        // --- Spotlight ---
        handlers["spotlight_search"] = { exe, input in
            let query = input["query"]?.stringValue ?? ""
            let folder = input["folder"]?.stringValue
            let maxResults = input["max_results"]?.intValue ?? 10
            guard !query.isEmpty else {
                return (ToolResult(success: false, output: "Missing required field: query", screenshot: nil), nil)
            }
            let safeQuery = query.replacingOccurrences(of: "'", with: "'\\''")
            var cmd: String
            if let folder = folder, !folder.isEmpty {
                let safeFolder = folder.replacingOccurrences(of: "'", with: "'\\''")
                cmd = "mdfind -onlyin '\(safeFolder)' '\(safeQuery)' | head -\(maxResults)"
            } else {
                cmd = "mdfind '\(safeQuery)' | head -\(maxResults)"
            }
            let result = exe.shell.execute(command: cmd, timeout: 15)
            if result.success {
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return (ToolResult(success: true, output: output.isEmpty ? "No results found for: \(query)" : output, screenshot: nil), nil)
            }
            return (result, nil)
        }

        // --- Notification ---
        handlers["send_notification"] = { exe, input in
            let title = input["title"]?.stringValue ?? ""
            let message = input["message"]?.stringValue ?? ""
            let sound = input["sound"]?.stringValue ?? "default"
            guard !title.isEmpty, !message.isEmpty else {
                return (ToolResult(success: false, output: "Missing required fields: title, message", screenshot: nil), nil)
            }
            let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let safeMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
            let safeSound = sound.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "display notification \"\(safeMessage)\" with title \"\(safeTitle)\" sound name \"\(safeSound)\""
            let result = exe.shell.execute(command: "osascript -e '\(script.replacingOccurrences(of: "'", with: "'\\''"))'", timeout: 5)
            if result.success {
                return (ToolResult(success: true, output: "Notification sent: \(title)", screenshot: nil), nil)
            }
            return (result, nil)
        }

        // --- App Management ---
        handlers["list_apps"] = { exe, input in
            let apps = exe.applescript.listRunningApps()
            let output = apps.map { app in
                var line = "• \(app.name) (pid: \(app.pid))"
                if let bid = app.bundleId { line += " [\(bid)]" }
                if app.isActive { line += " [ACTIVE]" }
                return line
            }.joined(separator: "\n")
            return (ToolResult(success: true, output: output.isEmpty ? "No apps running" : output, screenshot: nil), nil)
        }

        handlers["get_frontmost_app"] = { exe, input in
            if let app = exe.applescript.getFrontmostApp() {
                let output = "\(app.name) (pid: \(app.pid))\(app.bundleId.map { " [\($0)]" } ?? "")"
                return (ToolResult(success: true, output: output, screenshot: nil), nil)
            }
            return (ToolResult(success: false, output: "No frontmost app found", screenshot: nil), nil)
        }

        handlers["activate_app"] = { exe, input in
            let name = input["name"]?.stringValue ?? ""
            exe.lastTargetApp = name
            return (exe.applescript.activateApp(name: name), nil)
        }

        handlers["open_app"] = { exe, input in
            let name = input["name"]?.stringValue ?? ""
            exe.lastTargetApp = name
            let result = exe.shell.execute(command: "open -a '\(name.replacingOccurrences(of: "'", with: "'\\''"))' 2>&1", timeout: 10)
            if result.success {
                Thread.sleep(forTimeInterval: 1.0)
                return (ToolResult(success: true, output: "Opened \(name)", screenshot: nil), nil)
            }
            let asResult = exe.applescript.openApp(name: name)
            if asResult.success { Thread.sleep(forTimeInterval: 1.0) }
            return (asResult, nil)
        }

        // --- UI Inspection ---
        handlers["get_ui_elements"] = { exe, input in
            let appName = input["app_name"]?.stringValue ?? ""
            exe.lastTargetApp = appName
            let maxDepth = min(input["max_depth"]?.intValue ?? 3, 5)

            var apps = exe.applescript.listRunningApps()
            var app = exe.accessibility.findApp(query: appName, runningApps: apps)
            if app == nil {
                apps = exe.applescript.listRunningApps(includeAccessory: true)
                app = exe.accessibility.findApp(query: appName, runningApps: apps)
            }

            guard let app = app else {
                let appList = apps.map { "\($0.name) (pid: \($0.pid))" }.joined(separator: ", ")
                return (ToolResult(success: false, output: "App '\(appName)' not found.\nRunning: \(appList)", screenshot: nil), nil)
            }

            if !exe.accessibility.checkPermissions() {
                return (ToolResult(success: false, output: "Accessibility permissions not granted.", screenshot: nil), nil)
            }

            let elements = exe.accessibility.getUIElements(pid: app.pid, maxDepth: maxDepth)
            let output = "App: \(app.name) (pid: \(app.pid))\n" + elements.map { exe.formatUIElement($0, indent: 0) }.joined(separator: "\n")
            return (ToolResult(success: true, output: output.isEmpty ? "No UI elements found" : output, screenshot: nil), nil)
        }

        // --- Mouse ---
        handlers["click_element"] = { exe, input in
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let button = input["button"]?.stringValue ?? "left"
            let doubleClick = input["double_click"]?.boolValue ?? false
            exe.vision.invalidateCache()  // Screen will change after click
            return (exe.keyboard.mouseClick(x: x, y: y, button: button, clickCount: doubleClick ? 2 : 1), nil)
        }

        handlers["mouse_move"] = { exe, input in
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            return (exe.keyboard.mouseMove(x: x, y: y), nil)
        }

        handlers["scroll"] = { exe, input in
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let direction = input["direction"]?.stringValue ?? "down"
            let amount = input["amount"]?.intValue ?? 3
            exe.vision.invalidateCache()  // Screen will change after scroll
            return (exe.keyboard.scroll(x: x, y: y, direction: direction, amount: amount), nil)
        }

        handlers["drag"] = { exe, input in
            let fromX = input["from_x"]?.intValue ?? 0
            let fromY = input["from_y"]?.intValue ?? 0
            let toX = input["to_x"]?.intValue ?? 0
            let toY = input["to_y"]?.intValue ?? 0
            let duration = input["duration"]?.doubleValue ?? 0.5
            exe.vision.invalidateCache()  // Screen will change after drag
            return (exe.keyboard.drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY, duration: duration), nil)
        }

        // --- Keyboard ---
        handlers["type_text"] = { exe, input in
            let text = input["text"]?.stringValue ?? ""
            exe.ensureAppFocus()
            exe.vision.invalidateCache()  // Screen will change after typing
            return (exe.keyboard.typeText(text), nil)
        }

        handlers["press_key"] = { exe, input in
            let key = input["key"]?.stringValue ?? ""
            exe.ensureAppFocus()
            exe.vision.invalidateCache()  // Screen will change after key press
            return (exe.keyboard.pressKey(key), nil)
        }

        // --- Vision ---
        handlers["take_screenshot"] = { exe, input in
            var region: ScreenRegion? = nil
            if let x = input["x"]?.intValue, let y = input["y"]?.intValue,
               let w = input["width"]?.intValue, let h = input["height"]?.intValue {
                region = ScreenRegion(x: x, y: y, width: w, height: h)
            }
            if let screenshot = exe.vision.takeScreenshotBase64(region: region) {
                return (ToolResult(success: true, output: screenshot.description, screenshot: nil), screenshot.base64)
            }
            return (ToolResult(success: false, output: "Failed to take screenshot.", screenshot: nil), nil)
        }

        // --- Window Management ---
        handlers["list_windows"] = { exe, input in
            let appFilter = input["app_name"]?.stringValue
            let windows = exe.accessibility.listWindows(appName: appFilter)
            if windows.isEmpty {
                return (ToolResult(success: true, output: "No windows found", screenshot: nil), nil)
            }
            return (ToolResult(success: true, output: windows.map { $0.description }.joined(separator: "\n"), screenshot: nil), nil)
        }

        handlers["move_window"] = { exe, input in
            let appName = input["app_name"]?.stringValue ?? ""
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let apps = exe.applescript.listRunningApps()
            guard let app = exe.accessibility.findApp(query: appName, runningApps: apps) else {
                return (ToolResult(success: false, output: "App '\(appName)' not found", screenshot: nil), nil)
            }
            return (exe.accessibility.setWindowPosition(pid: app.pid, x: x, y: y), nil)
        }

        handlers["resize_window"] = { exe, input in
            let appName = input["app_name"]?.stringValue ?? ""
            let w = input["width"]?.intValue ?? 800
            let h = input["height"]?.intValue ?? 600
            let apps = exe.applescript.listRunningApps()
            guard let app = exe.accessibility.findApp(query: appName, runningApps: apps) else {
                return (ToolResult(success: false, output: "App '\(appName)' not found", screenshot: nil), nil)
            }
            return (exe.accessibility.setWindowSize(pid: app.pid, width: w, height: h), nil)
        }

        // --- Window Manager ---
        handlers["window_manager"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""
            let appName = input["app_name"]?.stringValue ?? ""
            let title = input["title"]?.stringValue

            switch action {
            case "list_windows":
                let script = """
                tell application "System Events"
                    set windowList to ""
                    repeat with proc in (every process whose visible is true)
                        set procName to name of proc
                        try
                            repeat with win in (every window of proc)
                                set winTitle to name of win
                                set winPos to position of win
                                set winSize to size of win
                                set windowList to windowList & procName & " | " & winTitle & " | pos: (" & (item 1 of winPos) & ", " & (item 2 of winPos) & ") | size: (" & (item 1 of winSize) & "x" & (item 2 of winSize) & ")" & linefeed
                            end repeat
                        end try
                    end repeat
                    return windowList
                end tell
                """
                let result = exe.applescript.execute(script)
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return (ToolResult(success: result.success, output: output.isEmpty ? "No visible windows found" : output, screenshot: nil), nil)

            case "focus_window":
                guard !appName.isEmpty || title != nil else {
                    return (ToolResult(success: false, output: "Provide app_name or title to focus a window", screenshot: nil), nil)
                }
                if let title = title, !title.isEmpty {
                    let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
                    let script = """
                    tell application "System Events"
                        repeat with proc in (every process whose visible is true)
                            try
                                repeat with win in (every window of proc)
                                    if name of win contains "\(safeTitle)" then
                                        set frontmost of proc to true
                                        perform action "AXRaise" of win
                                        return "Focused: " & name of proc & " — " & name of win
                                    end if
                                end repeat
                            end try
                        end repeat
                        return "No window matching title: \(safeTitle)"
                    end tell
                    """
                    return (exe.applescript.execute(script), nil)
                } else {
                    let safeApp = appName.replacingOccurrences(of: "\"", with: "\\\"")
                    let script = """
                    tell application "\(safeApp)" to activate
                    return "Focused: \(safeApp)"
                    """
                    return (exe.applescript.execute(script), nil)
                }

            case "resize_window":
                guard !appName.isEmpty else {
                    return (ToolResult(success: false, output: "Provide app_name for resize_window", screenshot: nil), nil)
                }
                let safeApp = appName.replacingOccurrences(of: "\"", with: "\\\"")
                let x = input["x"]?.intValue
                let y = input["y"]?.intValue
                let w = input["width"]?.intValue
                let h = input["height"]?.intValue
                var commands: [String] = []
                if let x = x, let y = y {
                    commands.append("set position of window 1 to {\(x), \(y)}")
                }
                if let w = w, let h = h {
                    commands.append("set size of window 1 to {\(w), \(h)}")
                }
                guard !commands.isEmpty else {
                    return (ToolResult(success: false, output: "Provide x,y for position and/or width,height for size", screenshot: nil), nil)
                }
                let script = """
                tell application "System Events" to tell process "\(safeApp)"
                    \(commands.joined(separator: "\n    "))
                end tell
                return "Resized: \(safeApp)"
                """
                return (exe.applescript.execute(script), nil)

            case "minimize_window":
                guard !appName.isEmpty else {
                    return (ToolResult(success: false, output: "Provide app_name for minimize_window", screenshot: nil), nil)
                }
                let safeApp = appName.replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                tell application "System Events" to tell process "\(safeApp)"
                    set value of attribute "AXMinimized" of window 1 to true
                end tell
                return "Minimized: \(safeApp)"
                """
                return (exe.applescript.execute(script), nil)

            case "close_window":
                guard !appName.isEmpty else {
                    return (ToolResult(success: false, output: "Provide app_name for close_window", screenshot: nil), nil)
                }
                let safeApp = appName.replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                tell application "System Events" to tell process "\(safeApp)"
                    click (menu item "Close" of menu "File" of menu bar 1)
                end tell
                return "Closed window: \(safeApp)"
                """
                return (exe.applescript.execute(script), nil)

            case "tile_left":
                let script = """
                tell application "System Events"
                    set screenBounds to bounds of window of desktop
                    set screenW to item 3 of screenBounds
                    set screenH to item 4 of screenBounds
                    set halfW to screenW div 2
                    set frontProc to first process whose frontmost is true
                    tell frontProc
                        set position of window 1 to {0, 0}
                        set size of window 1 to {halfW, screenH}
                    end tell
                    return "Tiled left: " & name of frontProc & " (" & halfW & "x" & screenH & ")"
                end tell
                """
                exe.vision.invalidateCache()
                return (exe.applescript.execute(script), nil)

            case "tile_right":
                let script = """
                tell application "System Events"
                    set screenBounds to bounds of window of desktop
                    set screenW to item 3 of screenBounds
                    set screenH to item 4 of screenBounds
                    set halfW to screenW div 2
                    set frontProc to first process whose frontmost is true
                    tell frontProc
                        set position of window 1 to {halfW, 0}
                        set size of window 1 to {halfW, screenH}
                    end tell
                    return "Tiled right: " & name of frontProc & " (" & halfW & "x" & screenH & ")"
                end tell
                """
                exe.vision.invalidateCache()
                return (exe.applescript.execute(script), nil)

            case "fullscreen":
                let script = """
                tell application "System Events"
                    keystroke "f" using {control down, command down}
                end tell
                return "Toggled fullscreen"
                """
                exe.vision.invalidateCache()
                return (exe.applescript.execute(script), nil)

            default:
                return (ToolResult(success: false, output: "Unknown window_manager action: \(action). Valid: list_windows, focus_window, resize_window, minimize_window, close_window, tile_left, tile_right, fullscreen", screenshot: nil), nil)
            }
        }

        // --- Utilities ---
        handlers["open_url"] = { exe, input in
            let url = input["url"]?.stringValue ?? ""
            return (exe.applescript.openURL(url), nil)
        }

        handlers["read_clipboard"] = { exe, input in
            return (exe.applescript.getClipboard(), nil)
        }

        handlers["write_clipboard"] = { exe, input in
            let text = input["text"]?.stringValue ?? ""
            return (exe.applescript.setClipboard(text), nil)
        }

        handlers["clipboard_manager"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""

            switch action {
            case "read":
                let result = exe.shell.execute(command: "pbpaste", timeout: 5)
                if result.success {
                    let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (ToolResult(success: true, output: text.isEmpty ? "(clipboard is empty)" : text, screenshot: nil), nil)
                }
                return (result, nil)

            case "write":
                let content = input["content"]?.stringValue ?? ""
                guard !content.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: content", screenshot: nil), nil)
                }
                // Pipe content via stdin to pbcopy to handle special characters safely
                let safeContent = content.replacingOccurrences(of: "'", with: "'\\''")
                let result = exe.shell.execute(command: "printf '%s' '\(safeContent)' | pbcopy", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Text copied to clipboard (\(content.count) chars)", screenshot: nil)
                    : result, nil)

            case "write_image":
                let path = input["content"]?.stringValue ?? ""
                guard !path.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: content (image file path)", screenshot: nil), nil)
                }
                let resolvedPath = (path as NSString).expandingTildeInPath
                let safePath = resolvedPath.replacingOccurrences(of: "'", with: "'\\''")
                // Determine image type from extension
                let ext = (resolvedPath as NSString).pathExtension.lowercased()
                let imageType: String
                switch ext {
                case "png":
                    imageType = "PNG picture"
                case "tiff", "tif":
                    imageType = "TIFF picture"
                case "gif":
                    imageType = "GIF picture"
                default:
                    imageType = "JPEG picture"
                }
                let script = "set the clipboard to (read (POSIX file \"\(safePath)\") as \(imageType))"
                let result = exe.shell.execute(command: "osascript -e '\(script.replacingOccurrences(of: "'", with: "'\\''"))'", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: "Image copied to clipboard: \(resolvedPath)", screenshot: nil)
                    : result, nil)

            default:
                return (ToolResult(success: false, output: "Unknown clipboard_manager action: \(action). Valid actions: read, write, write_image", screenshot: nil), nil)
            }
        }

        handlers["get_screen_size"] = { exe, input in
            let size = exe.keyboard.getScreenSize()
            return (ToolResult(success: true, output: "\(size.width)x\(size.height)", screenshot: nil), nil)
        }

        handlers["wait"] = { exe, input in
            let seconds = min(max(input["seconds"]?.doubleValue ?? 1.0, 0.1), 10.0)
            Thread.sleep(forTimeInterval: seconds)
            return (ToolResult(success: true, output: "Waited \(seconds)s", screenshot: nil), nil)
        }

        // --- File Operations ---
        handlers["read_file"] = { exe, input in
            let path = input["path"]?.stringValue ?? ""
            let maxLines = input["max_lines"]?.intValue ?? 500
            return (exe.file.readFile(path: path, maxLines: maxLines), nil)
        }

        handlers["write_file"] = { exe, input in
            let path = input["path"]?.stringValue ?? ""
            let content = input["content"]?.stringValue ?? ""
            // Protect osai source code — must use claude_code tool for programming
            let resolved = (path as NSString).expandingTildeInPath
            if resolved.contains("/Sites/osai/Sources/") || resolved.contains("/Sites/osai/Package.swift") {
                return (ToolResult(success: false, output: "⛔ Cannot modify osai source code directly. Use the `claude_code` tool to delegate programming tasks to Claude Code.", screenshot: nil), nil)
            }
            return (exe.file.writeFile(path: path, content: content), nil)
        }

        handlers["list_directory"] = { exe, input in
            let path = input["path"]?.stringValue ?? ""
            let recursive = input["recursive"]?.boolValue ?? false
            return (exe.file.listDirectory(path: path, recursive: recursive), nil)
        }

        handlers["file_info"] = { exe, input in
            let path = input["path"]?.stringValue ?? ""
            return (exe.file.fileInfo(path: path), nil)
        }

        // --- System ---
        handlers["system_info"] = { exe, input in
            let commands: [(String, String)] = [
                ("macOS", "sw_vers -productVersion"),
                ("Build", "sw_vers -buildVersion"),
                ("Hostname", "hostname"),
                ("Username", "whoami"),
                ("CPU", "sysctl -n machdep.cpu.brand_string"),
                ("CPU Usage", "ps -A -o %cpu | awk '{s+=$1} END {printf \"%.1f%%\", s}'"),
                ("Memory", "vm_stat | awk '/Pages free/ {free=$3} /Pages active/ {active=$3} /Pages inactive/ {inactive=$3} /Pages speculative/ {spec=$3} /page size of/ {pagesize=$8} END {printf \"Free: %.0f MB, Active: %.0f MB\", (free+spec)*pagesize/1048576, active*pagesize/1048576}'"),
                ("Disk", "df -h / | tail -1 | awk '{print $4 \" available of \" $2}'"),
                ("WiFi", "networksetup -getairportnetwork en0 2>/dev/null | sed 's/Current Wi-Fi Network: //' || echo 'N/A'"),
                ("Battery", "pmset -g batt 2>/dev/null | grep -o '[0-9]*%' || echo 'N/A'"),
                ("Uptime", "uptime | sed 's/.*up /up /' | sed 's/,.*//'"),
            ]
            var lines: [String] = []
            for (label, cmd) in commands {
                let result = exe.shell.execute(command: cmd, timeout: 5)
                let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("\(label): \(value)")
            }
            return (ToolResult(success: true, output: lines.joined(separator: "\n"), screenshot: nil), nil)
        }

        handlers["notify"] = { exe, input in
            let title = input["title"]?.stringValue ?? ""
            let body = input["body"]?.stringValue ?? ""
            let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let safeBody = body.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\""
            let result = exe.shell.execute(command: "osascript -e '\(script.replacingOccurrences(of: "'", with: "'\\''"))'", timeout: 5)
            if result.success {
                return (ToolResult(success: true, output: "Notification sent: \(title)", screenshot: nil), nil)
            }
            return (result, nil)
        }

        handlers["web_search"] = { exe, input in
            let query = input["query"]?.stringValue ?? ""
            let maxResults = input["max_results"]?.intValue ?? 10
            guard !query.isEmpty else {
                return (ToolResult(success: false, output: "Missing required field: query", screenshot: nil), nil)
            }
            // URL-encode the query
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            // Use sed-based parsing (portable across macOS)
            let macCmd = """
            curl -sL -A 'Mozilla/5.0' 'https://html.duckduckgo.com/html/?q=\(encoded)' 2>/dev/null | \
            sed -n 's/.*class="result__a" href="\\([^"]*\\)".*/URL: \\1/p; s/.*class="result__a"[^>]*>\\([^<]*\\).*/Title: \\1/p' | \
            head -\(maxResults * 2)
            """
            let result = exe.shell.execute(command: macCmd, timeout: 15)
            if result.success && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (ToolResult(success: true, output: result.output, screenshot: nil), nil)
            }
            // Fallback: simpler parsing
            let fallbackCmd = """
            curl -sL -A 'Mozilla/5.0' 'https://html.duckduckgo.com/html/?q=\(encoded)' 2>/dev/null | \
            grep -o 'href="//duckduckgo.com/l/[^"]*"' | \
            sed 's/href="//;s/"$//' | \
            head -\(maxResults)
            """
            let fallback = exe.shell.execute(command: fallbackCmd, timeout: 15)
            if fallback.success && !fallback.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (ToolResult(success: true, output: fallback.output, screenshot: nil), nil)
            }
            return (ToolResult(success: true, output: "No results found for: \(query)", screenshot: nil), nil)
        }

        // --- System Control ---
        handlers["system_control"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""
            let value = input["value"]?.intValue

            switch action {
            case "set_volume":
                let vol = min(max(value ?? 50, 0), 100)
                let result = exe.shell.execute(command: "osascript -e 'set volume output volume \(vol)'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Volume set to \(vol)%", screenshot: nil)
                    : result, nil)

            case "toggle_wifi":
                // Determine current state and toggle
                let statusResult = exe.shell.execute(command: "networksetup -getairportpower en0 2>/dev/null", timeout: 5)
                let isOn = statusResult.output.lowercased().contains("on")
                let newState = isOn ? "off" : "on"
                let result = exe.shell.execute(command: "networksetup -setairportpower en0 \(newState)", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: "WiFi turned \(newState)", screenshot: nil)
                    : result, nil)

            case "toggle_bluetooth":
                // Try blueutil first, fall back to defaults
                let statusResult = exe.shell.execute(command: "blueutil --power 2>/dev/null", timeout: 5)
                if statusResult.success {
                    let isOn = statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                    let newState = isOn ? "0" : "1"
                    let result = exe.shell.execute(command: "blueutil --power \(newState)", timeout: 5)
                    return (result.success
                        ? ToolResult(success: true, output: "Bluetooth turned \(isOn ? "off" : "on")", screenshot: nil)
                        : result, nil)
                } else {
                    // Fallback: use AppleScript to open Bluetooth preferences
                    let result = exe.shell.execute(command: "open 'x-apple.systempreferences:com.apple.BluetoothSettings'", timeout: 5)
                    return (ToolResult(success: result.success, output: result.success
                        ? "Opened Bluetooth settings (install `blueutil` via Homebrew for direct toggle)"
                        : "Failed to toggle Bluetooth. Install blueutil: brew install blueutil", screenshot: nil), nil)
                }

            case "toggle_dnd":
                // Try Shortcuts first, fall back to Focus menu
                let result = exe.shell.execute(command: "shortcuts run 'Toggle Do Not Disturb' 2>/dev/null", timeout: 10)
                if result.success {
                    return (ToolResult(success: true, output: "Do Not Disturb toggled", screenshot: nil), nil)
                }
                // Fallback: use AppleScript to toggle via Control Center
                let fallback = exe.shell.execute(command: "osascript -e 'tell application \"System Events\" to tell process \"ControlCenter\" to click menu bar item \"Focus\" of menu bar 1' 2>/dev/null", timeout: 5)
                return (ToolResult(success: fallback.success, output: fallback.success
                    ? "Do Not Disturb toggled via Control Center"
                    : "Failed to toggle DND. Create a Shortcut named 'Toggle Do Not Disturb' for reliable toggling.", screenshot: nil), nil)

            case "set_brightness":
                let brightness = min(max(value ?? 50, 0), 100)
                let normalized = Double(brightness) / 100.0
                // Try brightness CLI first
                let result = exe.shell.execute(command: "brightness \(normalized) 2>/dev/null", timeout: 5)
                if result.success {
                    return (ToolResult(success: true, output: "Brightness set to \(brightness)%", screenshot: nil), nil)
                }
                // Fallback: AppleScript via System Events
                let asResult = exe.shell.execute(command: "osascript -e 'tell application \"System Preferences\" to quit' -e 'delay 0.5' -e 'do shell script \"brightness \(normalized)\"' 2>/dev/null || echo 'Install brightness: brew install brightness'", timeout: 10)
                return (ToolResult(success: asResult.success, output: asResult.success
                    ? "Brightness set to \(brightness)%"
                    : "Failed to set brightness. Install: brew install brightness", screenshot: nil), nil)

            case "toggle_dark_mode":
                let result = exe.shell.execute(command: "osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'", timeout: 5)
                if result.success {
                    // Read current state after toggle
                    let stateResult = exe.shell.execute(command: "osascript -e 'tell application \"System Events\" to tell appearance preferences to get dark mode'", timeout: 5)
                    let mode = stateResult.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" ? "Dark" : "Light"
                    return (ToolResult(success: true, output: "\(mode) mode activated", screenshot: nil), nil)
                }
                return (result, nil)

            case "lock_screen":
                let result = exe.shell.execute(command: "/System/Library/CoreServices/Menu\\ Extras/User.menu/Contents/Resources/CGSession -suspend", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Screen locked", screenshot: nil)
                    : result, nil)

            case "empty_trash":
                let result = exe.shell.execute(command: "osascript -e 'tell application \"Finder\" to empty trash'", timeout: 15)
                return (result.success
                    ? ToolResult(success: true, output: "Trash emptied", screenshot: nil)
                    : result, nil)

            case "sleep_display":
                let result = exe.shell.execute(command: "pmset displaysleepnow", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Display going to sleep", screenshot: nil)
                    : result, nil)

            default:
                return (ToolResult(success: false, output: "Unknown system_control action: \(action). Valid actions: set_volume, toggle_wifi, toggle_bluetooth, toggle_dnd, set_brightness, toggle_dark_mode, lock_screen, empty_trash, sleep_display", screenshot: nil), nil)
            }
        }

        // --- Media Control ---
        handlers["media_control"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""
            let value = input["value"]?.intValue
            let url = input["url"]?.stringValue ?? ""

            // Helper: detect whether Spotify is running
            let spotifyCheck = exe.shell.execute(command: "osascript -e 'tell app \"System Events\" to (name of processes) contains \"Spotify\"'", timeout: 5)
            let useSpotify = spotifyCheck.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            let app = useSpotify ? "Spotify" : "Music"

            switch action {
            case "play_pause":
                let result = exe.shell.execute(command: "osascript -e 'tell app \"\(app)\" to playpause'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Toggled play/pause on \(app)", screenshot: nil)
                    : result, nil)

            case "next_track":
                let result = exe.shell.execute(command: "osascript -e 'tell app \"\(app)\" to next track'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Skipped to next track on \(app)", screenshot: nil)
                    : result, nil)

            case "previous_track":
                let result = exe.shell.execute(command: "osascript -e 'tell app \"\(app)\" to previous track'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Went to previous track on \(app)", screenshot: nil)
                    : result, nil)

            case "now_playing":
                let script: String
                if useSpotify {
                    script = """
                    osascript -e 'tell app "Spotify"' \
                      -e 'set trackName to name of current track' \
                      -e 'set artistName to artist of current track' \
                      -e 'set albumName to album of current track' \
                      -e 'set playerState to player state as string' \
                      -e 'return trackName & " | " & artistName & " | " & albumName & " | " & playerState' \
                      -e 'end tell'
                    """
                } else {
                    script = """
                    osascript -e 'tell app "Music"' \
                      -e 'set trackName to name of current track' \
                      -e 'set artistName to artist of current track' \
                      -e 'set albumName to album of current track' \
                      -e 'set playerState to player state as string' \
                      -e 'return trackName & " | " & artistName & " | " & albumName & " | " & playerState' \
                      -e 'end tell'
                    """
                }
                let result = exe.shell.execute(command: script, timeout: 10)
                if result.success {
                    let parts = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " | ")
                    if parts.count >= 4 {
                        return (ToolResult(success: true, output: "Now playing on \(app):\n  Track: \(parts[0])\n  Artist: \(parts[1])\n  Album: \(parts[2])\n  State: \(parts[3])", screenshot: nil), nil)
                    }
                    return (ToolResult(success: true, output: "Now playing on \(app): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))", screenshot: nil), nil)
                }
                return (ToolResult(success: false, output: "No track currently playing or \(app) is not running.", screenshot: nil), nil)

            case "set_volume":
                let vol = min(max(value ?? 50, 0), 100)
                let script: String
                if useSpotify {
                    script = "osascript -e 'tell app \"Spotify\" to set sound volume to \(vol)'"
                } else {
                    script = "osascript -e 'tell app \"Music\" to set sound volume to \(vol)'"
                }
                let result = exe.shell.execute(command: script, timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "\(app) volume set to \(vol)%", screenshot: nil)
                    : result, nil)

            case "mute":
                let result = exe.shell.execute(command: "osascript -e 'set volume with output muted'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "System audio muted", screenshot: nil)
                    : result, nil)

            case "unmute":
                let result = exe.shell.execute(command: "osascript -e 'set volume without output muted'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "System audio unmuted", screenshot: nil)
                    : result, nil)

            case "open_url_in_browser":
                guard !url.isEmpty else {
                    return (ToolResult(success: false, output: "Missing 'url' parameter for open_url_in_browser action", screenshot: nil), nil)
                }
                let sanitized = url.replacingOccurrences(of: "\"", with: "\\\"")
                let result = exe.shell.execute(command: "open \"\(sanitized)\"", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: "Opened \(url) in default browser", screenshot: nil)
                    : result, nil)

            default:
                return (ToolResult(success: false, output: "Unknown media_control action: \(action). Valid actions: play_pause, next_track, previous_track, now_playing, set_volume, mute, unmute, open_url_in_browser", screenshot: nil), nil)
            }
        }

        // --- Process Manager ---
        handlers["process_manager"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""
            let target = input["target"]?.stringValue ?? ""

            switch action {
            case "list":
                let result = exe.shell.execute(command: "ps aux --sort=-%cpu | head -21", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: result.output, screenshot: nil)
                    : result, nil)

            case "kill":
                guard !target.isEmpty else {
                    return (ToolResult(success: false, output: "Missing 'target': provide a process name or PID to kill", screenshot: nil), nil)
                }
                // If target is numeric, use kill; otherwise use killall
                let command: String
                if target.allSatisfy({ $0.isNumber }) {
                    command = "kill \(target)"
                } else {
                    command = "killall \(target)"
                }
                let result = exe.shell.execute(command: command, timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: "Process '\(target)' killed", screenshot: nil)
                    : result, nil)

            case "launch":
                guard !target.isEmpty else {
                    return (ToolResult(success: false, output: "Missing 'target': provide an app name to launch", screenshot: nil), nil)
                }
                let result = exe.shell.execute(command: "open -a \"\(target)\"", timeout: 15)
                return (result.success
                    ? ToolResult(success: true, output: "Launched '\(target)'", screenshot: nil)
                    : result, nil)

            case "quit":
                guard !target.isEmpty else {
                    return (ToolResult(success: false, output: "Missing 'target': provide an app name to quit", screenshot: nil), nil)
                }
                let escaped = target.replacingOccurrences(of: "\"", with: "\\\"")
                let result = exe.shell.execute(command: "osascript -e 'tell application \"\(escaped)\" to quit'", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: "Quit '\(target)'", screenshot: nil)
                    : result, nil)

            case "info":
                guard !target.isEmpty else {
                    return (ToolResult(success: false, output: "Missing 'target': provide a process name or PID", screenshot: nil), nil)
                }
                let escaped = target.replacingOccurrences(of: "'", with: "'\\''")
                let result = exe.shell.execute(command: "ps aux | grep -i '\(escaped)' | grep -v grep", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: result.output.isEmpty ? "No matching processes found for '\(target)'" : result.output, screenshot: nil)
                    : result, nil)

            case "cpu_usage":
                let result = exe.shell.execute(command: "top -l 1 -s 0 | head -12", timeout: 15)
                return (result.success
                    ? ToolResult(success: true, output: result.output, screenshot: nil)
                    : result, nil)

            case "disk_usage":
                let result = exe.shell.execute(command: "df -h /", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: result.output, screenshot: nil)
                    : result, nil)

            default:
                return (ToolResult(success: false, output: "Unknown process_manager action: \(action). Valid actions: list, kill, launch, quit, info, cpu_usage, disk_usage", screenshot: nil), nil)
            }
        }

        // --- Network Info ---
        handlers["network_info"] = { exe, input in
            let action = input["action"]?.stringValue ?? "status"
            switch action {
            case "status":
                let ports = exe.shell.execute(command: "networksetup -listallhardwareports", timeout: 10)
                // Check which interfaces are active
                let active = exe.shell.execute(command: "ifconfig | grep -E '^[a-z]|inet ' | grep -B1 'inet ' | grep -E '^[a-z]' | cut -d: -f1", timeout: 5)
                var output = "Hardware Ports:\n\(ports.output)\n\nActive Interfaces: \(active.output.trimmingCharacters(in: .whitespacesAndNewlines))"
                return (ToolResult(success: true, output: output, screenshot: nil), nil)

            case "ip":
                let publicIP = exe.shell.execute(command: "curl -s --connect-timeout 5 ifconfig.me", timeout: 10)
                let localIP = exe.shell.execute(command: "ipconfig getifaddr en0 2>/dev/null || echo 'N/A'", timeout: 5)
                let output = "Public IP: \(publicIP.output.trimmingCharacters(in: .whitespacesAndNewlines))\nLocal IP: \(localIP.output.trimmingCharacters(in: .whitespacesAndNewlines))"
                return (ToolResult(success: true, output: output, screenshot: nil), nil)

            case "wifi_name":
                let wifi = exe.shell.execute(command: "networksetup -getairportnetwork en0 2>/dev/null || echo 'WiFi not available'", timeout: 5)
                let name = wifi.output.replacingOccurrences(of: "Current Wi-Fi Network: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return (ToolResult(success: true, output: "WiFi Network: \(name)", screenshot: nil), nil)

            case "dns":
                let dns = exe.shell.execute(command: "scutil --dns | grep 'nameserver\\[' | head -5", timeout: 5)
                let output = dns.output.trimmingCharacters(in: .whitespacesAndNewlines)
                return (ToolResult(success: true, output: output.isEmpty ? "No DNS servers found" : "DNS Servers:\n\(output)", screenshot: nil), nil)

            case "ping":
                let target = input["target"]?.stringValue ?? "google.com"
                let safeTarget = target.replacingOccurrences(of: "'", with: "'\\''")
                let ping = exe.shell.execute(command: "ping -c 3 '\(safeTarget)'", timeout: 15)
                return (ToolResult(success: ping.success, output: ping.output, screenshot: nil), nil)

            case "speed_test":
                let speed = exe.shell.execute(command: "curl -o /dev/null -s -w 'Download speed: %{speed_download} bytes/sec\\nTotal time: %{time_total}s\\nSize downloaded: %{size_download} bytes' http://speedtest.tele2.net/1MB.zip", timeout: 30)
                return (ToolResult(success: speed.success, output: speed.output, screenshot: nil), nil)

            default:
                return (ToolResult(success: false, output: "Unknown network_info action: \(action). Valid actions: status, ip, wifi_name, speed_test, dns, ping", screenshot: nil), nil)
            }
        }

        // --- Battery Info ---
        handlers["battery_info"] = { exe, input in
            let batt = exe.shell.execute(command: "pmset -g batt", timeout: 5)
            let raw = batt.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard batt.success, !raw.isEmpty else {
                return (ToolResult(success: false, output: "Could not retrieve battery info (this Mac may not have a battery)", screenshot: nil), nil)
            }
            // Parse: extract percentage, source, and time remaining
            var percentage = "N/A"
            var source = "Unknown"
            var timeRemaining = "N/A"
            var charging = "N/A"

            // Source line: "Now drawing from 'Battery Power'" or "'AC Power'"
            if raw.contains("'AC Power'") {
                source = "AC Power"
            } else if raw.contains("'Battery Power'") {
                source = "Battery Power"
            }

            // Battery line like: "-InternalBattery-0 (id=...)	85%; charging; 1:30 remaining"
            let lines = raw.components(separatedBy: "\n")
            for line in lines {
                if line.contains("InternalBattery") || line.contains("%") {
                    // Extract percentage
                    if let range = line.range(of: #"(\d+)%"#, options: .regularExpression) {
                        percentage = String(line[range])
                    }
                    // Extract charging status
                    if line.contains("charging") && !line.contains("not charging") && !line.contains("discharging") {
                        charging = "Charging"
                    } else if line.contains("discharging") {
                        charging = "Discharging"
                    } else if line.contains("not charging") {
                        charging = "Not Charging"
                    } else if line.contains("charged") {
                        charging = "Fully Charged"
                    }
                    // Extract time remaining
                    if let range = line.range(of: #"\d+:\d+ remaining"#, options: .regularExpression) {
                        timeRemaining = String(line[range])
                    } else if line.contains("(no estimate)") {
                        timeRemaining = "Calculating..."
                    }
                }
            }

            let output = "Battery: \(percentage), \(charging), Source: \(source), Time: \(timeRemaining)"
            return (ToolResult(success: true, output: output, screenshot: nil), nil)
        }

        // --- Email (via gws CLI) ---
        handlers["send_email"] = { exe, input in
            let to = input["to"]?.stringValue ?? ""
            let subject = input["subject"]?.stringValue ?? ""
            let body = input["body"]?.stringValue ?? ""
            guard !to.isEmpty, !subject.isEmpty else {
                return (ToolResult(success: false, output: "Missing required fields: to, subject", screenshot: nil), nil)
            }
            // Escape single quotes for shell
            let safeTo = to.replacingOccurrences(of: "'", with: "'\\''")
            let safeSubject = subject.replacingOccurrences(of: "'", with: "'\\''")
            let safeBody = body.replacingOccurrences(of: "'", with: "'\\''")
            let cmd = "gws gmail +send --to '\(safeTo)' --subject '\(safeSubject)' --body '\(safeBody)'"
            return (exe.shell.execute(command: cmd, timeout: 30), nil)
        }

        // --- Memory ---
        handlers["save_memory"] = { exe, input in
            let topic = input["topic"]?.stringValue ?? "notes"
            let content = input["content"]?.stringValue ?? ""
            let append = input["append"]?.boolValue ?? false
            exe.memory.memoryLoadedThisSession = true
            do {
                if append, let existing = exe.memory.readMemoryFile(name: topic) {
                    try exe.memory.writeMemoryFile(name: topic, content: existing + "\n\n" + content)
                } else {
                    try exe.memory.writeMemoryFile(name: topic, content: content)
                }
                return (ToolResult(success: true, output: "Memory saved: \(topic).md", screenshot: nil), nil)
            } catch {
                return (ToolResult(success: false, output: "Error saving memory: \(error)", screenshot: nil), nil)
            }
        }

        handlers["read_memory"] = { exe, input in
            let topic = input["topic"]?.stringValue
            exe.memory.memoryLoadedThisSession = true
            if let topic = topic {
                if let content = exe.memory.readMemoryFile(name: topic) {
                    return (ToolResult(success: true, output: content, screenshot: nil), nil)
                }
                return (ToolResult(success: false, output: "Memory file '\(topic)' not found", screenshot: nil), nil)
            } else {
                let files = exe.memory.listMemoryFiles()
                if files.isEmpty {
                    return (ToolResult(success: true, output: "No memory files yet.", screenshot: nil), nil)
                }
                let output = files.map { "• \($0.name) (\($0.size) bytes)" }.joined(separator: "\n")
                return (ToolResult(success: true, output: "Memory files:\n\(output)", screenshot: nil), nil)
            }
        }

        // --- Sub-Agents (handled by AgentLoop directly) ---
        handlers["run_subagents"] = { exe, input in
            return (ToolResult(success: true, output: "SUBAGENT_DISPATCH", screenshot: nil), nil)
        }

        // --- File Manager ---
        handlers["file_manager"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""
            let path = input["path"]?.stringValue ?? ""
            let destination = input["destination"]?.stringValue ?? ""
            let pattern = input["pattern"]?.stringValue ?? "*"

            // Resolve ~ in paths
            let resolvedPath = path.isEmpty ? "" : (path as NSString).expandingTildeInPath
            let resolvedDest = destination.isEmpty ? "" : (destination as NSString).expandingTildeInPath
            let safePath = resolvedPath.replacingOccurrences(of: "'", with: "'\\''")
            let safeDest = resolvedDest.replacingOccurrences(of: "'", with: "'\\''")
            let safePattern = pattern.replacingOccurrences(of: "'", with: "'\\''")

            switch action {
            case "list":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                return (exe.shell.execute(command: "ls -la '\(safePath)'", timeout: 10), nil)

            case "find":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                return (exe.shell.execute(command: "find '\(safePath)' -name '\(safePattern)' -maxdepth 3 2>/dev/null | head -20", timeout: 15), nil)

            case "info":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                return (exe.shell.execute(command: "stat -f '%N %z bytes, modified %Sm' '\(safePath)'", timeout: 5), nil)

            case "open":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                let result = exe.shell.execute(command: "open '\(safePath)'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Opened: \(path)", screenshot: nil)
                    : result, nil)

            case "reveal":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                let result = exe.shell.execute(command: "open -R '\(safePath)'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Revealed in Finder: \(path)", screenshot: nil)
                    : result, nil)

            case "move":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                guard !resolvedDest.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: destination", screenshot: nil), nil)
                }
                let result = exe.shell.execute(command: "mv '\(safePath)' '\(safeDest)'", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: "Moved: \(path) → \(destination)", screenshot: nil)
                    : result, nil)

            case "copy":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                guard !resolvedDest.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: destination", screenshot: nil), nil)
                }
                let result = exe.shell.execute(command: "cp -r '\(safePath)' '\(safeDest)'", timeout: 30)
                return (result.success
                    ? ToolResult(success: true, output: "Copied: \(path) → \(destination)", screenshot: nil)
                    : result, nil)

            case "trash":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                let safeAppleScriptPath = resolvedPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let result = exe.shell.execute(command: "osascript -e 'tell app \"Finder\" to delete POSIX file \"\(safeAppleScriptPath)\"'", timeout: 10)
                return (result.success
                    ? ToolResult(success: true, output: "Moved to trash: \(path)", screenshot: nil)
                    : result, nil)

            case "create_folder":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                let result = exe.shell.execute(command: "mkdir -p '\(safePath)'", timeout: 5)
                return (result.success
                    ? ToolResult(success: true, output: "Created folder: \(path)", screenshot: nil)
                    : result, nil)

            case "get_size":
                guard !resolvedPath.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: path", screenshot: nil), nil)
                }
                return (exe.shell.execute(command: "du -sh '\(safePath)'", timeout: 30), nil)

            default:
                return (ToolResult(success: false, output: "Unknown file_manager action: \(action). Valid actions: list, find, info, open, reveal, move, copy, trash, create_folder, get_size", screenshot: nil), nil)
            }
        }

        // --- Calendar Control ---
        handlers["calendar_control"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""
            let title = input["title"]?.stringValue ?? ""
            let date = input["date"]?.stringValue ?? ""
            let duration = input["duration"]?.intValue ?? 60
            let calendarName = input["calendar_name"]?.stringValue ?? ""
            let notes = input["notes"]?.stringValue ?? ""

            let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let safeNotes = notes.replacingOccurrences(of: "\"", with: "\\\"")
            let safeCalendar = calendarName.replacingOccurrences(of: "\"", with: "\\\"")

            switch action {
            case "list_calendars":
                let script = "tell application \"Calendar\" to get name of every calendar"
                return (exe.applescript.execute(script), nil)

            case "list_today":
                let script = """
                set today to current date
                set hours of today to 0
                set minutes of today to 0
                set seconds of today to 0
                set tomorrow to today + (1 * days)
                set output to ""
                tell application "Calendar"
                    repeat with cal in calendars
                        set evts to (every event of cal whose start date >= today and start date < tomorrow)
                        repeat with evt in evts
                            set evtStart to start date of evt
                            set evtEnd to end date of evt
                            set output to output & (summary of evt) & " | " & (evtStart as string) & " - " & (evtEnd as string) & " [" & (name of cal) & "]" & linefeed
                        end repeat
                    end repeat
                end tell
                if output is "" then return "No events today."
                return output
                """
                return (exe.applescript.execute(script), nil)

            case "list_week":
                let script = """
                set today to current date
                set hours of today to 0
                set minutes of today to 0
                set seconds of today to 0
                set weekEnd to today + (7 * days)
                set output to ""
                tell application "Calendar"
                    repeat with cal in calendars
                        set evts to (every event of cal whose start date >= today and start date < weekEnd)
                        repeat with evt in evts
                            set evtStart to start date of evt
                            set evtEnd to end date of evt
                            set output to output & (summary of evt) & " | " & (evtStart as string) & " - " & (evtEnd as string) & " [" & (name of cal) & "]" & linefeed
                        end repeat
                    end repeat
                end tell
                if output is "" then return "No events this week."
                return output
                """
                return (exe.applescript.execute(script), nil)

            case "create_event":
                guard !safeTitle.isEmpty, !date.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required fields: title, date", screenshot: nil), nil)
                }
                let calTarget = safeCalendar.isEmpty ? "first calendar" : "calendar \"\(safeCalendar)\""
                let notesLine = safeNotes.isEmpty ? "" : "set description of newEvent to \"\(safeNotes)\""
                let script = """
                set eventDate to date "\(date)"
                set eventEnd to eventDate + (\(duration) * minutes)
                tell application "Calendar"
                    tell \(calTarget)
                        set newEvent to make new event with properties {summary:"\(safeTitle)", start date:eventDate, end date:eventEnd}
                        \(notesLine)
                    end tell
                end tell
                return "Event created: \(safeTitle)"
                """
                return (exe.applescript.execute(script), nil)

            case "delete_event":
                guard !safeTitle.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: title", screenshot: nil), nil)
                }
                let script = """
                tell application "Calendar"
                    repeat with cal in calendars
                        set evts to (every event of cal whose summary is "\(safeTitle)")
                        repeat with evt in evts
                            delete evt
                        end repeat
                    end repeat
                end tell
                return "Deleted events matching: \(safeTitle)"
                """
                return (exe.applescript.execute(script), nil)

            default:
                return (ToolResult(success: false, output: "Unknown calendar_control action: \(action). Valid: list_today, list_week, create_event, delete_event, list_calendars", screenshot: nil), nil)
            }
        }

        // --- Reminders Control ---
        handlers["reminders_control"] = { exe, input in
            let action = input["action"]?.stringValue ?? ""
            let title = input["title"]?.stringValue ?? ""
            let listName = input["list_name"]?.stringValue ?? "Reminders"
            let dueDate = input["due_date"]?.stringValue ?? ""
            let notes = input["notes"]?.stringValue ?? ""

            let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let safeList = listName.replacingOccurrences(of: "\"", with: "\\\"")
            let safeNotes = notes.replacingOccurrences(of: "\"", with: "\\\"")

            switch action {
            case "list_lists":
                let script = "tell application \"Reminders\" to get name of every list"
                return (exe.applescript.execute(script), nil)

            case "list":
                let script = """
                set output to ""
                tell application "Reminders"
                    set rems to reminders of list "\(safeList)" whose completed is false
                    repeat with rem in rems
                        set remName to name of rem
                        set remDue to ""
                        try
                            set remDue to " (due: " & (due date of rem as string) & ")"
                        end try
                        set output to output & "- " & remName & remDue & linefeed
                    end repeat
                end tell
                if output is "" then return "No pending reminders in \(safeList)."
                return output
                """
                return (exe.applescript.execute(script), nil)

            case "create":
                guard !safeTitle.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: title", screenshot: nil), nil)
                }
                var props = "name:\"\(safeTitle)\""
                if !safeNotes.isEmpty {
                    props += ", body:\"\(safeNotes)\""
                }
                var dueLine = ""
                if !dueDate.isEmpty {
                    dueLine = "\nset due date of newReminder to date \"\(dueDate)\""
                }
                let script = """
                tell application "Reminders"
                    set newReminder to make new reminder in list "\(safeList)" with properties {\(props)}
                    \(dueLine)
                end tell
                return "Reminder created: \(safeTitle)"
                """
                return (exe.applescript.execute(script), nil)

            case "complete":
                guard !safeTitle.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: title", screenshot: nil), nil)
                }
                let script = """
                tell application "Reminders"
                    set targetReminder to first reminder of list "\(safeList)" whose name is "\(safeTitle)"
                    set completed of targetReminder to true
                end tell
                return "Completed: \(safeTitle)"
                """
                return (exe.applescript.execute(script), nil)

            case "delete":
                guard !safeTitle.isEmpty else {
                    return (ToolResult(success: false, output: "Missing required field: title", screenshot: nil), nil)
                }
                let script = """
                tell application "Reminders"
                    delete (first reminder of list "\(safeList)" whose name is "\(safeTitle)")
                end tell
                return "Deleted: \(safeTitle)"
                """
                return (exe.applescript.execute(script), nil)

            default:
                return (ToolResult(success: false, output: "Unknown reminders_control action: \(action). Valid: list, create, complete, delete, list_lists", screenshot: nil), nil)
            }
        }

        return handlers
    }

    // MARK: - Dangerous Command Detection

    /// Patterns that match potentially destructive shell commands.
    /// Each entry is (pattern, description) where the pattern is matched against the lowercased command.
    private static let dangerousPatterns: [(pattern: String, description: String)] = [
        // Destructive file operations
        ("rm -rf", "recursive force delete"),
        ("rm -r /", "recursive delete from root"),
        ("rmdir", "remove directory"),
        // Privilege escalation
        ("sudo ", "elevated privileges"),
        // Process killing
        ("kill -9", "force kill process"),
        ("killall", "kill all matching processes"),
        // Disk/filesystem destruction
        ("mkfs", "format filesystem"),
        ("dd if=", "raw disk write"),
        // Destructive git operations
        ("git push --force", "force push (rewrites remote history)"),
        ("git push -f ", "force push (rewrites remote history)"),
        ("git reset --hard", "hard reset (discards uncommitted changes)"),
        ("git clean -fd", "remove untracked files and directories"),
        ("git clean -f", "remove untracked files"),
        // SQL destruction
        ("drop table", "drop database table"),
        ("delete from", "delete database rows"),
        ("truncate table", "truncate database table"),
        // Permission changes
        ("chmod 777", "world-writable permissions"),
        ("chmod -r", "recursive permission change"),
        // Device writes
        ("> /dev/", "write to device file"),
    ]

    /// Check if a lowercased command matches any dangerous pattern.
    /// Returns the matched pattern description, or nil if safe.
    func matchesDangerousPattern(_ lowerCmd: String) -> String? {
        for (pattern, description) in Self.dangerousPatterns {
            if lowerCmd.contains(pattern) {
                return description
            }
        }
        return nil
    }

    // MARK: - Helpers

    func formatUIElement(_ element: UIElement, indent: Int) -> String {
        let prefix = String(repeating: "  ", count: indent)
        var lines = ["\(prefix)\(element.description)"]
        for child in element.children {
            lines.append(formatUIElement(child, indent: indent + 1))
        }
        return lines.joined(separator: "\n")
    }
}
