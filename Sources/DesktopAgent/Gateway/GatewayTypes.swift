import Foundation

// MARK: - Gateway Configuration

struct GatewayConfig: Codable {
    var telegram: TelegramGatewayConfig?
    var whatsapp: WhatsAppGatewayConfig?
    var slack: SlackGatewayConfig?
    var discord: DiscordGatewayConfig?
    var watch: WatchGatewayConfig?
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
    var allowedUsers: [String]?    // Slack user ID whitelist (nil = allow all)
    var systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case enabled, botToken = "bot_token", appToken = "app_token"
        case allowedChannels = "allowed_channels", allowedUsers = "allowed_users"
        case systemPrompt = "system_prompt"
    }
}

struct DiscordGatewayConfig: Codable {
    var enabled: Bool
    var botToken: String
    var allowedGuilds: [String]?
    var allowedUsers: [String]?    // Discord user ID whitelist (nil = allow all)
    var systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case enabled, botToken = "bot_token", allowedGuilds = "allowed_guilds"
        case allowedUsers = "allowed_users", systemPrompt = "system_prompt"
    }
}

struct WatchGatewayConfig: Codable {
    var enabled: Bool
    var port: Int?                     // HTTP server port (default: 8375)
    var serviceName: String?           // Bonjour service name (default: "osai")
    var allowedDevices: [String]?      // Device ID whitelist (nil = allow all)
    var maxResponseLength: Int?        // Truncate responses for watch (default: 500)
    var systemPrompt: String?
    var healthTrackingEnabled: Bool?    // Allow watch to send health data (default: true)
    var locationTrackingEnabled: Bool?  // Allow watch to send location data (default: true)
    var complicationsEnabled: Bool?     // Serve complication data (default: true)
    var shortcutsEnabled: Bool?         // Allow Siri shortcut triggers (default: true)

    enum CodingKeys: String, CodingKey {
        case enabled, port
        case serviceName = "service_name"
        case allowedDevices = "allowed_devices"
        case maxResponseLength = "max_response_length"
        case systemPrompt = "system_prompt"
        case healthTrackingEnabled = "health_tracking_enabled"
        case locationTrackingEnabled = "location_tracking_enabled"
        case complicationsEnabled = "complications_enabled"
        case shortcutsEnabled = "shortcuts_enabled"
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

// MARK: - Gateway Delivery Context (for tasks scheduled from gateway)

struct GatewayDeliveryContext {
    let platform: String
    let chatId: String
    let userId: String
}

// MARK: - Gateway Adapter Protocol

protocol GatewayAdapter: AnyObject {
    var platform: String { get }
    var isRunning: Bool { get }

    /// Start the adapter (begin polling/listening)
    func start() async throws

    /// Stop the adapter
    func stop()

    /// Set the message handler callback (fire-and-forget: responses sent via sendMessage)
    func onMessage(_ handler: @escaping (GatewayMessage) async -> Void)

    /// Send a message to a specific chat (for streaming responses)
    func sendMessage(chatId: String, text: String) async

    /// Send a typing indicator to a chat (platforms auto-expire after ~5-10s)
    func sendTypingIndicator(chatId: String) async
}
