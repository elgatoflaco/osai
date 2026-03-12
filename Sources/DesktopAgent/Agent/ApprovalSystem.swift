import Foundation

// MARK: - Approval System (like Claude Code's permission model)

enum DangerLevel: Comparable {
    case safe        // Auto-approved always
    case moderate    // Show what's happening, auto-approved in yolo mode
    case dangerous   // Requires explicit approval (unless yolo mode)
}

struct ActionClassification {
    let level: DangerLevel
    let reason: String
    let summary: String  // Human-readable one-liner
}

final class ApprovalSystem {
    var autoApprove: Bool = false  // YOLO mode
    private let lineEditor = LineEditor()

    /// Classify a tool action's danger level
    func classify(toolName: String, input: [String: AnyCodable]) -> ActionClassification {
        switch toolName {

        // --- Always safe ---
        case "list_apps", "get_frontmost_app", "list_windows", "get_screen_size",
             "read_clipboard", "take_screenshot", "spotlight_search", "list_directory",
             "file_info", "read_file", "read_memory", "read_program",
             "read_system_prompt", "read_improvement_log", "get_ui_elements":
            return ActionClassification(level: .safe, reason: "", summary: "")

        // --- Mouse/Keyboard (moderate — visible but not destructive) ---
        case "click_element", "mouse_move", "scroll", "drag", "type_text", "press_key":
            let summary = formatInputSummary(toolName, input)
            return ActionClassification(level: .moderate, reason: "Input simulation", summary: summary)

        // --- Shell commands — analyze content ---
        case "run_shell":
            let cmd = input["command"]?.stringValue ?? ""
            return classifyShellCommand(cmd)

        // --- AppleScript — analyze content ---
        case "run_applescript":
            let script = input["script"]?.stringValue ?? ""
            return classifyAppleScript(script)

        // --- File writes ---
        case "write_file":
            let path = input["path"]?.stringValue ?? ""
            return classifyFileWrite(path)

        // --- App control (moderate) ---
        case "activate_app", "open_app":
            let name = input["name"]?.stringValue ?? ""
            return ActionClassification(level: .moderate, reason: "Opening app", summary: "Open \(name)")

        case "open_url":
            let url = input["url"]?.stringValue ?? ""
            return ActionClassification(level: .moderate, reason: "Opening URL", summary: "Open \(url)")

        // --- Window management (safe) ---
        case "move_window", "resize_window":
            return ActionClassification(level: .safe, reason: "", summary: "")

        // --- Clipboard write (moderate) ---
        case "write_clipboard":
            return ActionClassification(level: .moderate, reason: "Writing to clipboard", summary: "Clipboard write")

        // --- Memory writes (safe — it's the agent's own memory) ---
        case "save_memory":
            return ActionClassification(level: .safe, reason: "", summary: "")

        // --- Self-modification ---
        case "edit_program", "edit_system_prompt":
            return ActionClassification(level: .dangerous, reason: "Modifying agent behavior", summary: "Self-modification: \(toolName)")

        case "modify_config":
            return ActionClassification(level: .moderate, reason: "Config change", summary: "Modify agent config")

        case "create_plugin":
            let name = input["name"]?.stringValue ?? ""
            return ActionClassification(level: .moderate, reason: "Creating plugin", summary: "Create plugin: \(name)")

        case "log_improvement":
            return ActionClassification(level: .safe, reason: "", summary: "")

        // --- Sub-agents (moderate — they execute actions) ---
        case "run_subagents":
            return ActionClassification(level: .moderate, reason: "Launching sub-agents", summary: "Parallel execution")

        // --- MCP install ---
        case "mcp_install":
            let pkg = input["package"]?.stringValue ?? ""
            return ActionClassification(level: .dangerous, reason: "Installing MCP server", summary: "Install MCP: \(pkg)")

        // --- Wait (safe) ---
        case "wait":
            return ActionClassification(level: .safe, reason: "", summary: "")

        // --- Task Scheduler ---
        case "list_tasks":
            return ActionClassification(level: .safe, reason: "", summary: "")
        case "schedule_task":
            let desc = input["description"]?.stringValue ?? ""
            return ActionClassification(level: .dangerous, reason: "Scheduling a recurring task", summary: "Schedule: \(desc)")
        case "cancel_task":
            let id = input["task_id"]?.stringValue ?? ""
            return ActionClassification(level: .moderate, reason: "Cancelling scheduled task", summary: "Cancel task: \(id)")
        case "run_task":
            let id = input["task_id"]?.stringValue ?? ""
            return ActionClassification(level: .moderate, reason: "Triggering scheduled task", summary: "Run task: \(id)")

        // --- Gateway ---
        case "configure_gateway":
            let platform = input["platform"]?.stringValue ?? ""
            return ActionClassification(level: .dangerous, reason: "Configuring gateway connection", summary: "Configure \(platform) gateway")
        case "import_gateway_config":
            return ActionClassification(level: .moderate, reason: "Importing gateway config", summary: "Import from OpenClaw")

        // --- Claude Code (dangerous — full code access) ---
        case "claude_code":
            let prompt = input["prompt"]?.stringValue ?? ""
            return ActionClassification(level: .dangerous, reason: "Delegating to Claude Code", summary: "Claude Code: \(String(prompt.prefix(80)))")

        // --- MCP tools (moderate by default) ---
        default:
            if toolName.hasPrefix("mcp_") {
                return ActionClassification(level: .moderate, reason: "MCP tool", summary: toolName)
            }
            return ActionClassification(level: .moderate, reason: "Unknown tool", summary: toolName)
        }
    }

