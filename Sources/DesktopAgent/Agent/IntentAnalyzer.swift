import Foundation

// MARK: - Intent Analyzer
// Analyzes user intent from natural language and routes to optimal tools.
// Detects the frontmost application and adjusts tool selection accordingly.

final class IntentAnalyzer {

    // MARK: - Types

    /// High-level intent categories
    enum IntentCategory: String, Codable {
        case fileOperation      // Read, write, find, organize files
        case appControl         // Open, close, switch apps
        case guiInteraction     // Click, type, navigate UI
        case communication      // Email, messages, chat
        case information        // Search, lookup, calculate
        case automation         // Schedule, script, workflow
        case system             // Settings, permissions, config
        case creative           // Design, edit media, generate content
        case development        // Code, build, test, deploy
        case unknown
    }

    /// Analyzed intent with confidence and tool recommendations
    struct Intent {
        let category: IntentCategory
        let confidence: Double          // 0.0 - 1.0
        let suggestedTools: [String]    // Ordered by preference
        let preferShell: Bool           // Should prefer CLI over GUI?
        let preferAppleScript: Bool     // Should prefer AppleScript?
        let appContext: String?         // Relevant app for this intent
        let keywords: [String]          // Matched keywords
    }

    /// App-specific tool preferences
    struct AppToolProfile {
        let appName: String
        let preferredTools: [String]      // Tools that work best with this app
        let hasAppleScriptSupport: Bool
        let commonActions: [String: String] // "save" → "command+s", etc.
    }

    // MARK: - Intent Patterns

    /// Keyword patterns mapped to intent categories
    private static let intentPatterns: [(keywords: [String], category: IntentCategory, tools: [String], preferShell: Bool, preferAS: Bool)] = [
        // File operations
        (["read file", "open file", "show file", "cat ", "contents of", "what's in"],
         .fileOperation, ["read_file", "run_shell"], true, false),
        (["write file", "create file", "save to", "write to", "generate file"],
         .fileOperation, ["write_file", "run_shell"], true, false),
        (["find file", "search file", "locate", "where is", "look for file"],
         .fileOperation, ["spotlight_search", "run_shell"], true, false),
        (["list files", "show files", "directory", "folder contents", "ls"],
         .fileOperation, ["list_directory", "run_shell"], true, false),
        (["move file", "rename file", "copy file", "delete file", "remove file"],
         .fileOperation, ["run_shell"], true, false),

        // App control
        (["open app", "launch", "start app", "run app"],
         .appControl, ["open_app", "run_shell"], false, false),
        (["close app", "quit app", "kill", "force quit"],
         .appControl, ["run_applescript", "run_shell"], false, true),
        (["switch to", "go to", "activate", "bring up", "show me"],
         .appControl, ["activate_app", "open_app"], false, false),

        // GUI interaction
        (["click", "press button", "tap", "select"],
         .guiInteraction, ["click_element", "get_ui_elements", "take_screenshot"], false, false),
        (["type", "enter text", "fill in", "write in"],
         .guiInteraction, ["type_text", "click_element"], false, false),
        (["scroll", "scroll down", "scroll up"],
         .guiInteraction, ["scroll", "take_screenshot"], false, false),
        (["screenshot", "what's on screen", "show screen", "see the screen"],
         .guiInteraction, ["take_screenshot", "get_ui_elements"], false, false),
        (["drag", "move to", "resize"],
         .guiInteraction, ["drag", "move_window", "resize_window"], false, false),

        // Communication
        (["email", "mail", "send email", "check email", "inbox", "correo", "gmail"],
         .communication, ["run_shell", "run_applescript"], true, true),
        (["message", "text", "imessage", "sms", "whatsapp"],
         .communication, ["run_applescript"], false, true),
        (["calendar", "event", "meeting", "schedule meeting", "appointment", "agenda"],
         .communication, ["run_shell", "run_applescript"], true, true),
        (["slack", "discord", "teams"],
         .communication, ["run_applescript", "open_app"], false, true),

        // Information
        (["search", "google", "look up", "find info", "what is", "who is", "how to"],
         .information, ["open_url", "run_shell"], true, false),
        (["calculate", "math", "convert", "how much", "how many"],
         .information, ["run_shell"], true, false),
        (["weather", "time", "date"],
         .information, ["run_shell", "run_applescript"], true, false),

        // Automation
        (["schedule", "remind", "timer", "alarm", "every day", "recurring"],
         .automation, ["schedule_task", "run_applescript"], false, true),
        (["automate", "script", "workflow", "batch", "repeat"],
         .automation, ["run_shell", "run_applescript", "schedule_task"], true, false),

        // System
        (["settings", "preferences", "system preferences", "config"],
         .system, ["run_applescript", "open_app"], false, true),
        (["volume", "brightness", "wifi", "bluetooth", "dark mode"],
         .system, ["run_applescript", "run_shell"], false, true),
        (["install", "update", "upgrade", "brew", "npm"],
         .system, ["run_shell"], true, false),

        // Creative
        (["design", "figma", "illustrator", "photoshop", "sketch"],
         .creative, ["run_applescript", "open_app", "take_screenshot"], false, true),
        (["image", "photo", "picture", "draw", "create image"],
         .creative, ["run_shell", "write_file", "open_app"], true, false),
        (["video", "audio", "music", "record"],
         .creative, ["run_applescript", "open_app", "run_shell"], false, true),

        // Development
        (["code", "program", "function", "class", "implement", "refactor", "debug"],
         .development, ["claude_code", "read_file", "run_shell"], true, false),
        (["build", "compile", "test", "run tests", "npm", "cargo", "swift build"],
         .development, ["run_shell", "claude_code"], true, false),
        (["git", "commit", "push", "pull", "branch", "merge"],
         .development, ["run_shell", "claude_code"], true, false),
        (["deploy", "publish", "release"],
         .development, ["run_shell", "claude_code"], true, false),
    ]

