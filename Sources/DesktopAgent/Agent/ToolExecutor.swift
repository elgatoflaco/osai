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
