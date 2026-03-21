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

    /// Result of routing — includes match quality info
    struct RouteResult {
        let agent: SpecializedAgentDef
        let score: Double
        let matchType: MatchType
        let reason: String

        enum MatchType: String {
            case ai         // AI model chose the agent
            case fallback   // no match, using general assistant
        }
    }

    /// AI-powered routing: ask the model which agent is best for this task.
    /// Falls back to nil (general assistant) if the AI call fails or no agents are configured.
    static func route(input: String) -> RouteResult? {
        let agents = loadAll()
        guard !agents.isEmpty else { return nil }

        // Build the agent catalog for the prompt
        let agentList = agents.enumerated().map { (i, a) in
            "\(i + 1). **\(a.name)**: \(a.description)"
        }.joined(separator: "\n")

        let prompt = """
        You are a router. Given the user's message, decide which specialist agent should handle it.

        Available agents:
        \(agentList)

        User message: "\(String(input.prefix(500)))"

        Rules:
        - Pick the SINGLE best agent, or "none" if the general assistant is better.
        - If the task involves multiple domains (e.g. "check news and send via WhatsApp"), pick the agent for the PRIMARY task.
        - Respond with ONLY a JSON object: {"agent": "name", "reason": "brief explanation"}
        - Use "none" as agent name if no specialist fits.
        """

        // Synchronous wrapper for async AI call (routing must be sync in current architecture)
        let config = AgentConfig.load()
        guard !config.apiKey.isEmpty else {
            logRoute(input: input, result: "no-api-key", agents: agents)
            return nil
        }

        let client = AIClient(
            apiKey: config.apiKey,
            model: config.model,
            maxTokens: 150,
            baseURL: config.baseURL,
            format: config.apiFormat,
            authType: config.authType
        )

        var routeResult: RouteResult? = nil
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            defer { semaphore.signal() }
            do {
                let messages = [ClaudeMessage(role: "user", content: [.text(prompt)])]
                let response = try await client.sendMessage(messages: messages, system: "You are a router that outputs JSON only. No explanation, no markdown, just {\"agent\":\"name\",\"reason\":\"why\"}.", tools: nil)

                let responseText: String? = response.content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.first
                if let text = responseText {
                    // Parse JSON response — handle markdown-wrapped JSON too
                    let cleaned = text
                        .replacingOccurrences(of: "```json", with: "")
                        .replacingOccurrences(of: "```", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if let data = cleaned.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let agentName = json["agent"] as? String,
                       agentName != "none" {
                        let reason = json["reason"] as? String ?? ""
                        if let agent = agents.first(where: { $0.name.lowercased() == agentName.lowercased() }) {
                            routeResult = RouteResult(agent: agent, score: 1.0, matchType: .ai, reason: reason)
                        }
                    }
                }
            } catch {
                // AI call failed — fall through to nil (general assistant)
            }
        }

        // Wait max 8 seconds for routing decision
        let timeout = semaphore.wait(timeout: .now() + 8)
        if timeout == .timedOut {
            logRoute(input: input, result: "timeout", agents: agents)
            return nil
        }

        logRoute(input: input, result: routeResult?.agent.name ?? "none", agents: agents)
        return routeResult
    }

    /// Log routing decision to file for debugging
    private static func logRoute(input: String, result: String, agents: [SpecializedAgentDef]) {
        let agentNames = agents.map { $0.name }.joined(separator: ", ")
        let logMsg = "[ROUTE-AI] input='\(String(input.prefix(80)))' result=\(result) agents=[\(agentNames)]\n"
        if let data = logMsg.data(using: .utf8) {
            let logPath = NSHomeDirectory() + "/.desktop-agent/routing.log"
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) { fh.seekToEndOfFile(); fh.write(data); fh.closeFile() }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    // MARK: - Text Normalization & Fuzzy Matching

    /// Remove accents, lowercase, strip punctuation
    static func normalizeText(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Standard Levenshtein distance (dynamic programming)
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Use two rows instead of full matrix for memory efficiency
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,       // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            prev = curr
        }

        return prev[n]
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
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[trimmed.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

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
