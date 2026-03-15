import Foundation
import CoreGraphics

// MARK: - Errors

enum AgentError: Error, CustomStringConvertible {
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case noAPIKey
    case permissionDenied(String)
    case toolError(String)

    var description: String {
        switch self {
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .noAPIKey: return "No API key set. Use /config set-key <provider> <key> or export the appropriate env var."
        case .permissionDenied(let msg): return "Permission denied: \(msg)"
        case .toolError(let msg): return "Tool error: \(msg)"
        }
    }
}

// MARK: - Agent Types

enum DriverType: String, CaseIterable {
    case applescript = "applescript"
    case accessibility = "accessibility"
    case keyboard = "keyboard"
    case vision = "vision"
    case shell = "shell"
}

struct ToolResult {
    let success: Bool
    let output: String
    let screenshot: Data?
}

struct AppInfo {
    let name: String
    let pid: pid_t
    let bundleId: String?
    let isActive: Bool
}

struct UIElement {
    let role: String
    let title: String?
    let value: String?
    let position: CGPoint?
    let size: CGSize?
    let children: [UIElement]
    let actions: [String]

    var description: String {
        var desc = "[\(role)]"
        if let title = title { desc += " title=\"\(title)\"" }
        if let value = value, !value.isEmpty { desc += " value=\"\(String(value.prefix(100)))\"" }
        if let pos = position, let sz = size {
            let cx = Int(pos.x + sz.width / 2)
            let cy = Int(pos.y + sz.height / 2)
            desc += " pos=(\(Int(pos.x)),\(Int(pos.y))) size=\(Int(sz.width))x\(Int(sz.height)) center=(\(cx),\(cy))"
        }
        if !actions.isEmpty { desc += " actions=[\(actions.joined(separator: ","))]" }
        return desc
    }
}

struct WindowInfo {
    let ownerName: String
    let name: String?
    let pid: pid_t
    let bounds: CGRect
    let windowID: UInt32
    let isOnScreen: Bool

    var description: String {
        var desc = "\(ownerName)"
        if let name = name, !name.isEmpty { desc += " - \"\(name)\"" }
        desc += " (pid: \(pid), wid: \(windowID))"
        desc += " bounds=(\(Int(bounds.origin.x)),\(Int(bounds.origin.y)) \(Int(bounds.width))x\(Int(bounds.height)))"
        return desc
    }
}

struct ScreenRegion {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

// MARK: - Configuration

struct AgentConfig {
    let apiKey: String
    let model: String
    let maxTokens: Int
    let systemPrompt: String
    let verbose: Bool
    let maxScreenshotWidth: Int
    let baseURL: String
    let apiFormat: String  // "anthropic" or "openai"
    let providerId: String
    let profileName: String?
    let fallbackModels: [String]  // "provider/model" strings to try when primary fails

    static func load() -> AgentConfig {
        let fileConfig = AgentConfigFile.load()
        let verbose = ProcessInfo.processInfo.environment["DESKTOP_AGENT_VERBOSE"] == "1"

        // Determine active model: CLI arg > config file > env var > default
        var modelString = "anthropic/claude-sonnet-4-20250514"
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--model"), idx + 1 < args.count {
            modelString = args[idx + 1]
        } else if let active = fileConfig.activeModel {
            modelString = active
        } else if let envModel = ProcessInfo.processInfo.environment["DESKTOP_AGENT_MODEL"] {
            modelString = envModel
        }

        // Resolve provider and model
        let resolved = AIProvider.resolve(modelString: modelString)
        let provider = resolved?.provider ?? AIProvider.known[0]
        let model = resolved?.model ?? modelString

        // Get API key: config file > env var
        var apiKey = fileConfig.getAPIKey(provider: provider.id) ?? ""
        if apiKey.isEmpty {
            // Try env vars as fallback
            let envKeys: [String: String] = [
                "anthropic": "ANTHROPIC_API_KEY",
                "openai": "OPENAI_API_KEY",
                "google": "GOOGLE_API_KEY",
                "groq": "GROQ_API_KEY",
                "mistral": "MISTRAL_API_KEY",
                "openrouter": "OPENROUTER_API_KEY",
                "deepseek": "DEEPSEEK_API_KEY",
                "xai": "XAI_API_KEY",
            ]
            if let envName = envKeys[provider.id] {
                apiKey = ProcessInfo.processInfo.environment[envName] ?? ""
            }
        }

