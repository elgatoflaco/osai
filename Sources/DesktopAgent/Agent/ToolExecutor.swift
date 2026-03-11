import Foundation
import AppKit

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

    /// Track the last app the agent interacted with (open_app, activate_app, get_ui_elements)
    /// so we can re-activate it before type_text/press_key to avoid typing in the terminal.
    private var lastTargetApp: String?

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

    func execute(toolName: String, input: [String: AnyCodable]) -> (result: ToolResult, screenshotBase64: String?) {

        // Check self-modification tools first
        if SelfModificationTools.canHandle(toolName) {
            return (SelfModificationTools.execute(toolName: toolName, input: input), nil)
        }

        // Check MCP tools
        if let mcp = mcpManager, mcp.canHandle(toolName: toolName) {
            let args = input.mapValues { $0.value }
            return (mcp.executeTool(qualifiedName: toolName, arguments: args), nil)
        }

        switch toolName {

        // --- AppleScript ---
        case "run_applescript":
            let script = input["script"]?.stringValue ?? ""
            return (applescript.execute(script), nil)

        // --- Shell ---
        case "run_shell":
            let command = input["command"]?.stringValue ?? ""
            let timeout = input["timeout"]?.intValue ?? 30
            return (shell.execute(command: command, timeout: timeout), nil)

        // --- Spotlight ---
        case "spotlight_search":
            let query = input["query"]?.stringValue ?? ""
            let kind = input["kind"]?.stringValue
            return (shell.spotlightSearch(query: query, kind: kind), nil)

        // --- App Management ---
        case "list_apps":
            let apps = applescript.listRunningApps()
            let output = apps.map { app in
                var line = "• \(app.name) (pid: \(app.pid))"
                if let bid = app.bundleId { line += " [\(bid)]" }
                if app.isActive { line += " [ACTIVE]" }
                return line
            }.joined(separator: "\n")
            return (ToolResult(success: true, output: output.isEmpty ? "No apps running" : output, screenshot: nil), nil)

        case "get_frontmost_app":
            if let app = applescript.getFrontmostApp() {
                let output = "\(app.name) (pid: \(app.pid))\(app.bundleId.map { " [\($0)]" } ?? "")"
                return (ToolResult(success: true, output: output, screenshot: nil), nil)
            }
            return (ToolResult(success: false, output: "No frontmost app found", screenshot: nil), nil)

        case "activate_app":
            let name = input["name"]?.stringValue ?? ""
            lastTargetApp = name
            return (applescript.activateApp(name: name), nil)

        case "open_app":
            let name = input["name"]?.stringValue ?? ""
            lastTargetApp = name
            let result = shell.execute(command: "open -a '\(name.replacingOccurrences(of: "'", with: "'\\''"))' 2>&1", timeout: 10)
            if result.success {
                Thread.sleep(forTimeInterval: 1.0)
                return (ToolResult(success: true, output: "Opened \(name)", screenshot: nil), nil)
            }
            let asResult = applescript.openApp(name: name)
            if asResult.success { Thread.sleep(forTimeInterval: 1.0) }
            return (asResult, nil)

        // --- UI Inspection ---
        case "get_ui_elements":
            let appName = input["app_name"]?.stringValue ?? ""
            lastTargetApp = appName
            let maxDepth = min(input["max_depth"]?.intValue ?? 3, 5)

            var apps = applescript.listRunningApps()
            var app = accessibility.findApp(query: appName, runningApps: apps)
            if app == nil {
                apps = applescript.listRunningApps(includeAccessory: true)
                app = accessibility.findApp(query: appName, runningApps: apps)
            }

            guard let app = app else {
                let appList = apps.map { "\($0.name) (pid: \($0.pid))" }.joined(separator: ", ")
                return (ToolResult(success: false, output: "App '\(appName)' not found.\nRunning: \(appList)", screenshot: nil), nil)
            }

            if !accessibility.checkPermissions() {
                return (ToolResult(success: false, output: "Accessibility permissions not granted.", screenshot: nil), nil)
            }

            let elements = accessibility.getUIElements(pid: app.pid, maxDepth: maxDepth)
            let output = "App: \(app.name) (pid: \(app.pid))\n" + elements.map { formatUIElement($0, indent: 0) }.joined(separator: "\n")
            return (ToolResult(success: true, output: output.isEmpty ? "No UI elements found" : output, screenshot: nil), nil)

        // --- Mouse ---
        case "click_element":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let button = input["button"]?.stringValue ?? "left"
            let doubleClick = input["double_click"]?.boolValue ?? false
            return (keyboard.mouseClick(x: x, y: y, button: button, clickCount: doubleClick ? 2 : 1), nil)

        case "mouse_move":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            return (keyboard.mouseMove(x: x, y: y), nil)

        case "scroll":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let direction = input["direction"]?.stringValue ?? "down"
            let amount = input["amount"]?.intValue ?? 3
            return (keyboard.scroll(x: x, y: y, direction: direction, amount: amount), nil)

        case "drag":
            let fromX = input["from_x"]?.intValue ?? 0
            let fromY = input["from_y"]?.intValue ?? 0
            let toX = input["to_x"]?.intValue ?? 0
            let toY = input["to_y"]?.intValue ?? 0
            let duration = input["duration"]?.doubleValue ?? 0.5
            return (keyboard.drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY, duration: duration), nil)

        // --- Keyboard ---
        case "type_text":
            let text = input["text"]?.stringValue ?? ""
            ensureAppFocus()  // Re-activate target app so keystrokes don't go to terminal
            return (keyboard.typeText(text), nil)

        case "press_key":
            let key = input["key"]?.stringValue ?? ""
            ensureAppFocus()  // Re-activate target app
            return (keyboard.pressKey(key), nil)

        // --- Vision ---
        case "take_screenshot":
            var region: ScreenRegion? = nil
            if let x = input["x"]?.intValue, let y = input["y"]?.intValue,
               let w = input["width"]?.intValue, let h = input["height"]?.intValue {
                region = ScreenRegion(x: x, y: y, width: w, height: h)
            }
            if let screenshot = vision.takeScreenshotBase64(region: region) {
                return (ToolResult(success: true, output: screenshot.description, screenshot: nil), screenshot.base64)
            }
            return (ToolResult(success: false, output: "Failed to take screenshot.", screenshot: nil), nil)

        // --- Window Management ---
        case "list_windows":
            let appFilter = input["app_name"]?.stringValue
            let windows = accessibility.listWindows(appName: appFilter)
            if windows.isEmpty {
                return (ToolResult(success: true, output: "No windows found", screenshot: nil), nil)
            }
            return (ToolResult(success: true, output: windows.map { $0.description }.joined(separator: "\n"), screenshot: nil), nil)

        case "move_window":
            let appName = input["app_name"]?.stringValue ?? ""
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            let apps = applescript.listRunningApps()
            guard let app = accessibility.findApp(query: appName, runningApps: apps) else {
                return (ToolResult(success: false, output: "App '\(appName)' not found", screenshot: nil), nil)
            }
            return (accessibility.setWindowPosition(pid: app.pid, x: x, y: y), nil)

        case "resize_window":
            let appName = input["app_name"]?.stringValue ?? ""
            let w = input["width"]?.intValue ?? 800
            let h = input["height"]?.intValue ?? 600
            let apps = applescript.listRunningApps()
            guard let app = accessibility.findApp(query: appName, runningApps: apps) else {
                return (ToolResult(success: false, output: "App '\(appName)' not found", screenshot: nil), nil)
            }
            return (accessibility.setWindowSize(pid: app.pid, width: w, height: h), nil)

        // --- Utilities ---
        case "open_url":
            let url = input["url"]?.stringValue ?? ""
            return (applescript.openURL(url), nil)

        case "read_clipboard":
            return (applescript.getClipboard(), nil)

        case "write_clipboard":
            let text = input["text"]?.stringValue ?? ""
            return (applescript.setClipboard(text), nil)

        case "get_screen_size":
            let size = keyboard.getScreenSize()
            return (ToolResult(success: true, output: "\(size.width)x\(size.height)", screenshot: nil), nil)

        case "wait":
            let seconds = min(max(input["seconds"]?.doubleValue ?? 1.0, 0.1), 10.0)
            Thread.sleep(forTimeInterval: seconds)
            return (ToolResult(success: true, output: "Waited \(seconds)s", screenshot: nil), nil)

        // --- File Operations ---
        case "read_file":
            let path = input["path"]?.stringValue ?? ""
            let maxLines = input["max_lines"]?.intValue ?? 500
            return (file.readFile(path: path, maxLines: maxLines), nil)

        case "write_file":
            let path = input["path"]?.stringValue ?? ""
            let content = input["content"]?.stringValue ?? ""
            return (file.writeFile(path: path, content: content), nil)

        case "list_directory":
            let path = input["path"]?.stringValue ?? ""
            let recursive = input["recursive"]?.boolValue ?? false
            return (file.listDirectory(path: path, recursive: recursive), nil)

        case "file_info":
            let path = input["path"]?.stringValue ?? ""
            return (file.fileInfo(path: path), nil)

        // --- Memory ---
        case "save_memory":
            let topic = input["topic"]?.stringValue ?? "notes"
            let content = input["content"]?.stringValue ?? ""
            let append = input["append"]?.boolValue ?? false
            do {
                if append, let existing = memory.readMemoryFile(name: topic) {
                    try memory.writeMemoryFile(name: topic, content: existing + "\n\n" + content)
                } else {
                    try memory.writeMemoryFile(name: topic, content: content)
                }
                return (ToolResult(success: true, output: "Memory saved: \(topic).md", screenshot: nil), nil)
            } catch {
                return (ToolResult(success: false, output: "Error saving memory: \(error)", screenshot: nil), nil)
            }

        case "read_memory":
            let topic = input["topic"]?.stringValue
            if let topic = topic {
                if let content = memory.readMemoryFile(name: topic) {
                    return (ToolResult(success: true, output: content, screenshot: nil), nil)
                }
                return (ToolResult(success: false, output: "Memory file '\(topic)' not found", screenshot: nil), nil)
            } else {
                let files = memory.listMemoryFiles()
                if files.isEmpty {
                    return (ToolResult(success: true, output: "No memory files yet.", screenshot: nil), nil)
                }
                let output = files.map { "• \($0.name) (\($0.size) bytes)" }.joined(separator: "\n")
                return (ToolResult(success: true, output: "Memory files:\n\(output)", screenshot: nil), nil)
            }

        // --- Sub-Agents (handled by AgentLoop directly) ---
        case "run_subagents":
            return (ToolResult(success: true, output: "SUBAGENT_DISPATCH", screenshot: nil), nil)

        default:
            return (ToolResult(success: false, output: "Unknown tool: \(toolName)", screenshot: nil), nil)
        }
    }

    // MARK: - Helpers

    private func formatUIElement(_ element: UIElement, indent: Int) -> String {
        let prefix = String(repeating: "  ", count: indent)
        var lines = ["\(prefix)\(element.description)"]
        for child in element.children {
            lines.append(formatUIElement(child, indent: indent + 1))
        }
        return lines.joined(separator: "\n")
    }
}
