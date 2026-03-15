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
            // Block wacli commands — the gateway handles WhatsApp messaging
            if command.contains("wacli") {
                return (ToolResult(success: false, output: "⛔ Do not use wacli directly. Your text responses are automatically sent to the user via the gateway. Just reply with text — the gateway delivers it.", screenshot: nil), nil)
            }
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
            let kind = input["kind"]?.stringValue
            return (exe.shell.spotlightSearch(query: query, kind: kind), nil)
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
