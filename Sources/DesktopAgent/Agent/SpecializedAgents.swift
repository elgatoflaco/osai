import Foundation

// MARK: - Specialized Agent Definition

/// A specialized agent is a reusable agent with its own model, triggers, and system prompt.
/// Stored as markdown files with YAML frontmatter in ~/.desktop-agent/agents/
struct SpecializedAgentDef: Codable {
    let name: String
    let description: String
    let model: String  // "provider/model" format
    let triggers: [String]  // keywords that auto-route to this agent
    let systemPrompt: String
    let toolCategories: [String]?  // nil = all tools, otherwise ToolCategory rawValue names
    let maxIterations: Int?
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case name, description, model, triggers
        case systemPrompt = "system_prompt"
        case toolCategories = "tool_categories"
        case maxIterations = "max_iterations"
        case temperature
    }
}

// MARK: - Agent Registry

final class AgentRegistry {
    static let agentsDir = NSHomeDirectory() + "/.desktop-agent/agents"

    /// Load all agent definitions from ~/.desktop-agent/agents/*.md
    static func loadAll() -> [SpecializedAgentDef] {
        let fm = FileManager.default
        ensureDir()
        guard let files = try? fm.contentsOfDirectory(atPath: agentsDir) else { return [] }
        return files
            .filter { $0.hasSuffix(".md") }
            .compactMap { loadAgent(path: agentsDir + "/" + $0) }
            .sorted { $0.name < $1.name }
    }

