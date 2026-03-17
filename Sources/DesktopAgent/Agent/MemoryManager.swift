import Foundation

// MARK: - Memory Index Structs

struct MemoryEntry: Codable {
    let fileName: String
    var keywords: [String]
    var summary: String
    var createdAt: Date
    var lastAccessed: Date
    var accessCount: Int
}

struct MemoryIndex: Codable {
    var entries: [String: MemoryEntry]  // keyed by fileName
}

// MARK: - Memory Manager (Persistent memory in markdown files)

final class MemoryManager {
    let memoryDir: String
    private var index: MemoryIndex?
    private var indexPath: String { memoryDir + "/memory_index.json" }

    /// Files that are always loaded (critical user context)
    private let criticalFiles = ["user_info.md", "contact_info.md", "preferencias-usuario.md", "user_preferences.md"]

    /// Bilingual stopwords (EN + ES)
    private static let stopwords: Set<String> = [
        // English
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "shall",
        "should", "may", "might", "must", "can", "could", "and", "but", "or",
        "nor", "not", "so", "yet", "both", "either", "neither", "each",
        "every", "all", "any", "few", "more", "most", "other", "some", "such",
        "than", "too", "very", "just", "about", "above", "after", "again",
        "also", "because", "before", "below", "between", "by", "for", "from",
        "here", "how", "in", "into", "it", "its", "of", "on", "only", "out",
        "over", "own", "same", "she", "he", "her", "him", "his", "they",
        "them", "their", "this", "that", "these", "those", "through", "to",
        "under", "until", "up", "what", "when", "where", "which", "while",
        "who", "whom", "why", "with", "you", "your", "we", "our", "me", "my",
        // Spanish
        "de", "el", "la", "los", "las", "un", "una", "unos", "unas", "del",
        "al", "y", "o", "en", "que", "es", "por", "con", "no", "se", "su",
        "para", "como", "más", "mas", "pero", "sus", "le", "ya", "lo", "fue",
        "son", "este", "esta", "estos", "estas", "ese", "esa", "esos", "esas",
        "hay", "está", "han", "ser", "sin", "sobre", "todo", "también",
        "entre", "nos", "cuando", "muy", "hasta", "donde", "quien",
        // Markdown / common noise
        "http", "https", "www", "com", "org", "the", "file", "true", "false"
    ]

    init() {
        self.memoryDir = AgentConfigFile.configDir + "/memory"
        ensureDir()
        loadOrBuildIndex()
    }

    private func ensureDir() {
        try? FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
    }

    // MARK: - Index Management

