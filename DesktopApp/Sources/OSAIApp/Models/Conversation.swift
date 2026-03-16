import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

/// Represents an activity happening during processing (MCP loading, tool call, etc.)
struct ActivityItem: Identifiable, Equatable {
    let id: String
    let type: ActivityType
    var label: String
    var detail: String
    var isComplete: Bool
    var startTime: Date
    var durationMs: Int?
    var success: Bool?
    var output: String?

    enum ActivityType: String, Equatable {
        case mcpLoading    // Loading MCP server
        case toolCall      // Running a tool
        case thinking      // Agent thinking
        case agentRoute    // Specialized agent selected
        case status        // Informational status message
    }

    var icon: String {
        switch type {
        case .mcpLoading: return "puzzlepiece.extension"
        case .toolCall: return "wrench.and.screwdriver"
        case .thinking: return "brain"
        case .agentRoute: return "arrow.triangle.branch"
        case .status: return "info.circle"
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool = false
    var activities: [ActivityItem] = []
    var toolName: String?
    var toolResult: String?
    var agentName: String?

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming &&
        lhs.activities == rhs.activities && lhs.agentName == rhs.agentName
    }
}

struct Conversation: Identifiable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var agentName: String?

    var lastMessage: String {
        messages.last?.content ?? ""
    }

    var preview: String {
        let msg = messages.last(where: { $0.role == .assistant })?.content ?? messages.last?.content ?? ""
        return String(msg.prefix(80))
    }
}
