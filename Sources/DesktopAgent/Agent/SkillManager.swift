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

        // GWS (Google Workspace) — always overwrite to keep in sync
        let gwsPath = skillsDir + "/gws.md"
        let gwsSkill = """
        ---
        name: Google Workspace
        description: Gmail, Calendar, Drive, Docs via gws CLI (REST-style API)
        triggers: [email, correo, gmail, mail, calendar, calendario, evento, drive, docs, sheets, workspace, inbox, bandeja, unread, sin leer, enviar correo, send email, agenda, meeting, reunión, cita, leído, leido, marcar, read, send, draft]
        mcp: null
        tools: [run_shell]
        ---

        ## Google Workspace — gws CLI

        The user has `gws` installed at /opt/homebrew/bin/gws. Use it via `run_shell` for ALL email/calendar/drive tasks.

        **SYNTAX:** `gws <service> <resource> [sub-resource] <method> [flags]`

        Accounts: enmaska@gmail.com (default), dev@puertozahara.com
        Use `--params '{"accountEmail": "dev@puertozahara.com"}'` to switch account.

        ### Gmail

        **List unread messages:**
        ```
        gws gmail users messages list --params '{"userId": "me", "q": "is:unread", "maxResults": 10}'
        ```

        **List inbox:**
        ```
        gws gmail users messages list --params '{"userId": "me", "q": "in:inbox", "maxResults": 10}'
        ```

        **Search emails:**
        ```
        gws gmail users messages list --params '{"userId": "me", "q": "from:someone@email.com subject:hello", "maxResults": 10}'
        ```

        **Read a specific message (metadata only — fast):**
        ```
        gws gmail users messages get --params '{"userId": "me", "id": "MSG_ID", "format": "metadata", "metadataHeaders": ["From","To","Subject","Date"]}'
        ```

        **Read full message:**
        ```
        gws gmail users messages get --params '{"userId": "me", "id": "MSG_ID", "format": "full"}'
        ```

        **Mark as read (remove UNREAD label):**
        ```
        gws gmail users messages modify --params '{"userId": "me", "id": "MSG_ID"}' --json '{"removeLabelIds": ["UNREAD"]}'
        ```
        ⚠️ Requires full scopes. If you get 403 "insufficientPermissions", tell the user:
        "Need write permissions. Run: `gws auth login --full` to re-authenticate with full scopes."
        **DO NOT fall back to opening Gmail in browser.**

        **Send email (base64-encoded RFC 2822):**
        ```
        # Build the raw email, base64url encode it, then send:
        echo -e "From: me\\nTo: recipient@email.com\\nSubject: Hello\\nContent-Type: text/plain\\n\\nBody text here" | base64 | tr '+/' '-_' | tr -d '=' | xargs -I{} gws gmail users messages send --params '{"userId": "me"}' --json '{"raw": "{}"}'
        ```

        **List labels:**
        ```
        gws gmail users labels list --params '{"userId": "me"}'
        ```

        **Read thread:**
        ```
        gws gmail users threads get --params '{"userId": "me", "id": "THREAD_ID"}'
        ```

        ### Calendar

        **List upcoming events:**
        ```
        gws calendar events list --params '{"calendarId": "primary", "timeMin": "2026-03-11T00:00:00Z", "maxResults": 10, "singleEvents": true, "orderBy": "startTime"}'
        ```
        ⚠️ Always set `timeMin` to today's date in ISO 8601 with Z suffix.

        **Create event:**
        ```
        gws calendar events insert --params '{"calendarId": "primary"}' --json '{"summary": "Meeting title", "start": {"dateTime": "2026-03-12T10:00:00", "timeZone": "Europe/Madrid"}, "end": {"dateTime": "2026-03-12T11:00:00", "timeZone": "Europe/Madrid"}}'
        ```

        **Delete event:**
        ```
        gws calendar events delete --params '{"calendarId": "primary", "eventId": "EVENT_ID"}'
        ```

        ### Drive

        **List recent files:**
        ```
        gws drive files list --params '{"pageSize": 10, "fields": "files(id,name,mimeType,modifiedTime)", "orderBy": "modifiedTime desc"}'
        ```

        **Search files:**
        ```
        gws drive files list --params '{"q": "name contains \\'report\\'", "pageSize": 10, "fields": "files(id,name,mimeType)"}'
        ```

        **Download file:**
        ```
        gws drive files get --params '{"fileId": "FILE_ID", "alt": "media"}' --output ./downloaded_file.pdf
        ```

        ### People / Contacts

        **Search contacts:**
        ```
        gws people people searchContacts --params '{"query": "John", "readMask": "names,emailAddresses,phoneNumbers", "pageSize": 10}'
        ```

        ### CRITICAL RULES:
        - **ALWAYS use `run_shell` with `gws` commands. NEVER open Gmail/Calendar/Drive in a browser.**
        - **If a gws command fails with 403, tell the user to run `gws auth login --full`. DO NOT fall back to GUI.**
        - **If a gws command fails with other errors, debug the command. DO NOT open a browser.**
        - All params are JSON. Quote carefully with single quotes outside, double inside.
        - Parse JSON output and present it nicely to the user (summary table, not raw JSON).
        - When listing messages, ALWAYS batch `get` calls for details (From, Subject, Date).
        - Use `format: "metadata"` for message listings (cheaper, faster than "full").
        """
        try? gwsSkill.write(toFile: gwsPath, atomically: true, encoding: .utf8)
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