    private func loadOrBuildIndex() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)),
           let decoded = try? JSONDecoder.withISO8601.decode(MemoryIndex.self, from: data) {
            self.index = decoded
        } else {
            buildIndexFromDisk()
        }
    }

    /// Scan all .md files and build a fresh index
    private func buildIndexFromDisk() {
        var entries = [String: MemoryEntry]()
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: memoryDir) else {
            self.index = MemoryIndex(entries: [:])
            return
        }
        let now = Date()
        for name in items where name.hasSuffix(".md") {
            let path = (memoryDir as NSString).appendingPathComponent(name)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let keywords = extractKeywords(content)
            let summary = String(content.prefix(120)).components(separatedBy: "\n").first ?? ""
            entries[name] = MemoryEntry(
                fileName: name,
                keywords: keywords,
                summary: summary,
                createdAt: (try? fm.attributesOfItem(atPath: path)[.creationDate] as? Date) ?? now,
                lastAccessed: now,
                accessCount: 0
            )
        }
        self.index = MemoryIndex(entries: entries)
        saveIndex()
    }

    private func saveIndex() {
        guard let index = index else { return }
        let encoder = JSONEncoder.withISO8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: URL(fileURLWithPath: indexPath))
    }

    // MARK: - Keyword Extraction

    func extractKeywords(_ text: String) -> [String] {
        let cleaned = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !MemoryManager.stopwords.contains($0) }

        // Count frequency
        var freq = [String: Int]()
        for word in cleaned {
            freq[word, default: 0] += 1
        }

        // Return top 10 by frequency
        return freq.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }

    // MARK: - Relevance Scoring

    func relevantMemories(for input: String, limit: Int = 5) -> [(file: String, score: Double)] {
        guard let index = index else { return [] }
        let inputKeywords = Set(extractKeywords(input))
        guard !inputKeywords.isEmpty else { return [] }

        let now = Date()
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)

        var scored = [(file: String, score: Double)]()
        for (fileName, entry) in index.entries {
            // Skip critical files (they're always loaded) and the index itself
            if criticalFiles.contains(fileName) || fileName == "MEMORY.md" { continue }

            let entryKeywords = Set(entry.keywords)
            let overlap = inputKeywords.intersection(entryKeywords).count
            guard overlap > 0 else { continue }

            var score = Double(overlap)

            // Boost by log(accessCount + 1)
            score += log(Double(entry.accessCount + 1))

            // Penalize stale files (not accessed in 30+ days)
            if entry.lastAccessed < thirtyDaysAgo {
                score *= 0.5
            }

            scored.append((file: fileName, score: score))
        }

        return scored.sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Update access tracking for a memory entry
    private func markAccessed(_ fileName: String) {
        guard index != nil else { return }
        index?.entries[fileName]?.lastAccessed = Date()
        index?.entries[fileName]?.accessCount += 1
        saveIndex()
    }

    // MARK: - Core Memory (always loaded into context)

    var coreMemoryPath: String { memoryDir + "/MEMORY.md" }

    func loadCoreMemory() -> String {
        var parts = [String]()

        // 1. Load MEMORY.md (index file)
        let path = coreMemoryPath
        if FileManager.default.fileExists(atPath: path),
           let data = try? String(contentsOfFile: path, encoding: .utf8), !data.isEmpty {
            let lines = data.components(separatedBy: "\n")
            if lines.count > 200 {
                parts.append(lines.prefix(200).joined(separator: "\n") + "\n... [truncated]")
            } else {
                parts.append(data)
            }
        }

        // 2. Also load key memory files (user_info, preferences) for critical context
        for filename in criticalFiles {
            let filePath = (memoryDir as NSString).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: filePath),
               let content = try? String(contentsOfFile: filePath, encoding: .utf8), !content.isEmpty {
                parts.append("[\(filename)]:\n\(String(content.prefix(500)))")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    func saveCoreMemory(_ content: String) throws {
        ensureDir()
        try content.write(toFile: coreMemoryPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Topic Memory Files

    func listMemoryFiles() -> [(name: String, path: String, size: Int)] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: memoryDir) else { return [] }
        return items
            .filter { $0.hasSuffix(".md") }
            .compactMap { name -> (String, String, Int)? in
                let path = (memoryDir as NSString).appendingPathComponent(name)
                let attrs = try? fm.attributesOfItem(atPath: path)
                let size = attrs?[.size] as? Int ?? 0
                return (name, path, size)
            }
            .sorted { $0.0 < $1.0 }
    }

    func readMemoryFile(name: String) -> String? {
        let fileName = name.hasSuffix(".md") ? name : name + ".md"
        let path = (memoryDir as NSString).appendingPathComponent(fileName)
        markAccessed(fileName)
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    func writeMemoryFile(name: String, content: String) throws {
        ensureDir()
        let fileName = name.hasSuffix(".md") ? name : name + ".md"
        let path = (memoryDir as NSString).appendingPathComponent(fileName)
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        // Auto-index on save
        let keywords = extractKeywords(content)
        let summary = String(content.prefix(120)).components(separatedBy: "\n").first ?? ""
        let now = Date()
        if let existing = index?.entries[fileName] {
            index?.entries[fileName] = MemoryEntry(
                fileName: fileName,
                keywords: keywords,
                summary: summary,
                createdAt: existing.createdAt,
                lastAccessed: now,
                accessCount: existing.accessCount + 1
            )
        } else {
            index?.entries[fileName] = MemoryEntry(
                fileName: fileName,
                keywords: keywords,
                summary: summary,
                createdAt: now,
                lastAccessed: now,
                accessCount: 0
            )
        }
        saveIndex()
    }

    func deleteMemoryFile(name: String) throws {
        let fileName = name.hasSuffix(".md") ? name : name + ".md"
        let path = (memoryDir as NSString).appendingPathComponent(fileName)
        try FileManager.default.removeItem(atPath: path)

        // Remove from index
        index?.entries.removeValue(forKey: fileName)
        saveIndex()
    }

    // MARK: - Memory as system prompt addition

    /// Keywords that suggest the user wants to access memory
    private static let memoryKeywords = [
        "remember", "recall", "last time", "previously", "before",
        "memoria", "recuerda", "anterior",
        "save_memory", "read_memory", "memory", "forgot", "forget",
        "you told me", "we discussed", "we talked",
        "me llamo", "mi nombre", "my name", "who am i", "quién soy",
        "cómo me llamo", "como me llamo"
    ]

    /// Track whether memory has been loaded this session
    var memoryLoadedThisSession = false

    /// Check if user input suggests memory is needed — always returns true to ensure user context is available
    func shouldLoadMemory(for userInput: String) -> Bool {
        // Always load memory — it contains critical user info (name, phone, preferences)
        return true
    }

    /// Smart memory context: loads critical files always + relevant memories based on input
    func getMemoryContext(for userInput: String? = nil) -> String {
        // If called without input (legacy), always load
        if let input = userInput {
            guard shouldLoadMemory(for: input) else { return "" }
        }

        var parts = [String]()

        // 1. Always load core memory (MEMORY.md + critical files)
        let core = loadCoreMemory()
        if !core.isEmpty {
            parts.append(core)
        }

        // 2. Load relevant memories based on user input
        if let input = userInput, !input.isEmpty {
            let relevant = relevantMemories(for: input)
            for (fileName, _) in relevant {
                let path = (memoryDir as NSString).appendingPathComponent(fileName)
                if let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
                    markAccessed(fileName)
                    parts.append("[\(fileName)]:\n\(String(content.prefix(800)))")
                }
            }
        }

        // 3. List unloaded memory files so the agent knows they exist
        let loadedFiles = Set(criticalFiles + ["MEMORY.md"] + (userInput.flatMap { relevantMemories(for: $0).map { $0.file } } ?? []))
        let allFiles = listMemoryFiles().map { $0.name }
        let unloaded = allFiles.filter { !loadedFiles.contains($0) && $0 != "memory_index.json" }
        if !unloaded.isEmpty {
            parts.append("Available memories (not loaded, use read_memory to access): \(unloaded.joined(separator: ", "))")
        }

        if parts.isEmpty { return "" }

        memoryLoadedThisSession = true

        return """

        ## Persistent Memory
        The following is your persistent memory from previous sessions:

        \(parts.joined(separator: "\n\n"))

        You can update your memory using the save_memory and read_memory tools.
        """
    }

    // MARK: - Session Digests

    /// Save a digest of the conversation to sessions/ for future reference.
    /// Only saves if the conversation is substantial (4+ messages).
    func saveSessionDigest(messages: [ClaudeMessage], model: String) {
        guard messages.count >= 4 else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let dateStr = String(timestamp.prefix(10)) // YYYY-MM-DD

        // Extract key info from messages without an API call
        var userQueries: [String] = []
        var toolsUsed: Set<String> = []
        var lastAssistantResponse = ""

        for msg in messages {
            if msg.role == "user" {
                for block in msg.content {
                    if case .text(let t) = block {
                        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            userQueries.append("- " + String(trimmed.prefix(100)))
                        }
                    }
                }
            }
            if msg.role == "assistant" {
                for block in msg.content {
                    switch block {
                    case .text(let t):
                        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            lastAssistantResponse = trimmed
                        }
                    case .toolUse(_, let name, _, _):
                        toolsUsed.insert(name)
                    default:
                        break
                    }
                }
            }
        }

        let digest = """
        ---
        date: \(timestamp)
        model: \(model)
        messages: \(messages.count)
        tools: \(toolsUsed.sorted().joined(separator: ", "))
        ---
        ## User asked:
        \(userQueries.prefix(3).joined(separator: "\n"))

        ## Summary:
        \(String(lastAssistantResponse.prefix(300)))
        """

        let sessionsDir = memoryDir + "/sessions"
        try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)

        let fileName = "session_\(dateStr)_\(UUID().uuidString.prefix(6)).md"
        let relativePath = "sessions/\(fileName)"
        let fullPath = (sessionsDir as NSString).appendingPathComponent(fileName)
        try? digest.write(toFile: fullPath, atomically: true, encoding: .utf8)

        // Index the session digest
        let keywords = extractKeywords(digest)
        let summary = String(digest.prefix(120)).components(separatedBy: "\n").first ?? ""
        let now = Date()
        index?.entries[relativePath] = MemoryEntry(
            fileName: relativePath,
            keywords: keywords,
            summary: summary,
            createdAt: now,
            lastAccessed: now,
            accessCount: 0
        )
        saveIndex()

        // Cleanup: keep only last 50 sessions
        cleanupOldSessions(keepLast: 50)
    }

    /// Remove oldest session files if there are more than `keepLast`.
    private func cleanupOldSessions(keepLast: Int) {
        let sessionsDir = memoryDir + "/sessions"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDir) else { return }

        let mdFiles = files.filter { $0.hasSuffix(".md") }.sorted()
        guard mdFiles.count > keepLast else { return }

        let toRemove = mdFiles.prefix(mdFiles.count - keepLast)
        for fileName in toRemove {
            let fullPath = (sessionsDir as NSString).appendingPathComponent(fileName)
            try? fm.removeItem(atPath: fullPath)
            // Remove from index
            index?.entries.removeValue(forKey: "sessions/\(fileName)")
        }
        saveIndex()
    }
}

// MARK: - JSON Encoder/Decoder with ISO8601 dates

private extension JSONEncoder {
    static var withISO8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
