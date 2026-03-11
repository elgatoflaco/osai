import Foundation

// MARK: - Skill System
//
// Skills are persistent knowledge files that teach the agent HOW to use specific
// tools, apps, or MCPs. Unlike plugins (which run in isolation), skills are
// injected into the main system prompt when relevant keywords are detected.
//
// ~/.desktop-agent/skills/
//   gws.md          → Google Workspace (gmail, calendar, drive)
//   figma.md        → Figma design automation
//   git.md          → Git workflow preferences
//
// Each skill is a markdown file with YAML frontmatter:
//   ---
//   name: Google Workspace
//   triggers: [email, correo, gmail, calendar, drive]
//   mcp: gws
//   ---
//   Instructions for the agent...

struct Skill {
    let name: String
    let description: String
    let triggers: [String]       // Keywords that activate this skill
    let mcp: String?             // Required MCP server name (auto-started if needed)
    let tools: [String]?         // Specific tool names to highlight
    let instructions: String     // Full instructions for the agent
    let filePath: String
}

final class SkillManager {
    static let skillsDir = NSHomeDirectory() + "/.desktop-agent/skills"

    // MARK: - Load Skills

    static func listSkills() -> [Skill] {
        let fm = FileManager.default
        ensureDir()
        guard let files = try? fm.contentsOfDirectory(atPath: skillsDir) else { return [] }
        return files.filter { $0.hasSuffix(".md") }.compactMap { loadSkill(path: skillsDir + "/" + $0) }
    }

    static func loadSkill(name: String) -> Skill? {
        let path = skillsDir + "/\(name).md"
        return loadSkill(path: path)
    }

    static func loadSkill(path: String) -> Skill? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parseSkill(content: content, filePath: path)
    }

    // MARK: - Match Skills to User Input

    /// Find all skills whose triggers match the user's input
    static func matchSkills(for input: String, allSkills: [Skill]? = nil) -> [Skill] {
        let skills = allSkills ?? listSkills()
        let lower = input.lowercased()

        return skills.filter { skill in
            skill.triggers.contains { trigger in
                lower.contains(trigger.lowercased())
            }
        }
    }

    /// Build context string for matched skills to inject into system prompt
    static func buildSkillContext(for input: String, allSkills: [Skill]? = nil) -> String {
        let matched = matchSkills(for: input, allSkills: allSkills)
        if matched.isEmpty { return "" }

        var context = "\n\n## ACTIVE SKILLS:\n"
        for skill in matched {
            context += "\n### Skill: \(skill.name)\n"
            if let mcp = skill.mcp {
                context += "MCP Server: \(mcp) (ensure it's running)\n"
            }
            context += skill.instructions + "\n"
        }
        return context
    }

    // MARK: - Save/Delete Skills

    static func saveSkill(name: String, content: String) throws {
        ensureDir()
        let path = skillsDir + "/\(name).md"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func deleteSkill(name: String) throws {
        let path = skillsDir + "/\(name).md"
        try FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Install Built-in Skills

    static func installBuiltins() {
        ensureDir()
        let fm = FileManager.default

        // GWS (Google Workspace)
        let gwsPath = skillsDir + "/gws.md"
        if !fm.fileExists(atPath: gwsPath) {
            let gwsSkill = """
            ---
            name: Google Workspace
            description: Gmail, Calendar, Drive, Docs via gws CLI
            triggers: [email, correo, gmail, mail, calendar, calendario, evento, drive, docs, sheets, workspace, inbox, bandeja, unread, sin leer, enviar correo, send email, agenda, meeting, reunión, cita]
            mcp: null
            tools: [run_shell]
            ---

            ## Google Workspace — gws CLI

            The user has `gws` CLI installed at /opt/homebrew/bin/gws. Use it via `run_shell` for ALL email/calendar/drive tasks.

            ### Gmail Commands:
            ```
            gws gmail inbox                    # List inbox (unread first)
            gws gmail inbox --unread           # Only unread messages
            gws gmail inbox --max 20           # Limit results
            gws gmail read <message_id>        # Read a specific email
            gws gmail send --to user@email.com --subject "Subject" --body "Body"
            gws gmail send --to user@email.com --subject "Subject" --body "Body" --html  # HTML body
            gws gmail search "query"           # Search emails
            gws gmail labels                   # List labels
            gws gmail threads                  # List threads
            gws gmail thread <thread_id>       # Read thread
            ```

            ### Calendar Commands:
            ```
            gws calendar list                  # List today's events
            gws calendar list --days 7         # Next 7 days
            gws calendar create --title "Meeting" --start "2025-03-12T10:00:00" --end "2025-03-12T11:00:00"
            gws calendar create --title "Lunch" --start "2025-03-12T13:00:00" --duration 60  # 60 minutes
            ```

            ### Drive Commands:
            ```
            gws drive list                     # List files
            gws drive list --folder <id>       # List folder contents
            gws drive search "query"           # Search files
            gws drive download <file_id> --output ./file.pdf
            ```

            ### IMPORTANT RULES:
            - ALWAYS use `run_shell` with `gws` commands. NEVER open Gmail in a browser.
            - For "check my emails" → `gws gmail inbox --unread`
            - For "send email" → `gws gmail send --to ... --subject ... --body ...`
            - For "what's on my calendar" → `gws calendar list`
            - Parse the output and present it nicely to the user.
            - If gws is not authenticated, tell the user to run `gws auth` first.
            """
            try? gwsSkill.write(toFile: gwsPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Internal

    private static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
    }

    private static func parseSkill(content: String, filePath: String) -> Skill? {
        // Parse YAML frontmatter
        guard content.hasPrefix("---") else {
            return Skill(name: URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent,
                        description: "", triggers: [], mcp: nil, tools: nil,
                        instructions: content, filePath: filePath)
        }

        let parts = content.split(separator: "---", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }

        let frontmatter = String(parts[1])
        let body = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)

        var name = ""
        var description = ""
        var triggers: [String] = []
        var mcp: String? = nil
        var tools: [String]? = nil

        for line in frontmatter.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("name:") {
                name = l.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if l.hasPrefix("description:") {
                description = l.dropFirst(12).trimmingCharacters(in: .whitespaces)
            } else if l.hasPrefix("triggers:") {
                let raw = l.dropFirst(9).trimmingCharacters(in: .whitespaces)
                triggers = parseBracketList(raw)
            } else if l.hasPrefix("mcp:") {
                let val = l.dropFirst(4).trimmingCharacters(in: .whitespaces)
                mcp = (val == "null" || val.isEmpty) ? nil : val
            } else if l.hasPrefix("tools:") {
                let raw = l.dropFirst(6).trimmingCharacters(in: .whitespaces)
                let parsed = parseBracketList(raw)
                tools = parsed.isEmpty ? nil : parsed
            }
        }

        if name.isEmpty {
            name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        }

        return Skill(name: name, description: description, triggers: triggers,
                     mcp: mcp, tools: tools, instructions: body, filePath: filePath)
    }

    private static func parseBracketList(_ raw: String) -> [String] {
        let cleaned = raw.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return cleaned.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }
}