        let baseURL = fileConfig.getBaseURL(provider: provider.id) ?? provider.defaultBaseURL
        let maxTokens = fileConfig.maxTokens ?? Int(ProcessInfo.processInfo.environment["DESKTOP_AGENT_MAX_TOKENS"] ?? "8192") ?? 8192

        // Install default program.md and profile templates if needed
        AgentProgram.installDefault()
        ProfileManager.installDefaults()

        // Determine active profile: CLI arg > none
        var profileName: String? = nil
        if let idx = args.firstIndex(of: "--profile"), idx + 1 < args.count {
            profileName = args[idx + 1]
        }

        // Build system prompt: custom override > default + program.md
        let systemPrompt: String
        if let custom = AgentProgram.loadCustomSystemPrompt() {
            systemPrompt = custom
        } else {
            let defaultPrompt = """
            You are a UNIVERSAL AI ASSISTANT with FULL control over a macOS computer. You can do ANYTHING the user asks.

            ## CRITICAL — EFFICIENCY RULES:

            **BATCH your tool calls!** You can call MULTIPLE tools in a SINGLE response. ALWAYS do this:
            - ✅ Call `take_screenshot` + `get_ui_elements` together in one turn
            - ✅ Call `click_element` + `wait` together, then `take_screenshot` on the next turn
            - ✅ Call `run_shell` for multiple independent commands using `run_subagents`
            - ❌ NEVER do one tool call per turn when you could batch them
            - ❌ NEVER screenshot after every single click — batch actions, then verify once

            **PLAN before acting.** For complex tasks, think through ALL the steps first, then execute efficiently:
            - Group related actions into batches
            - Use `run_subagents` for parallel independent work
            - Minimize screenshot→think→act cycles (aim for 2-3, not 20)

            **Target: Complete most tasks in 5-10 iterations, not 30.**

            ## CHOOSE THE LIGHTEST TOOL FIRST:

            **GOLDEN RULE: If you can do it with AppleScript or shell, DON'T open the app and screenshot.**
            Screenshots + GUI clicks cost tokens and time. AppleScript/shell is instant and free.

            **Reminders, Contacts, Notes, Messages, Music, Finder:**
            → ALWAYS use `run_applescript` first. These apps have full AppleScript support.
            → Example: Create reminder → `tell app "Reminders" to make new reminder with properties {name:"X", due date:...}`
            → NEVER open these apps just to take screenshots and click around.

            **Email → use the `send_email` tool** (NEVER shell scripts, NEVER Mail.app, NEVER Python):
            → Call: send_email(to: "email@example.com", subject: "Subject", body: "Body text")
            → Triage inbox: run_shell with `gws gmail +triage`
            → CRITICAL: Do NOT use run_shell with export/echo/python to send email. Use the send_email tool.
            **Calendar → use `gws calendar`** for events (see program.md for exact syntax).
            **Web pages → use `mcp_chrome_*` tools** to control the user's real Chrome browser.
            → `mcp_chrome_navigate_page` to open URLs, `mcp_chrome_take_screenshot` for captures.

            **FILE/DATA** → `run_shell`, `read_file`, `write_file`. NO screenshots.
            **GUI/DESKTOP (when GUI is truly needed):**
            → Screenshot+UI elements in ONE call → batch clicks → verify once.
            → Only use GUI for apps that DON'T support AppleScript well.
            **CREATIVE (Illustrator, Figma, Photoshop, etc.):**
            → Generate content as FILE first (SVG, .jsx ExtendScript), then open/execute it.
            → GUI automation is LAST RESORT, only for simple actions (save, export, menus).
            **WEB** → Use `mcp_chrome_*` tools for browsing. `run_shell` with curl for APIs.
            **DEVELOPMENT** → `run_shell` for git/npm/build. `write_file`/`read_file` for code.
            **COMMUNICATION** → `send_email` tool for email (NEVER shell). AppleScript for Messages.

            **COST AWARENESS:** Every API call costs money. Each screenshot ≈ 1K+ tokens.
            Prefer: shell (0 tokens) > AppleScript (0 tokens) > read_file > screenshot (expensive).

            ## MCP — CAPABILITY EXPANSION:
            You can install new capabilities autonomously:
            1. Check if `mcp_` tools already exist in your tool list
            2. Use `mcp_search` to find MCP servers on npm → `mcp_install` to add them
            3. Or tell user: `/mcp add <name> <command>`

            ## ABOUT YOURSELF:
            Desktop Agent — native Swift CLI at ~/.desktop-agent/
            Config: ~/.desktop-agent/config.json | Plugins: plugins/ | Memory: memory/

            ## GUI STRATEGY (when GUI is truly needed):
            1. `take_screenshot` + `get_ui_elements` → ONE turn to see and map the UI
            2. Batch clicks/types → multiple actions, minimal turns
            3. Verify with ONE final screenshot
            Fallbacks: AppleScript menus, keyboard shortcuts (`press_key`), `open -a`

            ## SELF-IMPROVEMENT:
            `read_program`/`edit_program`, `edit_system_prompt`, `create_plugin`, `modify_config`
            Track with `log_improvement`/`read_improvement_log`

            ## USER ASIDES:
            The user can send you messages WHILE you're working (marked as 💬 [USER ASIDE]).
            These are mid-task instructions — read them carefully and adjust your approach.
            They might be: corrections, additional context, priority changes, or questions about progress.
            When you see an aside, briefly acknowledge it and adapt your next actions accordingly.

            ## SKILLS — FOLLOW THEM STRICTLY:
            Skills are knowledge files that activate automatically when the user's input matches trigger keywords.
            When a skill is active, its instructions appear in your system prompt under "ACTIVE SKILLS".
            **Follow skill instructions PRECISELY — they contain the EXACT syntax for CLI tools.**
            **If a skill says to use a CLI command, ALWAYS use that command. NEVER fall back to GUI.**
            **If a CLI command fails (403, error, etc.), TELL THE USER the error and how to fix it.**
            **NEVER open a browser/app as fallback when a CLI approach fails. Report the error instead.**
            Skills dir: ~/.desktop-agent/skills/

            ## TASK SCHEDULING:
            You can schedule yourself to run tasks automatically using `schedule_task`.
            Tasks use macOS launchd — they run `osai "command"` at specified times.
            Schedule types: once (specific time), recurring (daily HH:MM), interval (every N min), cron.
            Use this for: daily briefings, periodic checks, timed reminders, automated workflows.
            Always confirm with the user before scheduling. Use `list_tasks` to show existing tasks.

            ## PLANNING
            For complex tasks (multi-step, involving multiple tools, or requiring coordination):
            1. First, output a brief plan with numbered steps
            2. Then execute each step, marking progress
            3. If a step fails, revise the plan

            Format your plan as:
            📋 Plan:
            1. [step description]
            2. [step description]
            3. [step description]

            Then as you work:
            ✅ Step 1 complete: [what was done]
            ⏳ Step 2: [working on...]

            For simple tasks (single tool call, quick answers), skip the plan and just do it.

            ## SAFETY:
            Dangerous actions → approval system prompts user. YOLO mode (/yolo) skips confirmations.
            NEVER type passwords or credentials.
            """

            // Append program.md content
            if let program = AgentProgram.load() {
                systemPrompt = defaultPrompt + "\n\n## USER PROGRAM (program.md):\n" + program
            } else {
                systemPrompt = defaultPrompt
            }
        }

        // Append profile content to system prompt
        var finalPrompt = systemPrompt
        if let name = profileName, let profileContent = ProfileManager.load(name: name) {
            finalPrompt += "\n\n## ACTIVE PROFILE (\(name)):\n" + profileContent
        }

        return AgentConfig(
            apiKey: apiKey,
            model: model,
            maxTokens: maxTokens,
            systemPrompt: finalPrompt,
            verbose: verbose,
            maxScreenshotWidth: fileConfig.maxScreenshotWidth ?? 1280,
            baseURL: baseURL,
            apiFormat: provider.format,
            providerId: provider.id,
            profileName: profileName,
            fallbackModels: fileConfig.fallbackModels ?? []
        )
    }
}
