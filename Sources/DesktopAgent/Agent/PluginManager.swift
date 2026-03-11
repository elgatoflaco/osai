import Foundation

// MARK: - Plugin / Specialized Agent System

/// A plugin is a reusable agent configuration stored as a markdown file
/// with frontmatter for settings and body for the system prompt.
struct AgentPlugin {
    let name: String
    let description: String
    let model: String?
    let tools: [String]?  // nil = all tools, or list of specific tool names
    let systemPrompt: String
    let filePath: String

    static let pluginDir = AgentConfigFile.configDir + "/plugins"

    static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: pluginDir, withIntermediateDirectories: true)
    }
}

final class PluginManager {

    // MARK: - List plugins

    static func listPlugins() -> [AgentPlugin] {
        AgentPlugin.ensureDir()
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: AgentPlugin.pluginDir) else { return [] }
        return items
            .filter { $0.hasSuffix(".md") }
            .compactMap { loadPlugin(name: String($0.dropLast(3))) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Load plugin

    static func loadPlugin(name: String) -> AgentPlugin? {
        let path = (AgentPlugin.pluginDir as NSString).appendingPathComponent("\(name).md")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parsePlugin(content: content, filePath: path, fallbackName: name)
    }

    // MARK: - Save plugin

    static func savePlugin(_ plugin: AgentPlugin) throws {
        AgentPlugin.ensureDir()
        let path = (AgentPlugin.pluginDir as NSString).appendingPathComponent("\(plugin.name).md")

        var content = "---\n"
        content += "name: \(plugin.name)\n"
        content += "description: \(plugin.description)\n"
        if let model = plugin.model { content += "model: \(model)\n" }
        if let tools = plugin.tools { content += "tools: \(tools.joined(separator: ", "))\n" }
        content += "---\n\n"
        content += plugin.systemPrompt

        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Delete plugin

    static func deletePlugin(name: String) throws {
        let path = (AgentPlugin.pluginDir as NSString).appendingPathComponent("\(name).md")
        try FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Create built-in plugins

    static func installBuiltins() {
        AgentPlugin.ensureDir()

        let builtins: [(name: String, description: String, prompt: String)] = [
            (
                "web-researcher",
                "Research topics on the web using browser automation",
                """
                You are a web research agent. Your job is to find information on the web.

                Strategy:
                1. Use run_shell with `curl` for simple pages, or open_url + take_screenshot for complex ones
                2. Use Chrome DevTools MCP if available for full browser control
                3. Extract and summarize the relevant information
                4. Always cite your sources with URLs

                For JavaScript-heavy sites, prefer using the browser (screenshots + clicking).
                For simple content, prefer curl + parsing.
                """
            ),
            (
                "file-analyzer",
                "Analyze files and directories, create reports",
                """
                You are a file analysis agent. Your job is to read, analyze, and summarize files.

                Strategy:
                1. Use list_directory to understand the structure
                2. Use read_file to read individual files
                3. Use run_shell for complex analysis (wc, grep, awk, etc.)
                4. Provide structured summaries with key findings

                When analyzing multiple files, work through them systematically.
                For code: identify languages, patterns, dependencies.
                For documents: extract key information, dates, amounts.
                For data: identify schemas, row counts, patterns.
                """
            ),
            (
                "app-automator",
                "Automate macOS applications with AppleScript and accessibility",
                """
                You are a macOS app automation specialist. You control desktop apps.

                Strategy:
                1. ALWAYS screenshot first to see the current state
                2. Use get_ui_elements to map the interface
                3. Prefer AppleScript for apps that support it well (Safari, Mail, Finder, Notes, Pages, Numbers, Keynote, Calendar, Reminders)
                4. Use accessibility APIs + click/type for apps that don't support AppleScript
                5. Use keyboard shortcuts when they're faster
                6. After every action, screenshot to verify

                For System Events scripting:
                ```applescript
                tell application "System Events"
                    tell process "AppName"
                        click menu item "Item" of menu "Menu" of menu bar 1
                    end tell
                end tell
                ```
                """
            ),
            (
                "coder",
                "Write, edit, and debug code",
                """
                You are a coding agent. You write and modify code files.

                Strategy:
                1. Read existing files to understand the codebase
                2. Use run_shell for: git, npm, pip, cargo, swift, etc.
                3. Use write_file to create/modify files
                4. Use run_shell to compile, test, and run code
                5. Fix errors iteratively based on compiler/runtime output

                Always read before writing. Understand the existing patterns.
                Write clean, minimal code. Test after changes.
                """
            ),
        ]

        for builtin in builtins {
            let path = (AgentPlugin.pluginDir as NSString).appendingPathComponent("\(builtin.name).md")
            if FileManager.default.fileExists(atPath: path) { continue }

            let plugin = AgentPlugin(
                name: builtin.name,
                description: builtin.description,
                model: nil,
                tools: nil,
                systemPrompt: builtin.prompt,
                filePath: path
            )
            try? savePlugin(plugin)
        }
    }

    // MARK: - Parse plugin from markdown with frontmatter

    private static func parsePlugin(content: String, filePath: String, fallbackName: String) -> AgentPlugin? {
        var name = fallbackName
        var description = ""
        var model: String? = nil
        var tools: [String]? = nil
        var systemPrompt = content

        // Parse YAML-like frontmatter
        if content.hasPrefix("---\n") {
            let parts = content.components(separatedBy: "---\n")
            if parts.count >= 3 {
                let frontmatter = parts[1]
                systemPrompt = parts.dropFirst(2).joined(separator: "---\n").trimmingCharacters(in: .whitespacesAndNewlines)

                for line in frontmatter.components(separatedBy: "\n") {
                    let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard kv.count == 2 else { continue }
                    switch kv[0] {
                    case "name": name = kv[1]
                    case "description": description = kv[1]
                    case "model": model = kv[1]
                    case "tools": tools = kv[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    default: break
                    }
                }
            }
        }

        return AgentPlugin(
            name: name,
            description: description,
            model: model,
            tools: tools,
            systemPrompt: systemPrompt,
            filePath: filePath
        )
    }
}
