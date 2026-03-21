import Foundation
import SwiftUI

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

enum MessageReaction: String, Codable {
    case thumbsUp
    case thumbsDown
    case heart
    case laugh
    case thinking
    case star

    var sfSymbol: String {
        switch self {
        case .thumbsUp: return "hand.thumbsup"
        case .thumbsDown: return "hand.thumbsdown"
        case .heart: return "heart"
        case .laugh: return "face.smiling"
        case .thinking: return "questionmark.bubble"
        case .star: return "star"
        }
    }

    var sfSymbolFilled: String {
        switch self {
        case .thumbsUp: return "hand.thumbsup.fill"
        case .thumbsDown: return "hand.thumbsdown.fill"
        case .heart: return "heart.fill"
        case .laugh: return "face.smiling.fill"
        case .thinking: return "questionmark.bubble.fill"
        case .star: return "star.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .thumbsUp: return .green
        case .thumbsDown: return .red
        case .heart: return .pink
        case .laugh: return .yellow
        case .thinking: return .purple
        case .star: return .orange
        }
    }

    var emoji: String {
        switch self {
        case .thumbsUp: return "👍"
        case .thumbsDown: return "👎"
        case .heart: return "❤️"
        case .laugh: return "😂"
        case .thinking: return "🤔"
        case .star: return "⭐"
        }
    }

    /// All reactions in display order
    static let allReactions: [MessageReaction] = [.thumbsUp, .thumbsDown, .heart, .laugh, .thinking, .star]
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
        case mcpLoading       // Loading MCP server
        case toolCall         // Running a tool
        case thinking         // Agent thinking
        case agentRoute       // Specialized agent selected
        case agentDelegate    // Agent delegating to sub-agent
        case doomLoop         // Agent stuck in repetitive loop
        case compaction       // Context compaction occurred
        case status           // Informational status message
    }

    var icon: String {
        switch type {
        case .mcpLoading: return "puzzlepiece.extension"
        case .toolCall: return "wrench.and.screwdriver"
        case .thinking: return "brain"
        case .agentRoute: return "arrow.triangle.branch"
        case .agentDelegate: return "person.2.wave.2"
        case .doomLoop: return "exclamationmark.arrow.circlepath"
        case .compaction: return "arrow.down.right.and.arrow.up.left"
        case .status: return "info.circle"
        }
    }

    /// Parent agent name (for delegation tree rendering)
    var parentAgent: String?
    /// Sub-agent task description
    var taskDescription: String?
}

struct EditRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let content: String
    let editedAt: Date

    init(id: UUID = UUID(), content: String, editedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.editedAt = editedAt
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
    var agentMatchType: String?
    var reaction: MessageReaction?
    var isBookmarked: Bool = false
    /// Time in milliseconds from user send to first streaming text (assistant messages only)
    var responseTimeMs: Int?
    var editHistory: [EditRecord] = []
    var replyToMessageId: String?
    var annotation: String?
    var isPinned: Bool = false
    var suggestions: [String] = []
    /// Session summary data (cost, turns, cache hits, context %)
    var sessionCost: Double?
    var sessionTurns: Int?
    var sessionContextPct: Int?

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming &&
        lhs.activities == rhs.activities && lhs.agentName == rhs.agentName && lhs.reaction == rhs.reaction &&
        lhs.isBookmarked == rhs.isBookmarked && lhs.responseTimeMs == rhs.responseTimeMs &&
        lhs.editHistory == rhs.editHistory && lhs.replyToMessageId == rhs.replyToMessageId &&
        lhs.annotation == rhs.annotation && lhs.isPinned == rhs.isPinned &&
        lhs.suggestions == rhs.suggestions && lhs.sessionCost == rhs.sessionCost
    }
}

struct Conversation: Identifiable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var agentName: String?
    var modelId: String?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var tags: [String] = []
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var branchedFromId: String?
    var branchedAtMessageIndex: Int?
    var titleManuallySet: Bool = false
    var summary: String?
    var colorLabel: String?

    /// Estimated cost based on typical rates ($3/M input, $15/M output for Sonnet)
    var estimatedCost: Double {
        let inputCost = Double(totalInputTokens) / 1_000_000.0 * 3.0
        let outputCost = Double(totalOutputTokens) / 1_000_000.0 * 15.0
        return inputCost + outputCost
    }

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    /// The date of the most recent message, or createdAt if no messages exist.
    var lastUpdated: Date {
        messages.last?.timestamp ?? createdAt
    }

    var lastMessage: String {
        messages.last?.content ?? ""
    }

    var preview: String {
        let msg = messages.last(where: { $0.role == .assistant })?.content ?? messages.last?.content ?? ""
        return String(msg.prefix(80))
    }
}
