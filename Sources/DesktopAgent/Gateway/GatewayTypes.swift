import Foundation

// MARK: - Gateway Configuration

struct GatewayConfig: Codable {
    var telegram: TelegramGatewayConfig?
    var whatsapp: WhatsAppGatewayConfig?
    var slack: SlackGatewayConfig?
    var discord: DiscordGatewayConfig?
}

struct TelegramGatewayConfig: Codable {
    var enabled: Bool
    var botToken: String
    var allowedUsers: [Int]?       // Telegram user IDs whitelist (nil = allow all)
    var systemPrompt: String?      // Optional override for gateway context

    enum CodingKeys: String, CodingKey {
        case enabled, botToken = "bot_token", allowedUsers = "allowed_users", systemPrompt = "system_prompt"
    }
}

struct WhatsAppGatewayConfig: Codable {
    var enabled: Bool
    var allowedJIDs: [String]?     // Whitelist of JIDs (nil = allow all)
    var pollInterval: Int?         // Seconds between polls (default: 5)
    var systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case enabled, allowedJIDs = "allowed_jids", pollInterval = "poll_interval", systemPrompt = "system_prompt"
    }
}

struct SlackGatewayConfig: Codable {
    var enabled: Bool
    var botToken: String
    var appToken: String           // For Socket Mode
    var allowedChannels: [String]?
    var systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case enabled, botToken = "bot_token", appToken = "app_token"
        case allowedChannels = "allowed_channels", systemPrompt = "system_prompt"
    }
}

struct DiscordGatewayConfig: Codable {
    var enabled: Bool
    var botToken: String
    var allowedGuilds: [String]?
    var systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case enabled, botToken = "bot_token", allowedGuilds = "allowed_guilds", systemPrompt = "system_prompt"
    }
}

// MARK: - Gateway Message (normalized)

struct GatewayMessage {
    let platform: String           // "telegram", "whatsapp", "slack", "discord"
    let chatId: String             // Platform-specific chat identifier
    let userId: String             // Platform-specific user identifier
    let userName: String           // Display name
    let text: String
    let timestamp: Date
    let replyToMessageId: String?  // For threading
}

// MARK: - Gateway Adapter Protocol

protocol GatewayAdapter: AnyObject {
    var platform: String { get }
    var isRunning: Bool { get }

    /// Start the adapter (begin polling/listening)
    func start() async throws

    /// Stop the adapter
    func stop()

    /// Set the message handler callback
    func onMessage(_ handler: @escaping (GatewayMessage) async -> String)
}