    // MARK: - App Profiles

    /// Known app profiles for optimized tool selection
    private static let appProfiles: [String: AppToolProfile] = [
        "finder": AppToolProfile(
            appName: "Finder", preferredTools: ["run_applescript", "run_shell"],
            hasAppleScriptSupport: true,
            commonActions: ["new_folder": "command+shift+n", "go_to": "command+shift+g", "info": "command+i"]
        ),
        "safari": AppToolProfile(
            appName: "Safari", preferredTools: ["run_applescript", "open_url"],
            hasAppleScriptSupport: true,
            commonActions: ["new_tab": "command+t", "close_tab": "command+w", "address_bar": "command+l"]
        ),
        "chrome": AppToolProfile(
            appName: "Google Chrome", preferredTools: ["run_applescript", "open_url"],
            hasAppleScriptSupport: true,
            commonActions: ["new_tab": "command+t", "close_tab": "command+w", "address_bar": "command+l"]
        ),
        "terminal": AppToolProfile(
            appName: "Terminal", preferredTools: ["run_shell"],
            hasAppleScriptSupport: true,
            commonActions: ["new_tab": "command+t", "clear": "command+k"]
        ),
        "notes": AppToolProfile(
            appName: "Notes", preferredTools: ["run_applescript"],
            hasAppleScriptSupport: true,
            commonActions: ["new_note": "command+n", "find": "command+f"]
        ),
        "reminders": AppToolProfile(
            appName: "Reminders", preferredTools: ["run_applescript"],
            hasAppleScriptSupport: true,
            commonActions: ["new_reminder": "command+n"]
        ),
        "mail": AppToolProfile(
            appName: "Mail", preferredTools: ["run_applescript", "run_shell"],
            hasAppleScriptSupport: true,
            commonActions: ["new_message": "command+n", "reply": "command+r"]
        ),
        "messages": AppToolProfile(
            appName: "Messages", preferredTools: ["run_applescript"],
            hasAppleScriptSupport: true,
            commonActions: ["new_message": "command+n"]
        ),
        "calendar": AppToolProfile(
            appName: "Calendar", preferredTools: ["run_applescript", "run_shell"],
            hasAppleScriptSupport: true,
            commonActions: ["new_event": "command+n", "today": "command+t"]
        ),
        "music": AppToolProfile(
            appName: "Music", preferredTools: ["run_applescript"],
            hasAppleScriptSupport: true,
            commonActions: ["play_pause": "space", "next": "command+right"]
        ),
        "xcode": AppToolProfile(
            appName: "Xcode", preferredTools: ["run_shell", "claude_code"],
            hasAppleScriptSupport: false,
            commonActions: ["build": "command+b", "run": "command+r", "test": "command+u"]
        ),
        "vscode": AppToolProfile(
            appName: "Visual Studio Code", preferredTools: ["run_shell", "claude_code"],
            hasAppleScriptSupport: false,
            commonActions: ["save": "command+s", "terminal": "ctrl+`", "command_palette": "command+shift+p"]
        ),
    ]