    /// Ask user for approval. Returns true if approved.
    func requestApproval(toolName: String, classification: ActionClassification, input: [String: AnyCodable]) -> Bool {
        if autoApprove { return true }
        if classification.level == .safe { return true }
        if classification.level == .moderate && autoApprove { return true }

        // For moderate in normal mode — show but don't block
        if classification.level == .moderate { return true }

        // Dangerous — require explicit approval
        let icon = "⚠"
        print()
        print("  \u{001B}[1;33m\(icon) \(classification.reason)\u{001B}[0m")
        print("  \u{001B}[90m\(classification.summary)\u{001B}[0m")

        // Show details
        showActionDetails(toolName: toolName, input: input)

        print()
        print("  \u{001B}[1mApprove?\u{001B}[0m \u{001B}[90m(y)es / (n)o / (a)lways\u{001B}[0m ", terminator: "")
        fflush(stdout)

        // Read single character
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        var raw = oldTermios
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            let buf = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: cc_t.self)
            buf[Int(VMIN)] = 1
            buf[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        var c: UInt8 = 0
        read(STDIN_FILENO, &c, 1)

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &oldTermios)

        let ch = Character(UnicodeScalar(c))
        print(String(ch))  // echo the choice

        switch ch {
        case "y", "Y", "\r", "\n":
            return true
        case "a", "A":
            autoApprove = true
            printColored("  Auto-approve enabled for this session.", color: .yellow)
            return true
        case "n", "N":
            printColored("  Denied.", color: .red)
            return false
        default:
            printColored("  Denied (unknown input).", color: .red)
            return false
        }
    }

    // MARK: - Shell Command Classification

    private func classifyShellCommand(_ cmd: String) -> ActionClassification {
        let lower = cmd.lowercased().trimmingCharacters(in: .whitespaces)

        // Read-only commands — safe
        let safeCommands = ["ls", "cat", "head", "tail", "wc", "find", "grep", "rg",
                           "which", "whereis", "file", "stat", "du", "df", "pwd",
                           "echo", "date", "whoami", "hostname", "uname", "sw_vers",
                           "ps", "top", "env", "printenv", "defaults read", "system_profiler",
                           "mdls", "mdfind", "plutil -p", "sysctl", "ioreg"]
        for safe in safeCommands {
            if lower.hasPrefix(safe + " ") || lower == safe {
                return ActionClassification(level: .safe, reason: "", summary: "")
            }
        }

        // Package managers, installers — dangerous
        let dangerousPatterns = [
            "sudo", "rm -rf", "rm -r /", "mkfs", "dd if=", "diskutil erase",
            ":(){ :|:& };:", "chmod -R 777", "> /dev/", "curl | sh", "curl | bash",
            "wget | sh", "pip install", "npm install -g", "brew install",
            "launchctl", "defaults write", "csrutil", "nvram", "bless",
            "kill -9", "killall", "pkill", "shutdown", "reboot", "halt"
        ]
        for pattern in dangerousPatterns {
            if lower.contains(pattern) {
                return ActionClassification(level: .dangerous,
                    reason: "Potentially destructive shell command",
                    summary: "$ \(String(cmd.prefix(100)))")
            }
        }

        // File modifications — moderate
        let moderatePatterns = ["rm ", "mv ", "cp ", "mkdir", "touch", "chmod", "chown",
                               "sed -i", "tee ", "> ", ">> ", "npm ", "npx ", "pip ",
                               "git push", "git reset", "git checkout",
                               "open -a", "osascript"]
        for pattern in moderatePatterns {
            if lower.contains(pattern) {
                return ActionClassification(level: .moderate,
                    reason: "Shell command modifying files",
                    summary: "$ \(String(cmd.prefix(100)))")
            }
        }

        // Network commands — moderate
        let networkPatterns = ["curl", "wget", "ssh", "scp", "rsync", "git clone", "git pull"]
        for pattern in networkPatterns {
            if lower.contains(pattern) {
                return ActionClassification(level: .moderate,
                    reason: "Network operation",
                    summary: "$ \(String(cmd.prefix(100)))")
            }
        }

        // Default: moderate (we can't know all commands)
        return ActionClassification(level: .moderate, reason: "Shell command", summary: "$ \(String(cmd.prefix(80)))")
    }

    private func classifyAppleScript(_ script: String) -> ActionClassification {
        let lower = script.lowercased()

        // Keystroke/key code with system events — moderate (input simulation)
        if lower.contains("keystroke") || lower.contains("key code") || lower.contains("click") {
            return ActionClassification(level: .moderate, reason: "AppleScript input simulation",
                                       summary: "AppleScript: \(String(script.prefix(60)))")
        }

        // System preferences, security — dangerous
        if lower.contains("system preferences") || lower.contains("system settings") ||
           lower.contains("security") || lower.contains("keychain") || lower.contains("password") {
            return ActionClassification(level: .dangerous, reason: "AppleScript accessing sensitive settings",
                                       summary: "AppleScript: system/security access")
        }

        return ActionClassification(level: .moderate, reason: "AppleScript execution",
                                    summary: "AppleScript: \(String(script.prefix(60)))")
    }

    private func classifyFileWrite(_ path: String) -> ActionClassification {
        let expanded = (path as NSString).expandingTildeInPath

        // System paths — dangerous
        let dangerousPaths = ["/etc/", "/usr/", "/System/", "/Library/", "/bin/", "/sbin/",
                              "/.ssh/", "/.gnupg/", "/.env", "/credentials", "/config.json"]
        for dp in dangerousPaths {
            if expanded.contains(dp) {
                return ActionClassification(level: .dangerous, reason: "Writing to sensitive path",
                                           summary: "Write: \(path)")
            }
        }

        return ActionClassification(level: .moderate, reason: "File write", summary: "Write: \(path)")
    }

    // MARK: - Display Helpers

    private func showActionDetails(toolName: String, input: [String: AnyCodable]) {
        switch toolName {
        case "run_shell":
            if let cmd = input["command"]?.stringValue {
                print("  \u{001B}[90m$ \(cmd)\u{001B}[0m")
            }
        case "run_applescript":
            if let script = input["script"]?.stringValue {
                let preview = String(script.prefix(200))
                print("  \u{001B}[90m\(preview)\u{001B}[0m")
            }
        case "write_file":
            if let path = input["path"]?.stringValue {
                print("  \u{001B}[90mPath: \(path)\u{001B}[0m")
            }
        case "mcp_install":
            if let pkg = input["package"]?.stringValue {
                print("  \u{001B}[90mPackage: \(pkg)\u{001B}[0m")
            }
            if let name = input["name"]?.stringValue {
                print("  \u{001B}[90mName: \(name)\u{001B}[0m")
            }
        default:
            let desc = input.map { "\($0.key)=\($0.value.value)" }.joined(separator: ", ")
            if !desc.isEmpty {
                print("  \u{001B}[90m\(String(desc.prefix(200)))\u{001B}[0m")
            }
        }
    }

    private func formatInputSummary(_ tool: String, _ input: [String: AnyCodable]) -> String {
        switch tool {
        case "click_element":
            let x = input["x"]?.intValue ?? 0
            let y = input["y"]?.intValue ?? 0
            return "Click at (\(x), \(y))"
        case "type_text":
            let text = input["text"]?.stringValue ?? ""
            return "Type: \(String(text.prefix(40)))"
        case "press_key":
            return "Press: \(input["key"]?.stringValue ?? "")"
        default:
            return tool
        }
    }
}
