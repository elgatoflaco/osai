import Foundation

// MARK: - CLI Session Persistence (save/resume interactive conversations)

struct SessionInfo: Codable {
    let id: String
    let name: String          // first ~50 chars of first user message
    let model: String
    let createdAt: Date
    var updatedAt: Date
    var turnCount: Int
    var totalTokens: Int
}

struct SessionManager {
    static let sessionsDir = NSHomeDirectory() + "/.desktop-agent/sessions/cli"
    static let currentFile = sessionsDir + "/current.jsonl"

    // MARK: - Save

    /// Save a full session (info line + all messages) to <id>.jsonl
    static func save(id: String, info: SessionInfo, messages: [ClaudeMessage]) {
        ensureDir()
        let path = sessionsDir + "/\(id).jsonl"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var lines: [String] = []

        // First line: session info
        if let infoData = try? encoder.encode(info),
           let infoStr = String(data: infoData, encoding: .utf8) {
            lines.append(infoStr)
        }

        // Remaining lines: one ClaudeMessage per line
        for msg in messages {
            if let msgData = try? encoder.encode(msg),
               let msgStr = String(data: msgData, encoding: .utf8) {
                lines.append(msgStr)
            }
        }

        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Append new messages to the current session file (lightweight incremental save)
    static func appendToCurrent(info: SessionInfo, newMessages: [ClaudeMessage]) {
        ensureDir()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // If file doesn't exist, write info header first
        if !FileManager.default.fileExists(atPath: currentFile) {
            if let infoData = try? encoder.encode(info),
               let infoStr = String(data: infoData, encoding: .utf8) {
                try? (infoStr + "\n").write(toFile: currentFile, atomically: true, encoding: .utf8)
            }
        } else {
            // Update the info line (first line) by rewriting
            rewriteInfoLine(info: info)
        }

        // Append new messages
        guard let handle = FileHandle(forWritingAtPath: currentFile) else { return }
        defer { handle.closeFile() }
        handle.seekToEndOfFile()

        for msg in newMessages {
            if let msgData = try? encoder.encode(msg),
               let msgStr = String(data: msgData, encoding: .utf8) {
                if let lineData = (msgStr + "\n").data(using: .utf8) {
                    handle.write(lineData)
                }
            }
        }
    }

    /// Rewrite just the first line (SessionInfo) of current.jsonl
    private static func rewriteInfoLine(info: SessionInfo) {
        guard let content = try? String(contentsOfFile: currentFile, encoding: .utf8) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var lines = content.components(separatedBy: "\n")
        if let infoData = try? encoder.encode(info),
           let infoStr = String(data: infoData, encoding: .utf8) {
            if lines.isEmpty {
                lines = [infoStr]
            } else {
                lines[0] = infoStr
            }
        }
        let updated = lines.joined(separator: "\n")
        try? updated.write(toFile: currentFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Load

    /// Load a session's info and messages from a JSONL file
    static func load(id: String) -> (info: SessionInfo, messages: [ClaudeMessage])? {
        let path: String
        if id == "current" {
            path = currentFile
        } else {
            path = sessionsDir + "/\(id).jsonl"
        }
        return loadFromFile(path: path)
    }

    private static func loadFromFile(path: String) -> (info: SessionInfo, messages: [ClaudeMessage])? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // First line is SessionInfo
        guard let infoData = lines[0].data(using: .utf8),
              let info = try? decoder.decode(SessionInfo.self, from: infoData) else {
            return nil
        }

        // Remaining lines are ClaudeMessages
        var messages: [ClaudeMessage] = []
        for line in lines.dropFirst() {
            if let data = line.data(using: .utf8),
               let msg = try? decoder.decode(ClaudeMessage.self, from: data) {
                messages.append(msg)
            }
        }

        return (info: info, messages: messages)
    }

    // MARK: - List

    /// List recent sessions sorted by updatedAt descending
    static func listRecent(limit: Int = 10) -> [SessionInfo] {
        ensureDir()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir) else {
            return []
        }

        var sessions: [SessionInfo] = []
        for file in files {
            guard file.hasSuffix(".jsonl"), file != "current.jsonl" else { continue }
            let path = sessionsDir + "/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let firstLine = content.components(separatedBy: "\n").first ?? ""
            guard let data = firstLine.data(using: .utf8),
                  let info = try? decoder.decode(SessionInfo.self, from: data) else { continue }
            sessions.append(info)
        }

        sessions.sort { $0.updatedAt > $1.updatedAt }
        return Array(sessions.prefix(limit))
    }

    // MARK: - Delete

    static func delete(id: String) {
        let path = sessionsDir + "/\(id).jsonl"
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Remove the current session file
    static func deleteCurrent() {
        try? FileManager.default.removeItem(atPath: currentFile)
    }

    /// Check if a current (auto-saved) session exists
    static func hasCurrentSession() -> Bool {
        FileManager.default.fileExists(atPath: currentFile)
    }

    // MARK: - Name Generation

    /// Generate a short name from the first user message (max ~50 chars)
    static func generateName(from message: String) -> String {
        let cleaned = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        if cleaned.count <= 50 {
            return cleaned
        }

        // Truncate at word boundary
        let prefix = String(cleaned.prefix(50))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "..."
        }
        return prefix + "..."
    }

    // MARK: - Helpers

    private static func ensureDir() {
        try? FileManager.default.createDirectory(
            atPath: sessionsDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
