import Foundation

// MARK: - Specialized Agent Definition

/// A specialized agent is a reusable agent with its own model, triggers, and system prompt.
/// Stored as markdown files with YAML frontmatter in ~/.desktop-agent/agents/
struct SpecializedAgentDef: Codable {
    let name: String
    let description: String
    let model: String  // "provider/model" format, or "claude-code" for CLI delegation
    let triggers: [String]  // keywords that auto-route to this agent
    let systemPrompt: String
    let toolCategories: [String]?  // nil = all tools, otherwise ToolCategory rawValue names
    let maxIterations: Int?
    let temperature: Double?
    let backend: String?  // nil = API call, "claude-code" = delegate to Claude Code CLI

    /// If true, this agent delegates to Claude Code CLI instead of making API calls
    var usesClaudeCode: Bool {
        backend == "claude-code" || model == "claude-code"
    }

    enum CodingKeys: String, CodingKey {
        case name, description, model, triggers
        case systemPrompt = "system_prompt"
        case toolCategories = "tool_categories"
        case maxIterations = "max_iterations"
        case temperature, backend
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
        // Just ensure the directory exists — no default agents installed.
        // Users create their own agents in ~/.desktop-agent/agents/
        // Use /agent install to install example templates if desired.
        ensureDir()
    }

    /// Explicitly install example agent templates (called via /agent install)
    static func installTemplates() {
        ensureDir()
        for (filename, content) in defaultAgents {
            let path = agentsDir + "/" + filename
            if !FileManager.default.fileExists(atPath: path) {
                try? content.write(toFile: path, atomically: true, encoding: .utf8)
            }
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
        var backend: String? = nil

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
            case "backend":
                backend = value
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
            temperature: temperature,
            backend: backend
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
        description: Noticias de tech, IA, producto y geopolitica
        model: openrouter/x-ai/grok-4-fast
        triggers:
          - noticias
          - news
          - briefing
          - headlines
          - actualidad
          - current events
          - esta semana
          - trending
          - tweets
          - salseos
          - que pasa
          - mundo
          - novedades
        ---
        Fast news analyst. Search HN, Reddit, TechCrunch via curl.
        Bullet points, sources cited, same language as user.
        Focus: AI/tech, digital product, geopolitics affecting tech, open source.
        """),

        ("product.md", """
        ---
        name: product
        description: Product manager para crear y lanzar productos digitales
        model: anthropic/claude-sonnet-4-20250514
        triggers:
          - producto
          - product
          - feature
          - roadmap
          - mvp
          - lanzar
          - launch
          - monetizar
          - pricing
          - user story
          - spec
          - prd
          - idea de negocio
          - business model
          - competencia
          - go to market
        ---
        Senior product manager. User first, business second, tech third. MVP > perfection.
        Always end with concrete next steps.
        """),

        ("code.md", """
        ---
        name: code
        description: Programador experto para features y bugs
        model: anthropic/claude-sonnet-4-20250514
        triggers:
          - codigo
          - code
          - debug
          - refactor
          - bug
          - error
          - compile
          - programar
          - implementar
          - function
          - class
          - fix
          - arreglar
        ---
        Senior programmer. Clean, simple code that works. Follow project conventions.
        """),

        ("research.md", """
        ---
        name: research
        description: Investigador para analisis y comparativas
        model: google/gemini-2.5-flash
        triggers:
          - investigar
          - research
          - averiguar
          - analizar
          - analyze
          - comparar
          - compare
          - alternativas
          - benchmark
          - pros y contras
        ---
        Thorough researcher. Multiple sources, cross-reference, structured output with confidence levels.
        """),

        ("organizer.md", """
        ---
        name: organizer
        description: Asistente personal para tareas, calendario y organizacion
        model: anthropic/claude-haiku-4-5-20251001
        triggers:
          - organizar
          - organize
          - tarea
          - pendiente
          - todo
          - recordatorio
          - reminder
          - calendario
          - calendar
          - agenda
          - planificar
          - priorizar
          - inbox zero
        ---
        Personal assistant. Uses gws calendar, gws gmail, AppleScript for Reminders/Notes.
        Triage, prioritize, act, report. CLI tools only, never open apps.
        """),

        ("writer.md", """
        ---
        name: writer
        description: Redactor para copy, emails y comunicacion
        model: anthropic/claude-sonnet-4-20250514
        triggers:
          - redactar
          - escribir
          - copy
          - copywriting
          - pitch
          - propuesta
          - proposal
          - post
          - blog
          - tweet
          - linkedin
          - email profesional
          - correo formal
        ---
        Professional writer. Clear, direct, no filler. Adapts tone to medium and audience.
        """),

        ("design.md", """
        ---
        name: design
        description: Disenador UX/UI para interfaces y prototipos
        model: anthropic/claude-sonnet-4-20250514
        triggers:
          - diseno
          - design
          - ui
          - ux
          - wireframe
          - mockup
          - prototipo
          - prototype
          - flujo
          - flow
          - componente
          - layout
          - svg
          - icono
        ---
        Senior UX/UI designer. Generate code (SVG, HTML, SwiftUI), not descriptions.
        Mobile first, less is more, use standard patterns.
        """),
    ]
}
