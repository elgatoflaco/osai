import Foundation

// MARK: - Session Store (saves/loads conversation history to disk)

final class SessionStore {
    static let sessionsDir = NSHomeDirectory() + "/.desktop-agent/sessions"

    /// Save conversation history for a session (keeps last 20 messages)
    /// Ensures saved history starts with a user message (not a tool_result)
    static func save(sessionKey: String, messages: [ClaudeMessage]) {
        ensureDir()
        let recent = messages.suffix(20)

        // Find the first valid starting index: a user message that isn't a tool_result.
        // Uses drop(while:) for O(n) instead of repeated removeFirst() which is O(n²).
        let trimmed = Array(recent.drop(while: { msg in
            if msg.role == "assistant" { return true }
            if msg.role == "user" && hasToolResult(msg) { return true }
            return false
        }))

        let path = filePath(for: sessionKey)
        do {
            let data = try JSONEncoder().encode(trimmed)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            // Silently fail — session persistence is best-effort
        }
    }

    /// Load conversation history for a session (returns empty if none)
    /// Validates that tool_result blocks have matching tool_use blocks
    static func load(sessionKey: String) -> [ClaudeMessage] {
        let path = filePath(for: sessionKey)
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        do {
            let messages = try JSONDecoder().decode([ClaudeMessage].self, from: data)
            return validate(messages)
        } catch {
            return []
        }
    }

    /// Validate that all tool_result blocks have matching tool_use in the previous message
    private static func validate(_ messages: [ClaudeMessage]) -> [ClaudeMessage] {
        var valid: [ClaudeMessage] = []
        for msg in messages {
            if msg.role == "user" && hasToolResult(msg) {
                // Check that the previous message (assistant) has matching tool_use IDs
                guard let prev = valid.last, prev.role == "assistant" else {
                    // No preceding assistant message — skip this broken message
                    continue
                }
                let toolUseIds = Set(prev.content.compactMap { content -> String? in
                    if case .toolUse(let id, _, _, _) = content { return id }
                    return nil
                })
                let toolResultIds = Set(msg.content.compactMap { content -> String? in
                    if case .toolResult(let id, _) = content { return id }
                    return nil
                })
                // If any result ID is missing from the tool_use set, skip this message pair
                if !toolResultIds.isSubset(of: toolUseIds) {
                    valid.removeLast() // Remove the orphaned assistant message too
                    continue
                }
            }
            valid.append(msg)
        }
        return valid
    }

    private static func hasToolResult(_ message: ClaudeMessage) -> Bool {
        return message.content.contains { content in
            if case .toolResult = content { return true }
            return false
        }
    }

    /// Delete a session
    static func delete(sessionKey: String) {
        let path = filePath(for: sessionKey)
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Helpers

    private static func filePath(for sessionKey: String) -> String {
        // Sanitize session key for filename safety
        let safe = sessionKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return sessionsDir + "/" + safe + ".json"
    }

    private static func ensureDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sessionsDir) {
            try? fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        }
    }
}