    /// Load a single agent from a markdown file
    static func loadAgent(path: String) -> SpecializedAgentDef? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parseAgent(content: content, filePath: path)
    }

    /// Find the best matching agent for a user input
    static func route(input: String) -> SpecializedAgentDef? {
        let agents = loadAll()
        if agents.isEmpty { return nil }

        let lower = input.lowercased()

        // Score each agent by trigger match count
        var bestAgent: SpecializedAgentDef? = nil
        var bestScore = 0

        for agent in agents {
            var score = 0
            for trigger in agent.triggers {
                if lower.contains(trigger.lowercased()) {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                bestAgent = agent
            }
        }

        return bestScore > 0 ? bestAgent : nil
    }

    /// Install default agents if none exist
    static func installDefaults() {
        ensureDir()

        // Only install if directory is empty
        let fm = FileManager.default
        let existing = (try? fm.contentsOfDirectory(atPath: agentsDir))?.filter { $0.hasSuffix(".md") } ?? []
        if !existing.isEmpty { return }

        // Install default agents
        for (filename, content) in defaultAgents {
            let path = agentsDir + "/" + filename
            try? content.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
    }

    // MARK: - Parse Agent from Markdown

    private static func parseAgent(content: String, filePath: String) -> SpecializedAgentDef? {
        let fallbackName = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent

        // Must have frontmatter
        guard content.hasPrefix("---") else { return nil }

        let parts = content.components(separatedBy: "---\n")
        guard parts.count >= 3 else { return nil }

        let frontmatter = parts[1]
        let body = parts.dropFirst(2).joined(separator: "---\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var name = fallbackName
        var description = ""
        var model = ""
        var triggers: [String] = []
        var toolCategories: [String]? = nil
        var maxIterations: Int? = nil
        var temperature: Double? = nil

        // Track multi-line YAML array parsing
        var currentArrayKey: String? = nil
        var currentArray: [String] = []

        for line in frontmatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for YAML array item (- value)
            if let key = currentArrayKey, trimmed.hasPrefix("- ") {
                let value = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty {
                    currentArray.append(value)
                }
                continue
            } else if currentArrayKey != nil {
                // End of array, store it
                finishArray(key: currentArrayKey!, values: currentArray,
                           triggers: &triggers, toolCategories: &toolCategories)
                currentArrayKey = nil
                currentArray = []
            }

            // Regular key: value parsing
            let kv = trimmed.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }

            let key = kv[0]
            let value = kv[1]

            switch key {
            case "name":
                name = value
            case "description":
                description = value
            case "model":
                model = value
            case "triggers":
                if value.isEmpty {
                    // Multi-line YAML array follows
                    currentArrayKey = "triggers"
                    currentArray = []
                } else {
                    // Inline format: [item1, item2, ...]
                    triggers = parseBracketList(value)
                }
            case "tool_categories":
                if value.isEmpty {
                    currentArrayKey = "tool_categories"
                    currentArray = []
                } else {
                    toolCategories = parseBracketList(value)
                }
            case "max_iterations":
                maxIterations = Int(value)
            case "temperature":
                temperature = Double(value)
            default:
                break
            }
        }

        // Flush any trailing array
        if let key = currentArrayKey {
            finishArray(key: key, values: currentArray,
                       triggers: &triggers, toolCategories: &toolCategories)
        }

        // Must have a model
        guard !model.isEmpty else { return nil }

        return SpecializedAgentDef(
            name: name,
            description: description,
            model: model,
            triggers: triggers,
            systemPrompt: body,
            toolCategories: toolCategories,
            maxIterations: maxIterations,
            temperature: temperature
        )
    }

    private static func finishArray(key: String, values: [String],
                                     triggers: inout [String], toolCategories: inout [String]?) {
        switch key {
        case "triggers":
            triggers = values
        case "tool_categories":
            toolCategories = values.isEmpty ? nil : values
        default:
            break
        }
    }

    private static func parseBracketList(_ raw: String) -> [String] {
        let cleaned = raw.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return cleaned.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }

    // MARK: - Default Agents

    static let defaultAgents: [(String, String)] = [
        ("news.md", """
        ---
        name: news
        description: Fast news briefings and current events analysis
        model: openrouter/x-ai/grok-3-mini
        triggers:
          - noticias
          - news
          - briefing
          - headlines
          - "que esta pasando"
          - "what's happening"
          - actualidad
          - current events
        ---
        You are a fast news analyst. Search the web for current news and provide concise briefings.
        Focus on: key facts, impact analysis, and relevance to the user.
        Always cite sources. Be concise -- bullet points preferred.
        Respond in the same language as the user's request.
        """),

        ("code.md", """
        ---
        name: code
        description: Expert coding assistant for programming tasks
        model: anthropic/claude-sonnet-4-20250514
        triggers:
          - codigo
          - code
          - programming
          - debug
          - refactor
          - function
          - class
          - bug
          - error
          - compile
          - programar
          - funcion
        ---
        You are an expert programmer. Write clean, efficient, well-tested code.
        Follow the project's existing conventions. Explain complex logic briefly.
        Prefer simple solutions over clever ones.
        """),

        ("research.md", """
        ---
        name: research
        description: Deep web research and analysis
        model: google/gemini-2.5-flash
        triggers:
          - research
          - investigar
          - buscar
          - search
          - find out
          - averiguar
          - informacion sobre
          - tell me about
          - analyze
          - analizar
          - compare
          - comparar
        ---
        You are a thorough researcher. Search multiple sources, cross-reference facts, and provide comprehensive but organized findings.
        Structure your output with headers and bullet points.
        Always note source reliability and potential biases.
        """),

        ("email-agent.md", """
        ---
        name: email-agent
        description: Email management and drafting
        model: anthropic/claude-haiku-4-5-20251001
        triggers:
          - redactar correo
          - draft email
          - write email
          - email draft
          - borrador
        ---
        You are an efficient email assistant. Draft professional emails, manage inbox, and prioritize messages.
        Match the formality level of the context. Be concise but complete.
        Use the send_email tool for sending and gws commands for inbox management.
        """),

        ("automation.md", """
        ---
        name: automation
        description: macOS automation specialist
        model: anthropic/claude-haiku-4-5-20251001
        triggers:
          - automate
          - automatizar
          - shortcut
          - atajo
          - workflow
          - launchd
        ---
        You are a macOS automation expert. Create AppleScripts, shell scripts, launchd tasks, and Shortcuts.
        Always explain what the automation does before creating it.
        Prefer AppleScript for app control, shell for file/system tasks, launchd for scheduling.
        """),
    ]
}
