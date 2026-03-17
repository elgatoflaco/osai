import Foundation

// MARK: - Memory Manager (Persistent memory in markdown files)

final class MemoryManager {
    let memoryDir: String

    init() {
        self.memoryDir = AgentConfigFile.configDir + "/memory"
        ensureDir()
    }

    private func ensureDir() {
        try? FileManager.default.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
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
        let keyFiles = ["user_info.md", "contact_info.md", "preferencias-usuario.md", "user_preferences.md"]
        for filename in keyFiles {
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
        let path = (memoryDir as NSString).appendingPathComponent(name.hasSuffix(".md") ? name : name + ".md")
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    func writeMemoryFile(name: String, content: String) throws {
        ensureDir()
        let fileName = name.hasSuffix(".md") ? name : name + ".md"
        let path = (memoryDir as NSString).appendingPathComponent(fileName)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func deleteMemoryFile(name: String) throws {
        let fileName = name.hasSuffix(".md") ? name : name + ".md"
        let path = (memoryDir as NSString).appendingPathComponent(fileName)
        try FileManager.default.removeItem(atPath: path)
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

    /// Conditionally return memory context based on user input relevance
    func getMemoryContext(for userInput: String? = nil) -> String {
        // If called without input (legacy), always load
        if let input = userInput {
            guard shouldLoadMemory(for: input) else { return "" }
        }

        let core = loadCoreMemory()
        if core.isEmpty { return "" }

        memoryLoadedThisSession = true

        return """

        ## Persistent Memory
        The following is your persistent memory from previous sessions:

        \(core)

        You can update your memory using the save_memory and read_memory tools.
        """
    }
}