    // MARK: - Analysis

    /// Analyze user input and return detected intent
    func analyze(input: String, frontmostApp: String? = nil) -> Intent {
        let lower = input.lowercased()
        var bestMatch: (category: IntentCategory, confidence: Double, tools: [String],
                       preferShell: Bool, preferAS: Bool, keywords: [String])
            = (.unknown, 0, [], false, false, [])

        // Score each pattern
        for pattern in Self.intentPatterns {
            var matchedKeywords: [String] = []
            for keyword in pattern.keywords {
                if lower.contains(keyword.lowercased()) {
                    matchedKeywords.append(keyword)
                }
            }

            if matchedKeywords.isEmpty { continue }

            // Confidence: ratio of keywords matched + bonus for longer matches
            let keywordScore = Double(matchedKeywords.count) / Double(pattern.keywords.count)
            let lengthBonus = matchedKeywords.reduce(0.0) { $0 + Double($1.count) } / Double(max(lower.count, 1)) * 0.3
            let confidence = min(keywordScore + lengthBonus, 1.0)

            if confidence > bestMatch.confidence {
                bestMatch = (pattern.category, confidence, pattern.tools,
                            pattern.preferShell, pattern.preferAS, matchedKeywords)
            }
        }

        // Adjust based on frontmost app context
        var suggestedTools = bestMatch.tools
        var appContext = frontmostApp
        var preferAS = bestMatch.preferAS

        if let app = frontmostApp?.lowercased() {
            for (key, profile) in Self.appProfiles {
                if app.contains(key) {
                    // Boost tools that work well with this app
                    let profileTools = profile.preferredTools.filter { !suggestedTools.contains($0) }
                    suggestedTools = profile.preferredTools + suggestedTools.filter { !profile.preferredTools.contains($0) }
                    if profile.hasAppleScriptSupport { preferAS = true }
                    appContext = profile.appName
                    _ = profileTools // silence unused warning
                    break
                }
            }
        }

        return Intent(
            category: bestMatch.category,
            confidence: bestMatch.confidence,
            suggestedTools: suggestedTools,
            preferShell: bestMatch.preferShell,
            preferAppleScript: preferAS,
            appContext: appContext,
            keywords: bestMatch.keywords
        )
    }

    /// Get the app profile for a given app name
    func getAppProfile(appName: String) -> AppToolProfile? {
        let lower = appName.lowercased()
        for (key, profile) in Self.appProfiles {
            if lower.contains(key) { return profile }
        }
        return nil
    }

    /// Get keyboard shortcut for a common action in an app
    func getShortcut(appName: String, action: String) -> String? {
        guard let profile = getAppProfile(appName: appName) else { return nil }
        return profile.commonActions[action.lowercased()]
    }

    /// Build a context hint for the system prompt based on intent analysis
    func buildIntentContext(input: String, frontmostApp: String?) -> String {
        let intent = analyze(input: input, frontmostApp: frontmostApp)

        guard intent.confidence > 0.3 else { return "" }

        var context = "\n\n## INTENT ANALYSIS:"
        context += "\nDetected intent: \(intent.category.rawValue) (confidence: \(String(format: "%.0f", intent.confidence * 100))%)"

        if !intent.suggestedTools.isEmpty {
            context += "\nSuggested tools (in order): \(intent.suggestedTools.prefix(5).joined(separator: ", "))"
        }

        if intent.preferShell {
            context += "\nPrefer shell/CLI approach over GUI for this task."
        }
        if intent.preferAppleScript {
            context += "\nAppleScript is recommended for this task."
        }

        if let app = intent.appContext {
            context += "\nRelevant app: \(app)"
            if let profile = getAppProfile(appName: app) {
                let shortcuts = profile.commonActions.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                if !shortcuts.isEmpty {
                    context += "\nKnown shortcuts: \(shortcuts)"
                }
            }
        }

        return context
    }
}
