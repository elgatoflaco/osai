import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import UserNotifications
import AVFoundation

// MARK: - App Notification

enum NotificationType {
    case info, success, warning, error

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return Color.blue
        case .success: return AppTheme.success
        case .warning: return AppTheme.warning
        case .error: return AppTheme.error
        }
    }
}

struct AppNotification: Identifiable {
    let id = UUID()
    let timestamp: Date
    let title: String
    let message: String
    let type: NotificationType
    var isRead: Bool = false

    /// Returns a human-readable relative timestamp string.
    var relativeTime: String {
        let elapsed = Date().timeIntervalSince(timestamp)
        if elapsed < 60 { return "just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(elapsed / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(elapsed / 86400)
        return "\(days)d ago"
    }
}

// MARK: - Toast

enum ToastType {
    case success, error, info

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return AppTheme.success
        case .error: return AppTheme.error
        case .info: return AppTheme.accent
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

enum ConversationSortOption: String, CaseIterable, Identifiable {
    case lastUpdated = "lastUpdated"
    case created = "created"
    case alphabetical = "alphabetical"
    case messageCount = "messageCount"
    case tokenUsage = "tokenUsage"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastUpdated: return "Last Updated"
        case .created: return "Date Created"
        case .alphabetical: return "Alphabetical"
        case .messageCount: return "Message Count"
        case .tokenUsage: return "Token Usage"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .lastUpdated: return "clock"
        case .created: return "calendar"
        case .alphabetical: return "textformat.abc"
        case .messageCount: return "bubble.left.and.bubble.right"
        case .tokenUsage: return "number"
        case .custom: return "hand.draw"
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case failed = "Failed"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .active: return "bolt.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case chat = "Chat"
    case agents = "Agents"
    case tasks = "Tasks"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .agents: return "person.3.fill"
        case .tasks: return "clock.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .chat: return "2"
        case .agents: return "3"
        case .tasks: return "4"
        case .settings: return "5"
        }
    }
}

// MARK: - Prompt Template

struct PromptTemplate: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var content: String
    var category: String  // "Code", "Writing", "Research", "Custom"
    var icon: String      // SF Symbol name
    let createdAt: Date

    static let builtInDefaults: [PromptTemplate] = [
        PromptTemplate(id: "builtin-code-review", name: "Code review", content: "Please review the following code for bugs, readability, and best practices. Suggest improvements:\n\n", category: "Code", icon: "magnifyingglass.circle", createdAt: Date(timeIntervalSince1970: 0)),
        PromptTemplate(id: "builtin-eli5", name: "Explain like I'm 5", content: "Explain the following concept in simple terms that a 5-year-old could understand:\n\n", category: "Writing", icon: "face.smiling", createdAt: Date(timeIntervalSince1970: 0)),
        PromptTemplate(id: "builtin-translate-spanish", name: "Translate to Spanish", content: "Translate the following text to Spanish, preserving tone and meaning:\n\n", category: "Writing", icon: "globe", createdAt: Date(timeIntervalSince1970: 0)),
        PromptTemplate(id: "builtin-summarize", name: "Summarize this", content: "Provide a concise summary of the following, highlighting the key points:\n\n", category: "Research", icon: "doc.text.magnifyingglass", createdAt: Date(timeIntervalSince1970: 0)),
        PromptTemplate(id: "builtin-unit-tests", name: "Write unit tests", content: "Write comprehensive unit tests for the following code. Cover edge cases and happy paths:\n\n", category: "Code", icon: "checkmark.shield", createdAt: Date(timeIntervalSince1970: 0)),
    ]

    static let categories = ["Code", "Writing", "Research", "Custom"]

    static let categoryIcons: [String: String] = [
        "Code": "chevron.left.forwardslash.chevron.right",
        "Writing": "pencil",
        "Research": "magnifyingglass",
        "Custom": "star",
    ]
}

// MARK: - Chat Quick Action

struct ChatQuickAction: Identifiable, Codable, Equatable {
    let id: String
    let label: String
    let icon: String   // SF Symbol name
    let prompt: String

    static let defaults: [ChatQuickAction] = [
        ChatQuickAction(id: "summarize",   label: "Summarize",    icon: "doc.text.magnifyingglass", prompt: "Summarize our conversation so far"),
        ChatQuickAction(id: "continue",    label: "Continue",     icon: "arrow.right.circle",       prompt: "Continue from where you left off"),
        ChatQuickAction(id: "explain",     label: "Explain",      icon: "lightbulb",                prompt: "Explain the last response in simpler terms"),
        ChatQuickAction(id: "fix_errors",  label: "Fix errors",   icon: "hammer",                   prompt: "Check for and fix any errors in the code above"),
        ChatQuickAction(id: "translate",   label: "Translate",    icon: "globe",                    prompt: "Translate the above to Spanish"),
        ChatQuickAction(id: "shorter",     label: "Make shorter", icon: "arrow.down.right.and.arrow.up.left", prompt: "Make the last response more concise"),
        ChatQuickAction(id: "expand",      label: "Expand",       icon: "arrow.up.left.and.arrow.down.right", prompt: "Expand on the last point with more detail"),
    ]
}

// MARK: - Model Definition

struct ModelDefinition: Identifiable, Equatable {
    let id: String          // e.g. "anthropic/claude-sonnet-4-20250514"
    let displayName: String // e.g. "Claude Sonnet 4"
    let shortName: String   // e.g. "Sonnet 4"
    let provider: String    // e.g. "Anthropic"
    let providerKey: String // e.g. "anthropic" — matches apiKeys dictionary
    let tag: String         // e.g. "Smart", "Fast", "Vision"
    let icon: String        // SF Symbol name

    static func == (lhs: ModelDefinition, rhs: ModelDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

let allModelDefinitions: [ModelDefinition] = [
    // Anthropic
    ModelDefinition(id: "anthropic/claude-sonnet-4-20250514", displayName: "Claude Sonnet 4", shortName: "Sonnet 4", provider: "Anthropic", providerKey: "anthropic", tag: "Smart", icon: "brain.head.profile"),
    ModelDefinition(id: "anthropic/claude-opus-4-20250514", displayName: "Claude Opus 4", shortName: "Opus 4", provider: "Anthropic", providerKey: "anthropic", tag: "Powerful", icon: "brain"),
    ModelDefinition(id: "anthropic/claude-haiku-4-5-20251001", displayName: "Claude Haiku 3.5", shortName: "Haiku 3.5", provider: "Anthropic", providerKey: "anthropic", tag: "Fast", icon: "hare"),
    // OpenAI
    ModelDefinition(id: "openai/gpt-4o", displayName: "GPT-4o", shortName: "GPT-4o", provider: "OpenAI", providerKey: "openai", tag: "Vision", icon: "eye"),
    ModelDefinition(id: "openai/gpt-4o-mini", displayName: "GPT-4o Mini", shortName: "4o Mini", provider: "OpenAI", providerKey: "openai", tag: "Fast", icon: "hare"),
    ModelDefinition(id: "openai/o3", displayName: "o3", shortName: "o3", provider: "OpenAI", providerKey: "openai", tag: "Reasoning", icon: "lightbulb"),
    // Google
    ModelDefinition(id: "google/gemini-2.5-pro", displayName: "Gemini 2.5 Pro", shortName: "Gemini Pro", provider: "Google", providerKey: "google", tag: "Smart", icon: "brain.head.profile"),
    ModelDefinition(id: "google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", shortName: "Gemini Flash", provider: "Google", providerKey: "google", tag: "Fast", icon: "bolt"),
    // Other
    ModelDefinition(id: "claude-code", displayName: "Claude Code", shortName: "Claude Code", provider: "Local", providerKey: "claude-code", tag: "Local", icon: "terminal"),
]

// MARK: - Code Block

struct CodeBlock: Identifiable {
    let id = UUID()
    let language: String
    let code: String
    let messageIndex: Int

    /// File extension inferred from the language identifier.
    var fileExtension: String {
        switch language.lowercased() {
        case "swift": return ".swift"
        case "python", "py": return ".py"
        case "javascript", "js": return ".js"
        case "typescript", "ts": return ".ts"
        case "bash", "sh", "shell", "zsh": return ".sh"
        case "html": return ".html"
        case "css": return ".css"
        case "json": return ".json"
        case "rust", "rs": return ".rs"
        case "go", "golang": return ".go"
        case "ruby", "rb": return ".rb"
        case "yaml", "yml": return ".yml"
        case "c": return ".c"
        case "cpp", "c++": return ".cpp"
        case "java": return ".java"
        case "sql": return ".sql"
        case "xml": return ".xml"
        case "toml": return ".toml"
        case "markdown", "md": return ".md"
        default: return ".txt"
        }
    }

    var preview: String {
        let lines = code.components(separatedBy: "\n")
        return lines.prefix(3).joined(separator: "\n")
    }

    var lineCount: Int {
        code.components(separatedBy: "\n").count
    }
}

@MainActor
// MARK: - Conversation Template

enum TemplateCategory: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case development = "Development"
    case writing = "Writing"
    case research = "Research"
    case general = "General"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .writing: return "pencil.line"
        case .research: return "magnifyingglass"
        case .general: return "sparkles"
        }
    }
}

struct ConversationTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var icon: String
    var description: String
    var initialMessage: String
    var isBuiltIn: Bool
    var category: String

    init(id: UUID = UUID(), name: String, icon: String, description: String, initialMessage: String, isBuiltIn: Bool = true, category: String = "General") {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.initialMessage = initialMessage
        self.isBuiltIn = isBuiltIn
        self.category = category
    }

    static func == (lhs: ConversationTemplate, rhs: ConversationTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - System Stats

struct SystemStats {
    var cpuUsage: Double = 0.0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var uptime: TimeInterval = 0
    var processCount: Int = 0
}

// MARK: - Dashboard Section

enum DashboardSection: String, Codable, CaseIterable, Identifiable {
    case quickStart
    case gateway
    case stats
    case spending
    case tokenStats
    case analytics
    case chatInsights
    case performance
    case recentActivity
    case recentConversations
    case systemHealth
    case systemStatus
    case activity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quickStart: return "Quick Start"
        case .gateway: return "Gateway Status"
        case .stats: return "Quick Stats"
        case .spending: return "Monthly Spending"
        case .tokenStats: return "Token & Cost Statistics"
        case .analytics: return "Usage Analytics"
        case .chatInsights: return "Chat Insights"
        case .performance: return "Performance"
        case .recentActivity: return "Recent Activity"
        case .recentConversations: return "Recent Conversations"
        case .systemHealth: return "System Health"
        case .systemStatus: return "System Status"
        case .activity: return "Your Activity"
        }
    }

    var icon: String {
        switch self {
        case .quickStart: return "bolt.fill"
        case .gateway: return "power"
        case .stats: return "square.grid.2x2"
        case .spending: return "chart.bar"
        case .tokenStats: return "number.circle"
        case .analytics: return "chart.bar.xaxis"
        case .chatInsights: return "lightbulb"
        case .performance: return "gauge.with.dots.needle.33percent"
        case .recentActivity: return "clock.arrow.circlepath"
        case .recentConversations: return "bubble.left.and.text.bubble.right"
        case .systemHealth: return "server.rack"
        case .systemStatus: return "cpu"
        case .activity: return "flame"
        }
    }

    static let defaultOrder: [DashboardSection] = [
        .quickStart, .activity, .gateway, .stats, .spending, .recentConversations, .tokenStats, .analytics, .chatInsights, .performance, .recentActivity, .systemHealth, .systemStatus
    ]
}

// MARK: - Daily Token Usage

struct DailyTokenUsage: Identifiable, Codable, Equatable {
    var id: String { dateKey }
    let dateKey: String      // "yyyy-MM-dd"
    let date: Date
    var inputTokens: Int
    var outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }

    /// Estimated cost using a rough average across models (~$3/MTok input, ~$15/MTok output)
    var estimatedCost: Double {
        (Double(inputTokens) * 3.0 + Double(outputTokens) * 15.0) / 1_000_000.0
    }

    /// Short day label (Mon, Tue, etc.)
    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Agent Status

enum AgentStatus {
    case recentlyUsed   // Used within last 24 hours
    case available      // API key configured, ready to use
    case noKey          // No API key for the agent's provider

    var dotColor: Color {
        switch self {
        case .recentlyUsed: return AppTheme.success
        case .available: return AppTheme.warning
        case .noKey: return AppTheme.textMuted
        }
    }

    var label: String {
        switch self {
        case .recentlyUsed: return "Recently used"
        case .available: return "Available"
        case .noKey: return "No API key"
        }
    }
}

// MARK: - Search Result

enum SearchResultCategory: String, CaseIterable {
    case recentSearch = "Recent Searches"
    case conversation = "Conversations"
    case message = "Messages"
    case agent = "Agents"
    case template = "Templates"
    case setting = "Settings"

    var icon: String {
        switch self {
        case .recentSearch: return "clock.arrow.circlepath"
        case .conversation: return "bubble.left.and.bubble.right"
        case .message: return "text.bubble"
        case .agent: return "person.3"
        case .template: return "doc.text"
        case .setting: return "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .recentSearch: return AppTheme.textSecondary
        case .conversation: return AppTheme.accent
        case .message: return .green
        case .agent: return .purple
        case .template: return .orange
        case .setting: return .blue
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let category: SearchResultCategory
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    /// Matched range in title for highlighting, if applicable
    var matchRange: Range<String.Index>?
}

class AppState: ObservableObject {
    // MARK: - Conversation Color Labels
    static let conversationColors: [(name: String, color: Color)] = [
        ("red", .red),
        ("orange", .orange),
        ("yellow", .yellow),
        ("green", .green),
        ("blue", .blue),
        ("purple", .purple),
        ("pink", .pink),
        ("teal", .teal)
    ]

    /// Returns the SwiftUI Color for a given color label name, or nil if not found.
    static func colorForLabel(_ name: String?) -> Color? {
        guard let name = name else { return nil }
        return conversationColors.first(where: { $0.name == name })?.color
    }

    @AppStorage("isDarkMode") var isDarkMode: Bool = true
    @AppStorage("sidebarCollapsed") var sidebarCollapsed: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("globalHotkeyEnabled") var globalHotkeyEnabled: Bool = true
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("notificationSound") var notificationSound: String = "default"
    @AppStorage("notifyOnTaskComplete") var notifyOnTaskComplete: Bool = true
    @AppStorage("notifyOnAgentRoute") var notifyOnAgentRoute: Bool = false
    @AppStorage("notifySoundEnabled") var notifySoundEnabled: Bool = true
    @AppStorage("compactMode") var compactMode: Bool = false
    @AppStorage("smartPasteEnabled") var smartPasteEnabled: Bool = true
    @AppStorage("displayDensity") var displayDensity: String = "comfortable"

    /// Message bubble padding based on display density
    var messagePadding: CGFloat {
        switch displayDensity {
        case "compact": return 8
        case "spacious": return 18
        default: return 12
        }
    }

    /// Vertical spacing between messages based on display density
    var messageSpacing: CGFloat {
        switch displayDensity {
        case "compact": return 4
        case "spacious": return 14
        default: return 8
        }
    }

    /// Avatar/icon size based on display density
    var avatarSize: CGFloat {
        switch displayDensity {
        case "compact": return 20
        case "spacious": return 32
        default: return 26
        }
    }
    // MARK: - Budget Settings
    @AppStorage("dailyBudget") var dailyBudget: Double = 5.0
    @AppStorage("monthlyBudget") var monthlyBudget: Double = 100.0
    @AppStorage("budgetAlertsEnabled") var budgetAlertsEnabled: Bool = true

    /// Daily spending as a percentage of daily budget (0.0 to 1.0+).
    var dailySpendingPercentage: Double {
        guard dailyBudget > 0 else { return 0 }
        return costToday / dailyBudget
    }

    /// Monthly spending as a percentage of monthly budget (0.0 to 1.0+).
    var monthlySpendingPercentage: Double {
        guard monthlyBudget > 0 else { return 0 }
        return costMonth / monthlyBudget
    }

    /// Tracks whether we already sent a budget alert this session to avoid spam.
    private var dailyBudgetAlertSent80 = false
    private var dailyBudgetAlertSent100 = false
    private var monthlyBudgetAlertSent80 = false
    private var monthlyBudgetAlertSent100 = false

    /// Check budget thresholds and send notifications when approaching or exceeding limits.
    func checkBudgetAlert() {
        guard budgetAlertsEnabled else { return }

        // Daily budget checks
        if dailyBudget > 0 {
            let pct = dailySpendingPercentage
            if pct >= 1.0 && !dailyBudgetAlertSent100 {
                dailyBudgetAlertSent100 = true
                let msg = String(format: "Daily budget of $%.2f exceeded ($%.2f spent)", dailyBudget, costToday)
                sendNotification(title: "OSAI Budget Alert", body: msg)
                addNotification(title: "Budget Exceeded", message: msg, type: .error)
                showToast(msg, type: .error)
            } else if pct >= 0.8 && !dailyBudgetAlertSent80 {
                dailyBudgetAlertSent80 = true
                let msg = String(format: "Approaching daily budget: $%.2f of $%.2f (%.0f%%)", costToday, dailyBudget, pct * 100)
                sendNotification(title: "OSAI Budget Warning", body: msg)
                addNotification(title: "Budget Warning", message: msg, type: .warning)
                showToast(msg, type: .info)
            }
        }

        // Monthly budget checks
        if monthlyBudget > 0 {
            let pct = monthlySpendingPercentage
            if pct >= 1.0 && !monthlyBudgetAlertSent100 {
                monthlyBudgetAlertSent100 = true
                let msg = String(format: "Monthly budget of $%.2f exceeded ($%.2f spent)", monthlyBudget, costMonth)
                sendNotification(title: "OSAI Budget Alert", body: msg)
                addNotification(title: "Budget Exceeded", message: msg, type: .error)
                showToast(msg, type: .error)
            } else if pct >= 0.8 && !monthlyBudgetAlertSent80 {
                monthlyBudgetAlertSent80 = true
                let msg = String(format: "Approaching monthly budget: $%.2f of $%.2f (%.0f%%)", costMonth, monthlyBudget, pct * 100)
                sendNotification(title: "OSAI Budget Warning", body: msg)
                addNotification(title: "Budget Warning", message: msg, type: .warning)
                showToast(msg, type: .info)
            }
        }
    }

    /// Reset the daily spending counter and alert flags.
    func resetDailySpending() {
        costToday = 0.0
        tokensToday = 0
        dailyBudgetAlertSent80 = false
        dailyBudgetAlertSent100 = false
        showToast("Daily spending counter reset", type: .success)
    }

    @AppStorage("floatOnTop") var floatOnTop: Bool = false
    @AppStorage("windowOpacity") var windowOpacity: Double = 1.0
    @AppStorage("quickActionsCollapsed") var quickActionsCollapsed: Bool = false
    @AppStorage("textToSpeechEnabled") var textToSpeechEnabled: Bool = true
    @AppStorage("sidebarWidth") var sidebarWidth: Double = 280
    @AppStorage("sidebarWidthPreset") var sidebarWidthPreset: Int = 1 // 0=narrow(200), 1=default(280), 2=wide(380)

    /// Width values for each sidebar preset index.
    static let sidebarPresetWidths: [Double] = [200, 280, 380]

    /// Cycle through sidebar width presets: Narrow -> Default -> Wide -> Narrow ...
    func cycleSidebarPreset() {
        let next = (sidebarWidthPreset + 1) % Self.sidebarPresetWidths.count
        sidebarWidthPreset = next
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            sidebarWidth = Self.sidebarPresetWidths[next]
        }
    }

    /// Toggle the sidebar between collapsed and expanded states.
    func toggleSidebarCollapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            sidebarCollapsed.toggle()
        }
    }

    @AppStorage("timestampDisplay") var timestampDisplay: String = "hover"
    @AppStorage("chatFontSize") var chatFontSize: Double = 13.0
    @AppStorage("syntaxTheme") var syntaxTheme: String = "Monokai"
    @AppStorage("autoScrollEnabled") var autoScrollEnabled: Bool = true
    @AppStorage("codeWordWrap") var codeWordWrap: Bool = false
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true

    // MARK: - Streaks & Gamification

    @AppStorage("currentStreak") var currentStreak: Int = 0
    @AppStorage("longestStreak") var longestStreak: Int = 0
    @AppStorage("lastActiveDate") var lastActiveDate: String = ""
    @AppStorage("totalConversationsCreated") var totalConversationsCreated: Int = 0
    @AppStorage("totalMessagesCount") var totalMessagesCount: Int = 0
    @AppStorage("dailyActivityHeatmap") var dailyActivityHeatmap: String = "" // JSON: {"2026-03-16":5,...}

    /// Called on app launch to update the usage streak based on consecutive days.
    func updateStreak() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        if lastActiveDate == todayStr {
            // Already recorded today, nothing to do
            return
        }

        if let lastDate = formatter.date(from: lastActiveDate) {
            let calendar = Calendar.current
            let daysBetween = calendar.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            if daysBetween == 1 {
                // Consecutive day
                currentStreak += 1
            } else if daysBetween > 1 {
                // Streak broken
                currentStreak = 1
            }
        } else {
            // First ever launch or invalid date
            currentStreak = 1
        }

        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }

        lastActiveDate = todayStr
    }

    /// Returns milestone text when the user hits notable conversation counts.
    func checkMilestone() -> String? {
        switch totalConversationsCreated {
        case 7: return "7 conversations - Getting started!"
        case 25: return "25 conversations - Regular user!"
        case 50: return "50 conversations - Power user!"
        case 100: return "100 conversations - Centurion!"
        case 250: return "250 conversations - Expert!"
        case 500: return "500 conversations - Legend!"
        case 1000: return "1,000 conversations - GOAT!"
        default: return nil
        }
    }

    /// Emoji indicator for the current streak level.
    var streakEmoji: String {
        if currentStreak >= 30 { return "star.fill" }
        if currentStreak >= 7 { return "flame.fill" }
        if currentStreak >= 1 { return "flame" }
        return "flame"
    }

    /// Records a message for today's heatmap data.
    func recordDailyActivity() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        var heatmap = parseDailyHeatmap()
        heatmap[todayStr, default: 0] += 1
        // Keep only last 30 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoffStr = formatter.string(from: cutoff)
        heatmap = heatmap.filter { $0.key >= cutoffStr }

        if let data = try? JSONSerialization.data(withJSONObject: heatmap),
           let str = String(data: data, encoding: .utf8) {
            dailyActivityHeatmap = str
        }
    }

    /// Parses the stored heatmap JSON into a dictionary.
    func parseDailyHeatmap() -> [String: Int] {
        guard !dailyActivityHeatmap.isEmpty,
              let data = dailyActivityHeatmap.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            return [:]
        }
        return dict
    }

    /// Returns message counts for the last 7 days (oldest first).
    func last7DaysActivity() -> [(date: String, count: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let heatmap = parseDailyHeatmap()
        let calendar = Calendar.current

        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            let key = formatter.string(from: date)
            return (date: key, count: heatmap[key] ?? 0)
        }
    }

    // MARK: - Dashboard Customization

    @Published var showDashboardCustomizer: Bool = false

    /// Ordered list of visible dashboard sections, persisted to UserDefaults.
    @Published var visibleDashboardSections: [DashboardSection] = {
        if let data = UserDefaults.standard.data(forKey: "visibleDashboardSections"),
           let decoded = try? JSONDecoder().decode([DashboardSection].self, from: data) {
            return decoded
        }
        return DashboardSection.defaultOrder
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(visibleDashboardSections) {
                UserDefaults.standard.set(data, forKey: "visibleDashboardSections")
            }
        }
    }

    /// Set of collapsed (minimized) dashboard section keys, persisted to UserDefaults.
    @Published var collapsedDashboardSections: Set<DashboardSection> = {
        if let data = UserDefaults.standard.data(forKey: "collapsedDashboardSections"),
           let decoded = try? JSONDecoder().decode(Set<DashboardSection>.self, from: data) {
            return decoded
        }
        return []
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(collapsedDashboardSections) {
                UserDefaults.standard.set(data, forKey: "collapsedDashboardSections")
            }
        }
    }

    func isSectionVisible(_ section: DashboardSection) -> Bool {
        visibleDashboardSections.contains(section)
    }

    func isSectionCollapsed(_ section: DashboardSection) -> Bool {
        collapsedDashboardSections.contains(section)
    }

    func toggleSectionCollapsed(_ section: DashboardSection) {
        if collapsedDashboardSections.contains(section) {
            collapsedDashboardSections.remove(section)
        } else {
            collapsedDashboardSections.insert(section)
        }
    }

    func toggleSectionVisibility(_ section: DashboardSection) {
        if let idx = visibleDashboardSections.firstIndex(of: section) {
            visibleDashboardSections.remove(at: idx)
        } else {
            visibleDashboardSections.append(section)
        }
    }

    func moveSectionUp(_ section: DashboardSection) {
        guard let idx = visibleDashboardSections.firstIndex(of: section), idx > 0 else { return }
        visibleDashboardSections.swapAt(idx, idx - 1)
    }

    func moveSectionDown(_ section: DashboardSection) {
        guard let idx = visibleDashboardSections.firstIndex(of: section), idx < visibleDashboardSections.count - 1 else { return }
        visibleDashboardSections.swapAt(idx, idx + 1)
    }

    func resetDashboardSections() {
        visibleDashboardSections = DashboardSection.defaultOrder
        collapsedDashboardSections = []
    }

    // MARK: - Input History

    @Published var inputHistory: [String] = {
        UserDefaults.standard.stringArray(forKey: "inputHistory") ?? []
    }() {
        didSet {
            UserDefaults.standard.set(inputHistory, forKey: "inputHistory")
        }
    }

    /// Current position in history (-1 = not browsing)
    @Published private(set) var inputHistoryIndex: Int = -1

    /// Saves the current unsent draft when the user starts browsing history
    private var inputHistoryDraft: String = ""

    /// Whether the user is currently browsing input history (for UI indicator)
    var isBrowsingInputHistory: Bool {
        inputHistoryIndex >= 0
    }

    /// Human-readable history position string, e.g. "3/12"
    var inputHistoryPositionLabel: String {
        guard inputHistoryIndex >= 0 else { return "" }
        return "\(inputHistoryIndex + 1)/\(inputHistory.count)"
    }

    /// Appends text to the input history (max 50 items, dedup consecutive).
    func addToInputHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Deduplicate consecutive entries
        if inputHistory.last == trimmed { return }
        inputHistory.append(trimmed)
        // Cap at 50 items
        if inputHistory.count > 50 {
            inputHistory.removeFirst(inputHistory.count - 50)
        }
        resetInputHistoryNavigation()
    }

    /// Navigate input history. direction: -1 = older, +1 = newer.
    /// Returns the text to display, or nil if navigation is not possible.
    func navigateInputHistory(direction: Int, currentText: String) -> String? {
        guard !inputHistory.isEmpty else { return nil }

        if inputHistoryIndex == -1 {
            // Not browsing yet — only allow going backward
            guard direction == -1 else { return nil }
            inputHistoryDraft = currentText
            inputHistoryIndex = inputHistory.count - 1
            return inputHistory[inputHistoryIndex]
        }

        let newIndex = inputHistoryIndex + direction

        if newIndex < 0 {
            // Already at the oldest entry
            return nil
        }

        if newIndex >= inputHistory.count {
            // Past the newest — restore draft
            inputHistoryIndex = -1
            return inputHistoryDraft
        }

        inputHistoryIndex = newIndex
        return inputHistory[inputHistoryIndex]
    }

    /// Reset history browsing state (call when user types manually or sends).
    func resetInputHistoryNavigation() {
        inputHistoryIndex = -1
        inputHistoryDraft = ""
    }

    // MARK: - Universal Search (Command Palette)

    @Published var recentSearches: [String] = {
        UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    }() {
        didSet {
            UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
        }
    }

    /// Adds a query to recent searches (max 5, deduped, most recent first).
    func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 5 {
            recentSearches = Array(recentSearches.prefix(5))
        }
    }

    /// Clears all recent searches.
    func clearRecentSearches() {
        recentSearches = []
    }

    /// Universal search across conversations, messages, agents, templates, and settings.
    func universalSearch(query: String) -> [SearchResult] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var results: [SearchResult] = []

        // -- Conversations (by title and summary) --
        for conv in conversations {
            let titleLower = conv.title.lowercased()
            let summaryLower = (conv.summary ?? "").lowercased()
            if titleLower.contains(q) || summaryLower.contains(q) {
                let lastMsg = conv.messages.last?.content ?? ""
                let subtitle = lastMsg.isEmpty ? "\(conv.messages.count) messages" : String(lastMsg.prefix(60))
                results.append(SearchResult(
                    category: .conversation,
                    title: conv.title,
                    subtitle: subtitle,
                    icon: conv.agentName != nil ? "person.bubble" : "bubble.left.and.bubble.right",
                    action: { [weak self] in
                        self?.openConversation(conv)
                        self?.selectedTab = .chat
                    }
                ))
            }
        }

        // -- Messages (by content) --
        for conv in conversations {
            for msg in conv.messages where msg.role == .user || msg.role == .assistant {
                let contentLower = msg.content.lowercased()
                if contentLower.contains(q) {
                    let excerpt: String
                    if let range = contentLower.range(of: q) {
                        let matchStart = contentLower.distance(from: contentLower.startIndex, to: range.lowerBound)
                        let excerptStart = max(0, matchStart - 20)
                        let startIdx = msg.content.index(msg.content.startIndex, offsetBy: excerptStart)
                        let endIdx = msg.content.index(startIdx, offsetBy: min(80, msg.content.distance(from: startIdx, to: msg.content.endIndex)))
                        let prefixStr = excerptStart > 0 ? "..." : ""
                        let suffixStr = endIdx < msg.content.endIndex ? "..." : ""
                        excerpt = prefixStr + String(msg.content[startIdx..<endIdx]) + suffixStr
                    } else {
                        excerpt = String(msg.content.prefix(80))
                    }
                    let msgId = msg.id
                    results.append(SearchResult(
                        category: .message,
                        title: conv.title,
                        subtitle: excerpt,
                        icon: msg.role == .user ? "person" : "sparkles",
                        action: { [weak self] in
                            self?.openConversation(conv)
                            self?.selectedTab = .chat
                            self?.scrollToMessageId = msgId
                        }
                    ))
                }
                if results.filter({ $0.category == .message }).count >= 5 { break }
            }
            if results.filter({ $0.category == .message }).count >= 5 { break }
        }

        // -- Agents (by name and description) --
        for agent in agents {
            if agent.name.lowercased().contains(q) || agent.description.lowercased().contains(q) {
                results.append(SearchResult(
                    category: .agent,
                    title: agent.name,
                    subtitle: agent.description,
                    icon: agent.backendIcon,
                    action: { [weak self] in
                        guard let self = self else { return }
                        let conv = Conversation(
                            id: UUID().uuidString,
                            title: agent.name,
                            messages: [],
                            createdAt: Date(),
                            agentName: agent.name
                        )
                        self.conversations.insert(conv, at: 0)
                        self.activeConversation = conv
                        self.selectedTab = .chat
                    }
                ))
            }
        }

        // -- Templates (prompt templates + conversation templates by name) --
        for template in promptTemplates {
            if template.name.lowercased().contains(q) || template.category.lowercased().contains(q) {
                results.append(SearchResult(
                    category: .template,
                    title: template.name,
                    subtitle: "Prompt - \(template.category)",
                    icon: template.icon,
                    action: { [weak self] in
                        self?.selectedTab = .chat
                        self?.shouldFocusInput = true
                    }
                ))
            }
        }
        for template in allTemplates {
            if template.name.lowercased().contains(q) || template.description.lowercased().contains(q) {
                let alreadyHas = results.contains { $0.category == .template && $0.title == template.name }
                if !alreadyHas {
                    results.append(SearchResult(
                        category: .template,
                        title: template.name,
                        subtitle: template.description,
                        icon: template.icon,
                        action: { [weak self] in
                            self?.selectedTab = .chat
                        }
                    ))
                }
            }
        }

        // -- Settings (searchable labels) --
        let settingsItems: [(label: String, icon: String, tab: SidebarItem)] = [
            ("Dark Mode", "moon.fill", .settings),
            ("Accent Color", "paintpalette.fill", .settings),
            ("API Keys", "key.fill", .settings),
            ("Gateway", "bolt.fill", .settings),
            ("Notifications", "bell.fill", .settings),
            ("Compact Mode", "rectangle.compress.vertical", .settings),
            ("Font Size", "textformat.size", .settings),
            ("Float on Top", "pin.fill", .settings),
            ("Window Opacity", "circle.lefthalf.filled", .settings),
            ("Focus Mode", "eye.slash", .settings),
            ("Hotkey", "command", .settings),
            ("Budget", "dollarsign.circle", .settings),
            ("Display Density", "square.grid.3x3", .settings),
            ("Sidebar Width", "sidebar.left", .settings),
            ("Code Theme", "chevron.left.forwardslash.chevron.right", .settings),
            ("Auto Scroll", "arrow.down.to.line", .settings),
            ("Text to Speech", "speaker.wave.2", .settings),
            ("Timestamps", "clock", .settings),
            ("Quick Actions", "bolt.circle", .settings),
            ("Export Data", "square.and.arrow.up", .settings),
        ]
        for item in settingsItems {
            if item.label.lowercased().contains(q) {
                results.append(SearchResult(
                    category: .setting,
                    title: item.label,
                    subtitle: "Open Settings",
                    icon: item.icon,
                    action: { [weak self] in
                        self?.selectedTab = item.tab
                    }
                ))
            }
        }

        return results
    }

    /// Message ID to scroll to after opening a conversation from search.
    @Published var scrollToMessageId: String?

    @Published var selectedAccentColor: String = UserDefaults.standard.string(forKey: "selectedAccentColor") ?? "teal"

    /// Enabled quick actions shown in the chat toolbar. Persisted to UserDefaults.
    @Published var quickActions: [ChatQuickAction] = {
        if let data = UserDefaults.standard.data(forKey: "chatQuickActions"),
           let decoded = try? JSONDecoder().decode([ChatQuickAction].self, from: data) {
            return decoded
        }
        return ChatQuickAction.defaults
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(quickActions) {
                UserDefaults.standard.set(data, forKey: "chatQuickActions")
            }
        }
    }

    /// Saved prompt templates. Persisted to UserDefaults.
    @Published var promptTemplates: [PromptTemplate] = {
        if let data = UserDefaults.standard.data(forKey: "promptTemplates"),
           let decoded = try? JSONDecoder().decode([PromptTemplate].self, from: data) {
            return decoded
        }
        return PromptTemplate.builtInDefaults
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(promptTemplates) {
                UserDefaults.standard.set(data, forKey: "promptTemplates")
            }
        }
    }

    func savePromptTemplate(name: String, content: String, category: String, icon: String) {
        let template = PromptTemplate(
            id: UUID().uuidString,
            name: name,
            content: content,
            category: category,
            icon: icon,
            createdAt: Date()
        )
        promptTemplates.append(template)
    }

    func deletePromptTemplate(id: String) {
        promptTemplates.removeAll { $0.id == id }
    }

    func updatePromptTemplate(_ template: PromptTemplate) {
        if let index = promptTemplates.firstIndex(where: { $0.id == template.id }) {
            promptTemplates[index] = template
        }
    }

    // MARK: - Window State Persistence

    /// Debounce timer for saving window frame
    private var windowFrameSaveTask: Task<Void, Never>?

    /// Save window frame to UserDefaults (debounced)
    func saveWindowFrame(_ frame: CGRect) {
        windowFrameSaveTask?.cancel()
        windowFrameSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let dict: [String: Double] = [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "w": frame.size.width,
                "h": frame.size.height
            ]
            UserDefaults.standard.set(dict, forKey: "windowFrame")
        }
    }

    /// Restore saved window frame, or nil if not saved
    var savedWindowFrame: CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "windowFrame"),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Apply float-on-top and opacity to the main window
    func applyWindowSettings() {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.className.contains("AppKitWindow") }) ?? NSApplication.shared.windows.first else { return }
        window.level = floatOnTop ? .floating : .normal
        window.alphaValue = CGFloat(windowOpacity)
    }

    func toggleFloatOnTop() {
        floatOnTop.toggle()
        applyWindowSettings()
    }

    func toggleCompactMode() {
        compactMode.toggle()
    }

    func increaseFontSize() {
        chatFontSize = min(chatFontSize + 1, 24)
    }

    func decreaseFontSize() {
        chatFontSize = max(chatFontSize - 1, 10)
    }

    func resetFontSize() {
        chatFontSize = 13
    }

    @Published var selectedTab: SidebarItem = .home
    @Published var agents: [AgentInfo] = []
    @Published var tasks: [TaskInfo] = []
    @Published var taskFilter: TaskFilter = .all
    @Published var taskSearchQuery: String = ""

    var filteredTasks: [TaskInfo] {
        var result = tasks

        // Apply status filter
        switch taskFilter {
        case .all:
            break
        case .active:
            result = result.filter { $0.enabled }
        case .completed:
            result = result.filter { !$0.enabled && $0.runCount > 0 }
        case .failed:
            result = result.filter { $0.isOverdue }
        }

        // Apply search query
        let query = taskSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.id.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                $0.command.lowercased().contains(query)
            }
        }

        return result
    }
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var unreadConversationIds: Set<String> = []
    @Published var mergeTargetId: String?

    // MARK: - Calendar Filter
    @Published var calendarFilterDate: Date?
    @AppStorage("showSidebarCalendar") var showSidebarCalendar: Bool = false

    /// Returns the set of day-of-month numbers that have conversations in the given month.
    func conversationDatesForMonth(_ date: Date) -> Set<Int> {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days = Set<Int>()
        for conversation in conversations {
            let created = conversation.createdAt
            if created >= monthInterval.start && created < monthInterval.end {
                days.insert(calendar.component(.day, from: created))
            }
            if let lastMsg = conversation.messages.last?.timestamp,
               lastMsg >= monthInterval.start && lastMsg < monthInterval.end {
                days.insert(calendar.component(.day, from: lastMsg))
            }
        }
        return days
    }

    /// Returns a mapping of day-of-month to the set of color labels for conversations on that day.
    func conversationColorsForMonth(_ date: Date) -> [Int: Set<String>] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [:] }
        var result: [Int: Set<String>] = [:]
        for conversation in conversations {
            guard let colorLabel = conversation.colorLabel else { continue }
            let created = conversation.createdAt
            if created >= monthInterval.start && created < monthInterval.end {
                let day = calendar.component(.day, from: created)
                result[day, default: []].insert(colorLabel)
            }
            if let lastMsg = conversation.messages.last?.timestamp,
               lastMsg >= monthInterval.start && lastMsg < monthInterval.end {
                let day = calendar.component(.day, from: lastMsg)
                result[day, default: []].insert(colorLabel)
            }
        }
        return result
    }

    /// Clears the calendar date filter.
    func clearCalendarFilter() {
        calendarFilterDate = nil
    }

    // MARK: - Multi-Select Mode
    @Published var isMultiSelectMode: Bool = false
    @Published var selectedConversationIds: Set<String> = []

    /// Number of active (enabled) tasks.
    var activeTaskCount: Int {
        tasks.filter { $0.enabled }.count
    }

    /// Number of available agents.
    var availableAgentCount: Int {
        agents.count
    }

    /// Marks a conversation as read, removing it from the unread set.
    func markConversationRead(id: String) {
        unreadConversationIds.remove(id)
    }

    /// Marks a conversation as unread (e.g. when a new message arrives while viewing a different conversation).
    func markConversationUnread(id: String) {
        unreadConversationIds.insert(id)
    }

    /// Last 5 non-archived conversations, sorted by most recent activity, for dashboard display.
    var recentConversationsForDashboard: [Conversation] {
        conversations
            .filter { !$0.isArchived }
            .sorted { $0.lastUpdated > $1.lastUpdated }
            .prefix(5)
            .map { $0 }
    }
    @Published var gatewayRunning: Bool = false
    @Published var gatewayPID: Int?
    @Published var config: AppConfig = AppConfig()
    @Published var isLoading: Bool = false
    @Published var tokensToday: Int = 0
    @Published var costToday: Double = 0.0
    @Published var costMonth: Double = 0.0
    @Published var dailyTokenUsage: [DailyTokenUsage] = []
    @Published var errorMessage: String?
    @Published var toastMessage: Toast?
    @Published var isProcessing: Bool = false
    @Published var shouldFocusInput: Bool = false
    @Published var focusModeEnabled: Bool = false
    /// Set by GeometryReader when window is too narrow for sidebar
    @Published var sidebarHidden: Bool = false
    /// Show sidebar as overlay on very narrow windows
    @Published var showSidebarOverlay: Bool = false
    @Published var contextPressurePercent: Int = 0
    @Published var suggestedReplies: [String] = []
    @Published var streamingStartTime: Date?
    /// Timestamp when the user pressed send, used to compute response time to first token
    private var messageSendTime: Date?
    @AppStorage("conversationSortOption") var conversationSortOption: String = "lastUpdated"
    @AppStorage("conversationSortAscending") var conversationSortAscending: Bool = false

    /// Custom conversation ordering persisted as an array of conversation IDs
    @Published var customConversationOrder: [String] = {
        UserDefaults.standard.stringArray(forKey: "customConversationOrder") ?? []
    }() {
        didSet {
            UserDefaults.standard.set(customConversationOrder, forKey: "customConversationOrder")
        }
    }

    /// Computed accessor for the typed sort option enum
    var conversationSortOrder: ConversationSortOption {
        get { ConversationSortOption(rawValue: conversationSortOption) ?? .lastUpdated }
        set { conversationSortOption = newValue.rawValue }
    }

    /// Move a conversation in the custom order array from one index to another
    func moveConversation(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < customConversationOrder.count,
              toIndex >= 0, toIndex <= customConversationOrder.count else { return }
        let id = customConversationOrder.remove(at: fromIndex)
        let insertAt = toIndex > fromIndex ? toIndex - 1 : toIndex
        customConversationOrder.insert(id, at: min(insertAt, customConversationOrder.count))
    }

    /// Ensure all current conversation IDs are present in the custom order (appending new ones)
    func syncCustomOrder() {
        let existingIds = Set(customConversationOrder)
        let allIds = conversations.map { $0.id }
        // Remove IDs that no longer exist
        customConversationOrder = customConversationOrder.filter { id in
            conversations.contains { $0.id == id }
        }
        // Append any new conversations not yet in the custom order
        for id in allIds where !existingIds.contains(id) {
            customConversationOrder.append(id)
        }
    }
    @Published var showArchived: Bool = false
    @Published var showRawMarkdown: Bool = false
    @Published var filterTag: String?
    @Published var selectedFilterTags: Set<String> = []
    @Published var tagColors: [String: String] = {
        (UserDefaults.standard.dictionary(forKey: "tagColors") as? [String: String]) ?? [:]
    }() {
        didSet {
            UserDefaults.standard.set(tagColors, forKey: "tagColors")
        }
    }
    @Published var notifications: [AppNotification] = []
    @Published var showNotificationPanel: Bool = false
    @Published var selectedModel: String = "anthropic/claude-sonnet-4-20250514"
    @Published var showConversationInfo: Bool = false

    // MARK: - System Status

    @Published var systemStats: SystemStats?

    func fetchSystemStats() -> SystemStats {
        var stats = SystemStats()

        // Memory info from ProcessInfo
        let processInfo = ProcessInfo.processInfo
        stats.memoryTotal = processInfo.physicalMemory
        stats.uptime = processInfo.systemUptime

        // CPU usage via top command
        if let cpuOutput = runShellCommand("top -l 1 -n 0 | grep 'CPU usage'") {
            // Parse: "CPU usage: 5.26% user, 10.52% sys, 84.21% idle"
            let parts = cpuOutput.components(separatedBy: ",")
            if let idlePart = parts.last,
               let idleStr = idlePart.trimmingCharacters(in: .whitespaces)
                   .components(separatedBy: "%").first?.trimmingCharacters(in: .whitespaces),
               let idle = Double(idleStr) {
                stats.cpuUsage = max(0, min(100, 100.0 - idle))
            }
        }

        // Memory pressure via vm_stat
        if let vmOutput = runShellCommand("vm_stat") {
            let pageSize: UInt64 = 16384
            var free: UInt64 = 0
            var active: UInt64 = 0
            var inactive: UInt64 = 0
            var speculative: UInt64 = 0
            var wired: UInt64 = 0
            var compressed: UInt64 = 0

            for line in vmOutput.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("Pages free:") {
                    free = parseVMStatValue(trimmed) * pageSize
                } else if trimmed.hasPrefix("Pages active:") {
                    active = parseVMStatValue(trimmed) * pageSize
                } else if trimmed.hasPrefix("Pages inactive:") {
                    inactive = parseVMStatValue(trimmed) * pageSize
                } else if trimmed.hasPrefix("Pages speculative:") {
                    speculative = parseVMStatValue(trimmed) * pageSize
                } else if trimmed.hasPrefix("Pages wired down:") {
                    wired = parseVMStatValue(trimmed) * pageSize
                } else if trimmed.hasPrefix("Pages occupied by compressor:") {
                    compressed = parseVMStatValue(trimmed) * pageSize
                }
            }

            let used = active + wired + compressed
            let totalAccountedFor = free + active + inactive + speculative + wired + compressed
            if totalAccountedFor > 0 {
                stats.memoryUsed = used
            }
        }

        // Disk space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            if let totalSize = attrs[.systemSize] as? UInt64,
               let freeSize = attrs[.systemFreeSize] as? UInt64 {
                stats.diskTotal = totalSize
                stats.diskUsed = totalSize - freeSize
            }
        }

        // Process count
        if let psOutput = runShellCommand("ps -e | wc -l") {
            let trimmed = psOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            stats.processCount = max(0, (Int(trimmed) ?? 1) - 1) // subtract header line
        }

        return stats
    }

    private func runShellCommand(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseVMStatValue(_ line: String) -> UInt64 {
        // Lines look like: "Pages free:    123456."
        let parts = line.components(separatedBy: ":")
        guard parts.count == 2 else { return 0 }
        let numStr = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "")
        return UInt64(numStr) ?? 0
    }

    // MARK: - Agent Usage Tracking

    @Published var agentUsageCounts: [String: Int] = {
        (UserDefaults.standard.dictionary(forKey: "agentUsageCounts") as? [String: Int]) ?? [:]
    }() {
        didSet {
            UserDefaults.standard.set(agentUsageCounts, forKey: "agentUsageCounts")
        }
    }

    @Published var agentLastUsed: [String: Date] = {
        guard let data = UserDefaults.standard.data(forKey: "agentLastUsed"),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        return decoded
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(agentLastUsed) {
                UserDefaults.standard.set(data, forKey: "agentLastUsed")
            }
        }
    }

    func recordAgentUsage(agentName: String) {
        agentUsageCounts[agentName, default: 0] += 1
        agentLastUsed[agentName] = Date()
    }

    func agentStatus(for agentName: String) -> AgentStatus {
        // Check if used within last 24 hours
        if let lastUsed = agentLastUsed[agentName],
           Date().timeIntervalSince(lastUsed) < 86400 {
            return .recentlyUsed
        }

        // Check if the agent's model provider has an API key
        if let agent = agents.first(where: { $0.name == agentName }) {
            if agent.backend == "claude-code" {
                return .available
            }
            let providerKey = agent.model.split(separator: "/").first.map(String.init) ?? ""
            if hasAPIKey(for: providerKey) {
                return .available
            }
            return .noKey
        }

        return .noKey
    }

    func agentLastUsedLabel(for agentName: String) -> String? {
        guard let lastUsed = agentLastUsed[agentName] else { return nil }
        let elapsed = Date().timeIntervalSince(lastUsed)
        if elapsed < 60 { return "Last used: just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "Last used: \(minutes)m ago" }
        let hours = Int(elapsed / 3600)
        if hours < 24 { return "Last used: \(hours)h ago" }
        let days = Int(elapsed / 86400)
        return "Last used: \(days)d ago"
    }

    // MARK: - Conversation Templates

    @Published var conversationTemplates: [ConversationTemplate] = [
        ConversationTemplate(
            name: "Code Review",
            icon: "magnifyingglass.circle",
            description: "Get feedback on your code",
            initialMessage: "Please review the following code for bugs, readability, and best practices. Suggest improvements:\n\n",
            isBuiltIn: true,
            category: "Development"
        ),
        ConversationTemplate(
            name: "Debug Issue",
            icon: "ladybug",
            description: "Track down and fix bugs",
            initialMessage: "I'm running into a bug and need help debugging. Here's what's happening:\n\n",
            isBuiltIn: true,
            category: "Development"
        ),
        ConversationTemplate(
            name: "Explain Code",
            icon: "doc.text.magnifyingglass",
            description: "Understand how code works",
            initialMessage: "Please explain the following code in detail, including what each part does and why:\n\n",
            isBuiltIn: true,
            category: "Development"
        ),
        ConversationTemplate(
            name: "Write Tests",
            icon: "checkmark.shield",
            description: "Generate test cases",
            initialMessage: "Write comprehensive unit tests for the following code. Cover edge cases and happy paths:\n\n",
            isBuiltIn: true,
            category: "Development"
        ),
        ConversationTemplate(
            name: "Brainstorm",
            icon: "brain.head.profile",
            description: "Explore ideas and solutions",
            initialMessage: "Let's brainstorm ideas. I'm working on the following and would love creative input:\n\n",
            isBuiltIn: true,
            category: "General"
        ),
        ConversationTemplate(
            name: "Research",
            icon: "books.vertical",
            description: "Deep dive into a topic",
            initialMessage: "I'd like to research and understand the following topic in depth:\n\n",
            isBuiltIn: true,
            category: "Research"
        ),
    ]

    @Published var userTemplates: [ConversationTemplate] = [] {
        didSet { persistUserTemplates() }
    }

    /// All templates combined: built-in + user-created
    var allTemplates: [ConversationTemplate] {
        conversationTemplates + userTemplates
    }

    /// Templates filtered by category
    func templates(for category: TemplateCategory, searchQuery: String = "") -> [ConversationTemplate] {
        var results = allTemplates
        if category != .all {
            results = results.filter { $0.category == category.rawValue }
        }
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            results = results.filter {
                $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }
        }
        return results
    }

    func saveUserTemplate(_ template: ConversationTemplate) {
        var t = template
        t.isBuiltIn = false
        if let index = userTemplates.firstIndex(where: { $0.id == t.id }) {
            userTemplates[index] = t
        } else {
            userTemplates.append(t)
        }
    }

    func deleteUserTemplate(id: UUID) {
        userTemplates.removeAll { $0.id == id }
    }

    func editUserTemplate(id: UUID, name: String, icon: String, description: String, initialMessage: String, category: String) {
        if let index = userTemplates.firstIndex(where: { $0.id == id }) {
            userTemplates[index].name = name
            userTemplates[index].icon = icon
            userTemplates[index].description = description
            userTemplates[index].initialMessage = initialMessage
            userTemplates[index].category = category
        }
    }

    func duplicateTemplate(_ template: ConversationTemplate) {
        var copy = template
        copy.id = UUID()
        copy.name = "\(template.name) Copy"
        copy.isBuiltIn = false
        userTemplates.append(copy)
    }

    private func persistUserTemplates() {
        if let data = try? JSONEncoder().encode(userTemplates) {
            UserDefaults.standard.set(data, forKey: "osai_user_templates")
        }
    }

    func loadUserTemplates() {
        if let data = UserDefaults.standard.data(forKey: "osai_user_templates"),
           let templates = try? JSONDecoder().decode([ConversationTemplate].self, from: data) {
            userTemplates = templates
        }
    }

    func startFromTemplate(_ template: ConversationTemplate) {
        let conv = Conversation(
            id: UUID().uuidString,
            title: template.name,
            messages: [],
            createdAt: Date(),
            agentName: nil,
            modelId: selectedModel
        )
        activeConversation = conv
        conversations.insert(conv, at: 0)
        selectedTab = .chat
        sendMessage(template.initialMessage)
    }

    // MARK: - Conversation Statistics

    struct ConversationStats {
        let totalMessages: Int
        let userMessages: Int
        let assistantMessages: Int
        let totalTokens: Int
        let inputTokens: Int
        let outputTokens: Int
        let averageResponseTimeMs: Int?
        let topTools: [(name: String, count: Int)]
        let conversationDuration: TimeInterval?
        let wordsPerMessage: Double
        let codeBlocksCount: Int

        var formattedDuration: String {
            guard let duration = conversationDuration else { return "N/A" }
            if duration < 60 { return "< 1 min" }
            if duration < 3600 {
                let mins = Int(duration / 60)
                return "\(mins) min"
            }
            let hours = Int(duration / 3600)
            let mins = Int(duration.truncatingRemainder(dividingBy: 3600) / 60)
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }

        var formattedAvgResponseTime: String {
            guard let ms = averageResponseTimeMs else { return "N/A" }
            if ms < 1000 { return "\(ms) ms" }
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }

    func computeStats(for conversation: Conversation) -> ConversationStats {
        let messages = conversation.messages
        let userMsgs = messages.filter { $0.role == .user }
        let assistantMsgs = messages.filter { $0.role == .assistant }

        // Average response time from assistant messages that have it
        let responseTimes = assistantMsgs.compactMap { $0.responseTimeMs }
        let avgResponseTime: Int? = responseTimes.isEmpty ? nil : responseTimes.reduce(0, +) / responseTimes.count

        // Tool usage counts
        var toolCounts: [String: Int] = [:]
        for msg in messages {
            for activity in msg.activities where activity.type == .toolCall {
                toolCounts[activity.label, default: 0] += 1
            }
            if let tool = msg.toolName {
                toolCounts[tool, default: 0] += 1
            }
        }
        let topTools = toolCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, count: $0.value) }

        // Duration
        var duration: TimeInterval? = nil
        if let first = messages.first?.timestamp, let last = messages.last?.timestamp, messages.count > 1 {
            duration = last.timeIntervalSince(first)
        }

        // Words per message
        let totalWords = messages.reduce(0) { total, msg in
            total + msg.content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        }
        let wordsPerMsg = messages.isEmpty ? 0.0 : Double(totalWords) / Double(messages.count)

        // Code blocks count (``` delimiters)
        let codeBlocks = messages.reduce(0) { total, msg in
            let matches = msg.content.components(separatedBy: "```")
            // Number of code blocks = (number of ``` pairs) / 2
            return total + max(0, (matches.count - 1) / 2)
        }

        return ConversationStats(
            totalMessages: messages.count,
            userMessages: userMsgs.count,
            assistantMessages: assistantMsgs.count,
            totalTokens: conversation.totalInputTokens + conversation.totalOutputTokens,
            inputTokens: conversation.totalInputTokens,
            outputTokens: conversation.totalOutputTokens,
            averageResponseTimeMs: avgResponseTime,
            topTools: topTools,
            conversationDuration: duration,
            wordsPerMessage: wordsPerMsg,
            codeBlocksCount: codeBlocks
        )
    }

    // MARK: - Conversation Summary

    func generateSummary(for conversation: Conversation) -> String {
        let messages = conversation.messages
        let userCount = messages.filter { $0.role == .user }.count
        let assistantCount = messages.filter { $0.role == .assistant }.count
        let totalCount = messages.count

        // Duration
        var durationStr = ""
        if let first = messages.first?.timestamp, let last = messages.last?.timestamp {
            let elapsed = last.timeIntervalSince(first)
            if elapsed < 60 {
                durationStr = "under a minute"
            } else if elapsed < 3600 {
                durationStr = "\(Int(elapsed / 60)) minutes"
            } else {
                let hours = Int(elapsed / 3600)
                let mins = Int(elapsed.truncatingRemainder(dividingBy: 3600) / 60)
                durationStr = mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
            }
        }

        // Tools used
        var toolNames: [String] = []
        for msg in messages {
            for activity in msg.activities where activity.type == .toolCall {
                let name = activity.label
                if !toolNames.contains(name) { toolNames.append(name) }
            }
            if let tool = msg.toolName, !toolNames.contains(tool) {
                toolNames.append(tool)
            }
        }

        // Key topics from first few user messages
        let firstUserMessages = messages.filter { $0.role == .user }.prefix(3)
        let topics = firstUserMessages.compactMap { msg -> String? in
            let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            return words.prefix(6).joined(separator: " ") + (words.count > 6 ? "..." : "")
        }

        // Build summary
        var parts: [String] = []

        var msgLine = "\(totalCount) messages (\(userCount) user, \(assistantCount) assistant)"
        if !durationStr.isEmpty {
            msgLine += " over \(durationStr)"
        }
        parts.append(msgLine)

        if !topics.isEmpty {
            parts.append("Topics: " + topics.joined(separator: "; "))
        }

        if !toolNames.isEmpty {
            parts.append("Tools used: " + toolNames.joined(separator: ", "))
        }

        if conversation.totalInputTokens > 0 || conversation.totalOutputTokens > 0 {
            let input = conversation.totalInputTokens
            let output = conversation.totalOutputTokens
            parts.append("Tokens: \(input + output) (\(input) in, \(output) out)")
        }

        return parts.joined(separator: ". ")
    }

    // MARK: - Text-to-Speech

    private let speechSynthesizer = NSSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?
    @Published var isSpeaking: Bool = false
    @Published var speakingMessageId: String?

    /// All known models grouped by provider, indicating availability based on configured API keys.
    var availableModels: [ModelDefinition] {
        allModelDefinitions
    }

    /// Models grouped by provider name for display in the selector.
    var modelsGroupedByProvider: [(provider: String, models: [ModelDefinition])] {
        let grouped = Dictionary(grouping: allModelDefinitions) { $0.provider }
        let order = ["Anthropic", "OpenAI", "Google", "Local"]
        return order.compactMap { provider in
            guard let models = grouped[provider] else { return nil }
            return (provider: provider, models: models)
        }
    }

    /// Whether a provider has an API key configured.
    func hasAPIKey(for providerKey: String) -> Bool {
        if providerKey == "claude-code" { return true }
        return config.apiKeys[providerKey] != nil
    }

    /// Look up a ModelDefinition by its id string.
    func modelDefinition(for id: String) -> ModelDefinition? {
        allModelDefinitions.first { $0.id == id }
    }

    /// Short display name for the currently selected model.
    var selectedModelShortName: String {
        modelDefinition(for: selectedModel)?.shortName ?? selectedModel
    }

    var unreadNotificationCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    // MARK: - Response Time Metrics

    /// All response times across all conversations (ms)
    private var allResponseTimes: [Int] {
        conversations.flatMap { conv in
            conv.messages.compactMap { $0.responseTimeMs }
        }
    }

    /// Average response time across all conversations in milliseconds
    var averageResponseTime: Double {
        let times = allResponseTimes
        guard !times.isEmpty else { return 0 }
        return Double(times.reduce(0, +)) / Double(times.count)
    }

    /// Fastest response time in milliseconds
    var fastestResponseTime: Int? {
        allResponseTimes.min()
    }

    /// Slowest response time in milliseconds
    var slowestResponseTime: Int? {
        allResponseTimes.max()
    }

    /// Average response times grouped by day for the last 7 days, for charting
    var responseTimesLastWeek: [(date: Date, avgMs: Int)] {
        let calendar = Calendar.current
        let now = Date()
        var result: [(date: Date, avgMs: Int)] = []

        for daysAgo in (0..<7).reversed() {
            guard let dayStart = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) else { continue }
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let times: [Int] = conversations.flatMap { conv in
                conv.messages.compactMap { msg -> Int? in
                    guard let rt = msg.responseTimeMs,
                          msg.timestamp >= dayStart && msg.timestamp < dayEnd else { return nil }
                    return rt
                }
            }

            let avg = times.isEmpty ? 0 : times.reduce(0, +) / times.count
            result.append((date: dayStart, avgMs: avg))
        }
        return result
    }

    /// Messages per hour over the last 24 hours
    var messagesPerHour: Double {
        let cutoff = Date().addingTimeInterval(-3600 * 24)
        let count = conversations.reduce(0) { total, conv in
            total + conv.messages.filter { $0.timestamp >= cutoff }.count
        }
        return Double(count) / 24.0
    }

    /// Number of conversations created today
    var conversationsToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return conversations.filter { $0.createdAt >= start }.count
    }

    /// Number of conversations created this week
    var conversationsThisWeek: Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return 0 }
        return conversations.filter { $0.createdAt >= weekStart }.count
    }

    /// Returns non-archived conversations sorted by the selected sort order, with pinned items always first.
    var sortedConversations: [Conversation] {
        let active = conversations.filter { !$0.isArchived }
        let pinned = active.filter { $0.isPinned }
        let unpinned = active.filter { !$0.isPinned }
        let sortedPinned = sortConversations(pinned)
        let sortedUnpinned = sortConversations(unpinned)
        return sortedPinned + sortedUnpinned
    }

    /// Returns archived conversations sorted by the selected sort order.
    var archivedConversations: [Conversation] {
        sortConversations(conversations.filter { $0.isArchived })
    }

    private func sortConversations(_ convs: [Conversation]) -> [Conversation] {
        let ascending = conversationSortAscending
        switch conversationSortOrder {
        case .lastUpdated:
            return convs.sorted { ascending ? $0.lastUpdated < $1.lastUpdated : $0.lastUpdated > $1.lastUpdated }
        case .created:
            return convs.sorted { ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        case .messageCount:
            return convs.sorted { ascending ? $0.messages.count < $1.messages.count : $0.messages.count > $1.messages.count }
        case .tokenUsage:
            return convs.sorted { ascending ? $0.totalTokens < $1.totalTokens : $0.totalTokens > $1.totalTokens }
        case .alphabetical:
            return convs.sorted {
                let result = $0.title.localizedCaseInsensitiveCompare($1.title)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        case .custom:
            let orderMap = Dictionary(uniqueKeysWithValues: customConversationOrder.enumerated().map { ($1, $0) })
            return convs.sorted { a, b in
                let idxA = orderMap[a.id] ?? Int.max
                let idxB = orderMap[b.id] ?? Int.max
                return idxA < idxB
            }
        }
    }


    // MARK: - Conversation Grouping

    /// Groups conversations by time period, extracting pinned conversations into their own group.
    /// Returns an array of (group name, conversations) tuples with empty groups omitted.
    func groupedConversations(from conversations: [Conversation]) -> [(String, [Conversation])] {
        let pinned = conversations.filter { $0.isPinned }
        let unpinned = conversations.filter { !$0.isPinned }

        // In custom sort mode, show pinned and all others as flat groups
        if conversationSortOrder == .custom {
            var result: [(String, [Conversation])] = []
            if !pinned.isEmpty { result.append(("Pinned", pinned)) }
            if !unpinned.isEmpty { result.append(("All Conversations", unpinned)) }
            return result
        }

        let cal = Calendar.current
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let monthAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var thisWeek: [Conversation] = []
        var thisMonth: [Conversation] = []
        var older: [Conversation] = []

        for conv in unpinned {
            let date = conv.lastUpdated
            if cal.isDateInToday(date) {
                today.append(conv)
            } else if cal.isDateInYesterday(date) {
                yesterday.append(conv)
            } else if date >= weekAgo {
                thisWeek.append(conv)
            } else if date >= monthAgo {
                thisMonth.append(conv)
            } else {
                older.append(conv)
            }
        }

        var result: [(String, [Conversation])] = []
        if !pinned.isEmpty { result.append(("Pinned", pinned)) }
        if !today.isEmpty { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        if !thisMonth.isEmpty { result.append(("This Month", thisMonth)) }
        if !older.isEmpty { result.append(("Older", older)) }
        return result
    }

    private(set) var runningProcess: Process?

    let service = OSAIService()
    private let configService = ConfigService()
    private var refreshTimer: Timer?
    private var toastDismissTask: Task<Void, Never>?

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[OSAI] Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func sendNotification(title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(100))
        if notifySoundEnabled && notificationSound != "none" {
            switch notificationSound {
            case "ping":
                content.sound = UNNotificationSound(named: UNNotificationSoundName("Ping"))
            case "pop":
                content.sound = UNNotificationSound(named: UNNotificationSoundName("Pop"))
            case "glass":
                content.sound = UNNotificationSound(named: UNNotificationSoundName("Glass"))
            default:
                content.sound = .default
            }
        } else {
            content.sound = nil
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func playNotificationSound() {
        guard notificationsEnabled && notifySoundEnabled else { return }
        let soundName: String
        switch notificationSound {
        case "ping": soundName = "Ping"
        case "pop": soundName = "Pop"
        case "glass": soundName = "Glass"
        case "none": return
        default: soundName = "Blow"
        }
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    func showToast(_ message: String, type: ToastType = .info) {
        toastDismissTask?.cancel()
        toastMessage = Toast(message: message, type: type)
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.toastMessage = nil
        }
    }

    func addNotification(title: String, message: String, type: NotificationType) {
        let notification = AppNotification(timestamp: Date(), title: title, message: message, type: type)
        notifications.insert(notification, at: 0)
        // Auto-trim to 50
        if notifications.count > 50 {
            notifications = Array(notifications.prefix(50))
        }
    }

    func markAllRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
    }

    func clearNotifications() {
        notifications.removeAll()
    }

    func changeAccentColor(_ presetId: String) {
        selectedAccentColor = presetId
        UserDefaults.standard.set(presetId, forKey: "selectedAccentColor")
        AppTheme.setAccentColor(presetId)
    }

    func loadAll() {
        // Apply saved accent color on launch
        AppTheme.setAccentColor(selectedAccentColor)

        requestNotificationPermission()
        isLoading = true
        agents = service.loadAgents()
        tasks = service.loadTasks()
        config = service.loadConfig()
        selectedModel = config.activeModel
        conversations = service.loadConversations()
        let status = service.gatewayStatus()
        gatewayRunning = status.running
        gatewayPID = status.pid
        loadSpending()
        loadUserTemplates()
        updateStreak()
        isLoading = false

        // Auto-refresh every 30s
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    func refreshStatus() {
        let wasRunning = gatewayRunning
        let status = service.gatewayStatus()
        gatewayRunning = status.running
        gatewayPID = status.pid
        loadSpending()
        tasks = service.loadTasks()

        // Notify if gateway stopped unexpectedly
        if wasRunning && !gatewayRunning {
            sendNotification(title: "OSAI", body: "Gateway stopped unexpectedly")
            showToast("Gateway stopped unexpectedly", type: .error)
            addNotification(title: "Gateway Stopped", message: "Gateway stopped unexpectedly", type: .error)
        }
    }

    func loadSpending() {
        let spendingPath = NSHomeDirectory() + "/.desktop-agent/spending.json"
        guard let data = FileManager.default.contents(atPath: spendingPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

        if let daily = json["daily"] as? [String: Any],
           let todayData = daily[String(today)] as? [String: Any] {
            costToday = todayData["cost_usd"] as? Double ?? 0.0
            tokensToday = todayData["tokens"] as? Int ?? 0
        }

        // Sum month cost
        if let daily = json["daily"] as? [String: Any] {
            let thisMonth = String(today.prefix(7))
            costMonth = daily.filter { $0.key.hasPrefix(thisMonth) }
                .compactMap { ($0.value as? [String: Any])?["cost_usd"] as? Double }
                .reduce(0, +)
        }

        loadDailyTokenUsage()
    }

    // MARK: - Daily Token Usage Persistence

    private static let dailyTokenUsageKey = "dailyTokenUsage"

    func loadDailyTokenUsage() {
        if let data = UserDefaults.standard.data(forKey: Self.dailyTokenUsageKey),
           let decoded = try? JSONDecoder().decode([DailyTokenUsage].self, from: data) {
            dailyTokenUsage = decoded
        }
    }

    private func saveDailyTokenUsage() {
        if let data = try? JSONEncoder().encode(dailyTokenUsage) {
            UserDefaults.standard.set(data, forKey: Self.dailyTokenUsageKey)
        }
    }

    func recordDailyTokenUsage(input: Int, output: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: Date())

        if let idx = dailyTokenUsage.firstIndex(where: { $0.dateKey == todayKey }) {
            dailyTokenUsage[idx].inputTokens += input
            dailyTokenUsage[idx].outputTokens += output
        } else {
            let entry = DailyTokenUsage(
                dateKey: todayKey,
                date: Calendar.current.startOfDay(for: Date()),
                inputTokens: input,
                outputTokens: output
            )
            dailyTokenUsage.append(entry)
        }

        // Prune entries older than 30 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        dailyTokenUsage.removeAll { $0.date < cutoff }

        saveDailyTokenUsage()
    }

    func getWeeklyTokenUsage() -> [DailyTokenUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var result: [DailyTokenUsage] = []
        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let key = formatter.string(from: date)
            if let existing = dailyTokenUsage.first(where: { $0.dateKey == key }) {
                result.append(existing)
            } else {
                result.append(DailyTokenUsage(dateKey: key, date: date, inputTokens: 0, outputTokens: 0))
            }
        }
        return result
    }

    func sendMessage(_ text: String, attachments: [URL] = []) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isProcessing else { return }
        suggestedReplies = []

        if activeConversation == nil {
            let conv = Conversation(
                id: UUID().uuidString,
                title: smartTitle(from: text),
                messages: [],
                createdAt: Date(),
                agentName: nil,
                modelId: selectedModel
            )
            activeConversation = conv
            conversations.insert(conv, at: 0)
            selectedTab = .chat
            totalConversationsCreated += 1
        }

        // Track message activity
        totalMessagesCount += 1
        recordDailyActivity()

        // Stamp current model on conversation if not already set
        if activeConversation?.modelId == nil {
            activeConversation?.modelId = selectedModel
        }

        // Build message with attachment context
        let textExtensions: Set<String> = ["swift", "py", "js", "ts", "md", "txt", "json", "yaml", "yml", "html", "css", "sh", "rb", "go", "rs", "c", "cpp", "h", "java", "kt", "toml", "xml", "csv", "log", "env", "cfg", "ini", "sql"]
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]

        var fullText = ""
        for url in attachments {
            let ext = url.pathExtension.lowercased()
            let name = url.lastPathComponent
            if textExtensions.contains(ext) {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    fullText += "File: \(name)\n```\n\(content)\n```\n\n"
                } else {
                    fullText += "[Attached: \(name)]\n\n"
                }
            } else if imageExtensions.contains(ext) {
                fullText += "[Image: \(name)]\n\n"
            } else {
                fullText += "[Attached: \(name)]\n\n"
            }
        }
        fullText += text

        let userMsg = ChatMessage(id: UUID().uuidString, role: .user, content: fullText, timestamp: Date())
        activeConversation?.messages.append(userMsg)
        syncConversationToList()

        let assistantMsg = ChatMessage(id: UUID().uuidString, role: .assistant, content: "", timestamp: Date(), isStreaming: true)
        activeConversation?.messages.append(assistantMsg)
        syncConversationToList()

        let streamingId = assistantMsg.id
        isProcessing = true
        streamingStartTime = Date()
        messageSendTime = Date()

        let streamState = StreamState()

        // Build CLI args — agent model takes priority, then selected model
        var args = [fullText]
        if let agentName = activeConversation?.agentName,
           let agent = agents.first(where: { $0.name == agentName }),
           !agent.model.isEmpty {
            args = ["--model", agent.model, fullText]
        } else if selectedModel != config.activeModel {
            // Use the chat-level selected model when it differs from config default
            args = ["--model", selectedModel, fullText]
        }

        Task {
            do {
                let process = try service.startAppModeStreaming(args: args) { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.handleAppEvent(event, streamingId: streamingId, state: streamState)
                    }
                }

                self.runningProcess = process
                await service.awaitProcess(process)
                self.runningProcess = nil

                try? await Task.sleep(for: .milliseconds(100))

                // Finalize
                if let idx = activeConversation?.messages.firstIndex(where: { $0.id == streamingId }) {
                    for i in 0..<(activeConversation?.messages[idx].activities.count ?? 0) {
                        activeConversation?.messages[idx].activities[i].isComplete = true
                    }
                    if activeConversation?.messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                        activeConversation?.messages[idx].content = streamState.accumulatedText.isEmpty ? "(no response)" : streamState.accumulatedText
                    }
                    activeConversation?.messages[idx].isStreaming = false
                }

                syncConversationToList()

                // Auto-generate smart title after first assistant response
                autoTitleIfNeeded()
                syncConversationToList()

                if let conv = activeConversation {
                    service.saveConversation(conv)
                }

                // Generate quick reply suggestions
                if let lastAssistant = self.activeConversation?.messages.last(where: { $0.role == .assistant }) {
                    self.generateSuggestedReplies(from: lastAssistant.content)
                }

                // Add in-app notification for completed response
                let agentLabel = activeConversation?.agentName ?? "Chat"
                addNotification(title: "Response Complete", message: "\(agentLabel) finished responding", type: .success)

                // Send notification if app is in the background
                if let app = NSApp, !app.isActive {
                    let title = activeConversation?.agentName ?? "OSAI"
                    let body = activeConversation?.messages.last(where: { $0.role == .assistant })?.content ?? ""
                    sendNotification(title: title, body: body)
                }
            } catch {
                self.runningProcess = nil
                if let idx = activeConversation?.messages.firstIndex(where: { $0.id == streamingId }) {
                    activeConversation?.messages[idx].content = "Error: \(error.localizedDescription)"
                    activeConversation?.messages[idx].isStreaming = false
                }
                syncConversationToList()
            }
            isProcessing = false
            streamingStartTime = nil
            messageSendTime = nil
        }
    }

    /// Keep conversations array in sync with activeConversation
    private func syncConversationToList() {
        guard let active = activeConversation else { return }
        if let idx = conversations.firstIndex(where: { $0.id == active.id }) {
            conversations[idx] = active
        }
    }

    /// Handle a structured NDJSON event from --app-mode — must be called on MainActor
    private func handleAppEvent(_ event: AppEventType, streamingId: String, state: StreamState) {
        guard let idx = activeConversation?.messages.firstIndex(where: { $0.id == streamingId }) else { return }

        switch event {
        case .text(let content):
            // Record response time on first text token
            if !state.firstTextReceived, let sendTime = messageSendTime {
                state.firstTextReceived = true
                let deltaMs = Int(Date().timeIntervalSince(sendTime) * 1000)
                activeConversation?.messages[idx].responseTimeMs = deltaMs
            }
            if state.accumulatedText.isEmpty {
                state.accumulatedText = content
            } else {
                state.accumulatedText += "\n" + content
            }
            activeConversation?.messages[idx].content = state.accumulatedText

        case .toolStart(let id, let name, let detail):
            let activity = ActivityItem(
                id: id,
                type: .toolCall,
                label: name,
                detail: detail ?? "",
                isComplete: false,
                startTime: Date()
            )
            state.activeActivityIds[id] = activity.id
            activeConversation?.messages[idx].activities.append(activity)

        case .toolResult(let id, _, let success, let output, let durationMs):
            if let actIdx = activeConversation?.messages[idx].activities.firstIndex(where: { $0.id == id }) {
                activeConversation?.messages[idx].activities[actIdx].isComplete = true
                activeConversation?.messages[idx].activities[actIdx].success = success
                activeConversation?.messages[idx].activities[actIdx].output = output
                activeConversation?.messages[idx].activities[actIdx].durationMs = durationMs
            }

        case .agentRoute(let agent, _):
            activeConversation?.messages[idx].agentName = agent
            if activeConversation?.agentName == nil {
                activeConversation?.agentName = agent
            }
            recordAgentUsage(agentName: agent)
            let activity = ActivityItem(
                id: UUID().uuidString,
                type: .agentRoute,
                label: agent,
                detail: "",
                isComplete: true,
                startTime: Date()
            )
            activeConversation?.messages[idx].activities.append(activity)
            addNotification(title: "Agent Routed", message: "Routed to \(agent)", type: .info)

        case .status(let message):
            let activity = ActivityItem(
                id: UUID().uuidString,
                type: .status,
                label: message,
                detail: "",
                isComplete: true,
                startTime: Date()
            )
            activeConversation?.messages[idx].activities.append(activity)

        case .tokens(let input, let output):
            activeConversation?.totalInputTokens += input
            activeConversation?.totalOutputTokens += output
            tokensToday += input + output
            recordDailyTokenUsage(input: input, output: output)
            checkBudgetAlert()

        case .contextPressure(let percent):
            contextPressurePercent = percent

        case .error(let message):
            if state.accumulatedText.isEmpty {
                state.accumulatedText = "Error: \(message)"
            } else {
                state.accumulatedText += "\nError: \(message)"
            }
            activeConversation?.messages[idx].content = state.accumulatedText
            showToast(message, type: .error)
            addNotification(title: "Error", message: message, type: .error)

        case .done:
            activeConversation?.messages[idx].isStreaming = false
            for i in 0..<(activeConversation?.messages[idx].activities.count ?? 0) {
                activeConversation?.messages[idx].activities[i].isComplete = true
            }
        }

        // Keep list in sync during streaming
        syncConversationToList()
    }

    func cancelProcessing() {
        if let process = runningProcess, process.isRunning {
            process.terminate()
        }
        runningProcess = nil
        isProcessing = false
        streamingStartTime = nil
        messageSendTime = nil

        // Mark current streaming message as done
        if let conv = activeConversation {
            if let idx = conv.messages.lastIndex(where: { $0.isStreaming }) {
                activeConversation?.messages[idx].isStreaming = false
                for i in 0..<(activeConversation?.messages[idx].activities.count ?? 0) {
                    activeConversation?.messages[idx].activities[i].isComplete = true
                }
                if activeConversation?.messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    activeConversation?.messages[idx].content = "(cancelled)"
                }
            }
        }
    }

    func retryLastMessage() {
        guard !isProcessing else { return }
        guard activeConversation != nil else { return }

        // Find the last assistant message and remove it
        if let lastAssistantIdx = activeConversation?.messages.lastIndex(where: { $0.role == .assistant }) {
            activeConversation?.messages.remove(at: lastAssistantIdx)
            syncConversationToList()
        }

        // Find the last user message content and re-send
        if let lastUserMsg = activeConversation?.messages.last(where: { $0.role == .user }) {
            let content = lastUserMsg.content
            // Remove the last user message too (sendMessage will re-add it)
            if let lastUserIdx = activeConversation?.messages.lastIndex(where: { $0.role == .user }) {
                activeConversation?.messages.remove(at: lastUserIdx)
                syncConversationToList()
            }
            sendMessage(content)
        }
    }

    func editAndResendMessage(messageId: String, newContent: String) {
        guard !isProcessing else { return }
        guard activeConversation != nil else { return }
        guard let msgIndex = activeConversation?.messages.firstIndex(where: { $0.id == messageId }) else { return }

        // Remove all messages after this one (the old response and any subsequent messages)
        activeConversation?.messages.removeSubrange((msgIndex + 1)...)
        // Remove the original user message too (sendMessage will re-add it)
        activeConversation?.messages.remove(at: msgIndex)
        syncConversationToList()

        sendMessage(newContent)
    }

    func startNewChat() {
        activeConversation = nil
        selectedTab = .chat
    }

    func closeCurrentConversation() {
        activeConversation = nil
        suggestedReplies = []
    }

    func copyLastAssistantMessage() {
        guard let conv = activeConversation,
              let lastAssistant = conv.messages.last(where: { $0.role == .assistant }) else { return }
        let content = lastAssistant.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        showToast("Copied to clipboard", type: .success)
    }

    @discardableResult
    func branchConversation(from conversationId: String, atMessageIndex: Int) -> Conversation? {
        guard let source = conversations.first(where: { $0.id == conversationId }) else { return nil }
        let branchedMessages = Array(source.messages.prefix(atMessageIndex + 1))
        let newConv = Conversation(
            id: UUID().uuidString,
            title: source.title + " (branch)",
            messages: branchedMessages,
            createdAt: Date(),
            agentName: source.agentName,
            modelId: source.modelId,
            branchedFromId: conversationId,
            branchedAtMessageIndex: atMessageIndex
        )
        conversations.insert(newConv, at: 0)
        service.saveConversation(newConv)
        activeConversation = newConv
        selectedTab = .chat
        showToast("Branched conversation", type: .success)
        return newConv
    }

    /// Look up a conversation's parent title for branch display
    func parentConversationTitle(for conv: Conversation) -> String? {
        guard let parentId = conv.branchedFromId else { return nil }
        return conversations.first(where: { $0.id == parentId })?.title
    }

    func navigateConversation(direction: Int) {
        guard !conversations.isEmpty else { return }
        selectedTab = .chat

        guard let active = activeConversation,
              let currentIdx = conversations.firstIndex(where: { $0.id == active.id }) else {
            // No active conversation: open first or last depending on direction
            if direction > 0 {
                openConversation(conversations[0])
            } else {
                openConversation(conversations[conversations.count - 1])
            }
            return
        }

        let newIdx = currentIdx + direction
        if newIdx >= 0, newIdx < conversations.count {
            openConversation(conversations[newIdx])
        }
    }

    // MARK: - Conversation List Navigation

    /// Selects the next conversation below the current one in the sorted list.
    func selectNextConversation() {
        let sorted = sortedConversations
        guard !sorted.isEmpty else { return }
        selectedTab = .chat

        guard let active = activeConversation,
              let currentIdx = sorted.firstIndex(where: { $0.id == active.id }) else {
            openConversation(sorted[0])
            return
        }

        let nextIdx = currentIdx + 1
        if nextIdx < sorted.count {
            openConversation(sorted[nextIdx])
        }
    }

    /// Selects the previous conversation above the current one in the sorted list.
    func selectPreviousConversation() {
        let sorted = sortedConversations
        guard !sorted.isEmpty else { return }
        selectedTab = .chat

        guard let active = activeConversation,
              let currentIdx = sorted.firstIndex(where: { $0.id == active.id }) else {
            openConversation(sorted[sorted.count - 1])
            return
        }

        let prevIdx = currentIdx - 1
        if prevIdx >= 0 {
            openConversation(sorted[prevIdx])
        }
    }

    /// Selects the conversation at the given 0-based index in the sorted list.
    func selectConversationByIndex(_ index: Int) {
        let sorted = sortedConversations
        guard index >= 0, index < sorted.count else { return }
        selectedTab = .chat
        openConversation(sorted[index])
    }

    /// Returns the content of the last user message in the active conversation, if any.
    func lastUserMessageContent() -> String? {
        activeConversation?.messages.last(where: { $0.role == .user })?.content
    }

    func openConversation(_ conv: Conversation) {
        // If we're already viewing this conversation (e.g. during streaming), don't overwrite with stale copy
        if activeConversation?.id == conv.id {
            selectedTab = .chat
            return
        }
        activeConversation = conv
        selectedTab = .chat
    }

    func deleteConversation(_ conv: Conversation) {
        conversations.removeAll { $0.id == conv.id }
        if activeConversation?.id == conv.id {
            activeConversation = nil
        }
        service.deleteConversation(conv.id)
        showToast("Conversation deleted", type: .success)
    }

    func clearAllConversations() {
        let ids = conversations.map { $0.id }
        conversations.removeAll()
        activeConversation = nil
        for id in ids {
            service.deleteConversation(id)
        }
        showToast("All conversations deleted", type: .success)
    }

    func deleteMultipleConversations(_ convs: [Conversation]) {
        let ids = Set(convs.map { $0.id })
        conversations.removeAll { ids.contains($0.id) }
        if let activeId = activeConversation?.id, ids.contains(activeId) {
            activeConversation = nil
        }
        for id in ids {
            service.deleteConversation(id)
        }
        showToast("\(ids.count) conversation\(ids.count == 1 ? "" : "s") deleted", type: .success)
    }

    // MARK: - Multi-Select Actions

    /// Delete all currently selected conversations and exit multi-select mode.
    func deleteSelectedConversations() {
        let toDelete = conversations.filter { selectedConversationIds.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        deleteMultipleConversations(toDelete)
        selectedConversationIds.removeAll()
        isMultiSelectMode = false
    }

    /// Archive all currently selected conversations and exit multi-select mode.
    func archiveSelectedConversations() {
        var count = 0
        for id in selectedConversationIds {
            if let idx = conversations.firstIndex(where: { $0.id == id }), !conversations[idx].isArchived {
                conversations[idx].isArchived = true
                service.saveConversation(conversations[idx])
                count += 1
            }
            if activeConversation?.id == id {
                activeConversation = nil
            }
        }
        selectedConversationIds.removeAll()
        isMultiSelectMode = false
        if count > 0 {
            showToast("\(count) conversation\(count == 1 ? "" : "s") archived", type: .info)
        }
    }

    /// Tag all currently selected conversations with the given tag.
    func tagSelectedConversations(tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var count = 0
        for id in selectedConversationIds {
            if let idx = conversations.firstIndex(where: { $0.id == id }) {
                if !conversations[idx].tags.contains(trimmed) {
                    conversations[idx].tags.append(trimmed)
                    service.saveConversation(conversations[idx])
                    count += 1
                }
            }
            if activeConversation?.id == id {
                if !(activeConversation?.tags.contains(trimmed) ?? false) {
                    activeConversation?.tags.append(trimmed)
                }
            }
        }
        if count > 0 {
            showToast("Tagged \(count) conversation\(count == 1 ? "" : "s") with \"\(trimmed)\"", type: .success)
        }
    }

    /// Merge source conversation into target: appends all messages, combines activities,
    /// updates token counts, merges tags, then deletes the source conversation.
    func mergeConversations(sourceId: String, targetId: String) {
        guard let sourceIdx = conversations.firstIndex(where: { $0.id == sourceId }),
              let targetIdx = conversations.firstIndex(where: { $0.id == targetId }) else {
            showToast("Could not find conversations to merge", type: .error)
            mergeTargetId = nil
            return
        }

        let source = conversations[sourceIdx]

        // Append all messages from source to target, sorted by timestamp
        conversations[targetIdx].messages.append(contentsOf: source.messages)
        conversations[targetIdx].messages.sort { $0.timestamp < $1.timestamp }

        // Update token counts
        conversations[targetIdx].totalInputTokens += source.totalInputTokens
        conversations[targetIdx].totalOutputTokens += source.totalOutputTokens

        // Merge tags (union, no duplicates)
        let existingTags = Set(conversations[targetIdx].tags)
        for tag in source.tags where !existingTags.contains(tag) {
            conversations[targetIdx].tags.append(tag)
        }

        // Save the updated target
        service.saveConversation(conversations[targetIdx])

        // Navigate to the merged conversation
        let merged = conversations[targetIdx]
        activeConversation = merged
        selectedTab = .chat

        // Delete the source conversation
        conversations.removeAll { $0.id == sourceId }
        if activeConversation?.id == sourceId {
            activeConversation = merged
        }
        service.deleteConversation(sourceId)

        // Clear merge mode
        mergeTargetId = nil

        showToast("Conversations merged successfully", type: .success)
    }

    func togglePin(_ conv: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx].isPinned.toggle()
        }
        if activeConversation?.id == conv.id {
            activeConversation?.isPinned.toggle()
        }
        if let updated = conversations.first(where: { $0.id == conv.id }) {
            service.saveConversation(updated)
        }
    }

    func setConversationColor(id: String, color: String?) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].colorLabel = color
            service.saveConversation(conversations[idx])
        }
        if activeConversation?.id == id {
            activeConversation?.colorLabel = color
        }
    }

    func archiveConversation(id: String) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].isArchived = true
            service.saveConversation(conversations[idx])
        }
        if activeConversation?.id == id {
            activeConversation = nil
        }
        showToast("Conversation archived", type: .info)
    }

    func unarchiveConversation(id: String) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].isArchived = false
            service.saveConversation(conversations[idx])
        }
        showToast("Conversation unarchived", type: .info)
    }

    func autoArchiveOldConversations(olderThan days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var count = 0
        for idx in conversations.indices {
            if !conversations[idx].isArchived && !conversations[idx].isPinned && conversations[idx].lastUpdated < cutoff {
                conversations[idx].isArchived = true
                service.saveConversation(conversations[idx])
                count += 1
            }
        }
        if activeConversation != nil, let id = activeConversation?.id,
           conversations.first(where: { $0.id == id })?.isArchived == true {
            activeConversation = nil
        }
        if count > 0 {
            showToast("\(count) conversation\(count == 1 ? "" : "s") archived", type: .info)
        } else {
            showToast("No old conversations to archive", type: .info)
        }
    }

    func setReaction(messageId: String, reaction: MessageReaction?) {
        guard let convId = activeConversation?.id else { return }
        if let msgIdx = activeConversation?.messages.firstIndex(where: { $0.id == messageId }) {
            activeConversation?.messages[msgIdx].reaction = reaction
        }
        if let convIdx = conversations.firstIndex(where: { $0.id == convId }),
           let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[convIdx].messages[msgIdx].reaction = reaction
        }
        if let updated = conversations.first(where: { $0.id == convId }) {
            service.saveConversation(updated)
        }
    }

    // MARK: - Bookmarks

    func toggleBookmark(messageId: String) {
        // Toggle in activeConversation
        if let msgIdx = activeConversation?.messages.firstIndex(where: { $0.id == messageId }) {
            activeConversation?.messages[msgIdx].isBookmarked.toggle()
        }
        // Toggle in conversations array
        for convIdx in conversations.indices {
            if let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId }) {
                conversations[convIdx].messages[msgIdx].isBookmarked.toggle()
                service.saveConversation(conversations[convIdx])
                break
            }
        }
    }

    var bookmarkedMessages: [(conversation: Conversation, message: ChatMessage)] {
        conversations.flatMap { conv in
            conv.messages
                .filter { $0.isBookmarked }
                .map { (conversation: conv, message: $0) }
        }
    }

    func allBookmarkedMessages() -> [(Conversation, ChatMessage)] {
        conversations.flatMap { conv in
            conv.messages
                .filter { $0.isBookmarked }
                .map { (conv, $0) }
        }
    }

    func removeBookmark(conversationId: String, messageId: String) {
        // Remove in conversations array
        if let convIdx = conversations.firstIndex(where: { $0.id == conversationId }),
           let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[convIdx].messages[msgIdx].isBookmarked = false
            service.saveConversation(conversations[convIdx])
        }
        // Remove in activeConversation if it matches
        if activeConversation?.id == conversationId,
           let msgIdx = activeConversation?.messages.firstIndex(where: { $0.id == messageId }) {
            activeConversation?.messages[msgIdx].isBookmarked = false
        }
    }

    func clearAllBookmarks() {
        for convIdx in conversations.indices {
            for msgIdx in conversations[convIdx].messages.indices {
                if conversations[convIdx].messages[msgIdx].isBookmarked {
                    conversations[convIdx].messages[msgIdx].isBookmarked = false
                }
            }
            service.saveConversation(conversations[convIdx])
        }
        if var active = activeConversation {
            for msgIdx in active.messages.indices {
                active.messages[msgIdx].isBookmarked = false
            }
            activeConversation = active
        }
    }

    func renameConversation(_ conv: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx].title = trimmed
            conversations[idx].titleManuallySet = true
        }
        if activeConversation?.id == conv.id {
            activeConversation?.title = trimmed
            activeConversation?.titleManuallySet = true
        }
        if let updated = conversations.first(where: { $0.id == conv.id }) {
            service.saveConversation(updated)
        }
    }

    // MARK: - Tags

    var allTags: [String] {
        Array(Set(conversations.flatMap { $0.tags })).sorted()
    }

    func addTag(to conversationId: String, tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            if !conversations[idx].tags.contains(trimmed) {
                conversations[idx].tags.append(trimmed)
            }
        }
        if activeConversation?.id == conversationId {
            if !(activeConversation?.tags.contains(trimmed) ?? false) {
                activeConversation?.tags.append(trimmed)
            }
        }
        if let updated = conversations.first(where: { $0.id == conversationId }) {
            service.saveConversation(updated)
        }
    }

    func removeTag(from conversationId: String, tag: String) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].tags.removeAll { $0 == tag }
        }
        if activeConversation?.id == conversationId {
            activeConversation?.tags.removeAll { $0 == tag }
        }
        if let updated = conversations.first(where: { $0.id == conversationId }) {
            service.saveConversation(updated)
        }
    }

    func allUniqueTags() -> [String] {
        Array(Set(conversations.flatMap { $0.tags })).sorted()
    }

    /// Predefined tag color palette
    static let tagColorPalette: [(name: String, color: Color)] = [
        ("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green),
        ("blue", .blue), ("purple", .purple), ("pink", .pink), ("gray", .gray)
    ]

    func tagColor(for tag: String) -> Color {
        if let colorName = tagColors[tag],
           let match = Self.tagColorPalette.first(where: { $0.name == colorName }) {
            return match.color
        }
        // Fallback: assign based on index in sorted unique tags
        let sorted = allUniqueTags()
        if let idx = sorted.firstIndex(of: tag) {
            return Self.tagColorPalette[idx % Self.tagColorPalette.count].color
        }
        return .gray
    }

    func renameTag(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, oldName != trimmed else { return }
        for idx in conversations.indices {
            if let tagIdx = conversations[idx].tags.firstIndex(of: oldName) {
                conversations[idx].tags[tagIdx] = trimmed
                service.saveConversation(conversations[idx])
            }
        }
        if let tagIdx = activeConversation?.tags.firstIndex(of: oldName) {
            activeConversation?.tags[tagIdx] = trimmed
        }
        // Migrate color mapping
        if let color = tagColors[oldName] {
            tagColors.removeValue(forKey: oldName)
            tagColors[trimmed] = color
        }
        // Migrate filter selection
        if selectedFilterTags.contains(oldName) {
            selectedFilterTags.remove(oldName)
            selectedFilterTags.insert(trimmed)
        }
        if filterTag == oldName {
            filterTag = trimmed
        }
    }

    func deleteTag(_ tag: String) {
        for idx in conversations.indices {
            if conversations[idx].tags.contains(tag) {
                conversations[idx].tags.removeAll { $0 == tag }
                service.saveConversation(conversations[idx])
            }
        }
        activeConversation?.tags.removeAll { $0 == tag }
        tagColors.removeValue(forKey: tag)
        selectedFilterTags.remove(tag)
        if filterTag == tag {
            filterTag = nil
        }
    }

    /// Generate contextual quick-reply suggestions based on the assistant's response.
    private func generateSuggestedReplies(from content: String) {
        let lower = content.lowercased()

        // If the response ends with or contains a question
        let hasQuestion = lower.contains("?")
        // If the response contains a numbered/bulleted list or plan
        let hasList = lower.contains("1.") || lower.contains("- ") || lower.contains("step ")
            || lower.contains("plan") || lower.contains("here's what")
        // If the response mentions code
        let hasCode = lower.contains("```") || lower.contains("function ") || lower.contains("def ")
            || lower.contains("class ") || lower.contains("import ") || lower.contains("var ")
            || lower.contains("let ") || lower.contains("const ")

        if hasQuestion && hasList {
            suggestedReplies = ["Yes, proceed", "Tell me more", "No, change approach"]
        } else if hasQuestion {
            suggestedReplies = ["Yes", "No", "Tell me more"]
        } else if hasCode && hasList {
            suggestedReplies = ["Run it", "Explain more", "Modify it"]
        } else if hasCode {
            suggestedReplies = ["Run it", "Explain more", "Modify it"]
        } else if hasList {
            suggestedReplies = ["Proceed", "Tell me more", "Change approach"]
        } else {
            suggestedReplies = ["Continue", "Elaborate", "New topic"]
        }
    }

    /// Generate a clean, readable title from the user's first message.
    private func smartTitle(from text: String) -> String {
        return generateSmartTitle(from: text)
    }

    /// Generate a meaningful title (max 40 chars) from the first user message.
    func generateSmartTitle(from text: String) -> String {
        // Clean up: collapse newlines, strip file attachments, and trim
        let cleaned = text
            .replacingOccurrences(of: "File: [^\n]*```[\\s\\S]*?```", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[Attached: [^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[Image: [^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "New Chat" }

        // Agent command: /agent <name>
        if let agentMatch = cleaned.range(of: "^/agent\\s+(\\S+)", options: .regularExpression) {
            let agentPart = cleaned[agentMatch]
                .replacingOccurrences(of: "/agent ", with: "")
                .trimmingCharacters(in: .whitespaces)
            let name = agentPart.components(separatedBy: " ").first ?? agentPart
            return truncateTitle("Agent: \(name)")
        }

        // Slash commands (e.g. /news, /research)
        if cleaned.hasPrefix("/") {
            let command = cleaned.components(separatedBy: " ").first ?? cleaned
            let rest = String(cleaned.dropFirst(command.count)).trimmingCharacters(in: .whitespaces)
            let label = String(command.dropFirst()).capitalized
            if rest.isEmpty {
                return truncateTitle(label)
            }
            return truncateTitle("\(label): \(rest)")
        }

        // Code request detection
        let codeKeywords = ["write a function", "write a script", "write code", "create a function",
                            "implement", "refactor", "debug", "fix the bug", "code review",
                            "write a class", "create a class", "write a method"]
        let lower = cleaned.lowercased()
        for keyword in codeKeywords {
            if lower.hasPrefix(keyword) || lower.contains("```") {
                let content = cleaned.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return truncateTitle("Code: \(content)")
            }
        }

        // Question: use the question text
        if cleaned.contains("?") {
            if let qEnd = cleaned.firstIndex(of: "?") {
                let question = String(cleaned[cleaned.startIndex...qEnd])
                return truncateTitle(question)
            }
        }

        // First sentence (split on . ! or ?)
        let sentenceEnd = cleaned.rangeOfCharacter(from: CharacterSet(charactersIn: ".!"))
        if let end = sentenceEnd, cleaned.distance(from: cleaned.startIndex, to: end.lowerBound) < 60 {
            let sentence = String(cleaned[cleaned.startIndex...end.lowerBound])
            return truncateTitle(sentence)
        }

        // Fallback: first N words
        return truncateTitle(cleaned)
    }

    /// Truncate a title to max 40 characters at a word boundary, adding "..." if needed.
    private func truncateTitle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 40 else { return trimmed }

        let prefix = String(trimmed.prefix(40))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "..."
        }
        return prefix + "..."
    }

    /// Auto-apply a smart title after the first assistant response, if title was not manually set.
    func autoTitleIfNeeded() {
        guard let conv = activeConversation else { return }
        guard !conv.titleManuallySet else { return }

        // Only auto-title after the first assistant message arrives
        let assistantMessages = conv.messages.filter { $0.role == .assistant && !$0.isStreaming }
        guard assistantMessages.count == 1 else { return }

        // Get first user message
        guard let firstUserMsg = conv.messages.first(where: { $0.role == .user }) else { return }

        let newTitle = generateSmartTitle(from: firstUserMsg.content)
        guard newTitle != conv.title else { return }

        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx].title = newTitle
        }
        activeConversation?.title = newTitle
    }

    /// Generate 2-3 title suggestions based on conversation content.
    func titleSuggestions(for conv: Conversation) -> [String] {
        var suggestions: [String] = []

        // Suggestion from first user message
        if let firstUser = conv.messages.first(where: { $0.role == .user }) {
            suggestions.append(generateSmartTitle(from: firstUser.content))
        }

        // Suggestion from topic words across all user messages
        let allUserText = conv.messages
            .filter { $0.role == .user }
            .map { $0.content }
            .joined(separator: " ")
            .lowercased()

        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "be", "been",
                                       "being", "have", "has", "had", "do", "does", "did", "will",
                                       "would", "could", "should", "may", "might", "can", "to",
                                       "of", "in", "for", "on", "with", "at", "by", "from", "it",
                                       "this", "that", "i", "you", "we", "they", "my", "your",
                                       "and", "or", "but", "not", "no", "if", "so", "me", "what",
                                       "how", "about", "just", "like", "please", "help", "need"]

        let words = allUserText.components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        var freq: [String: Int] = [:]
        for word in words { freq[word, default: 0] += 1 }
        let topWords = freq.sorted { $0.value > $1.value }.prefix(4).map { $0.key.capitalized }

        if topWords.count >= 2 {
            let topicTitle = truncateTitle(topWords.joined(separator: ", "))
            if !suggestions.contains(topicTitle) {
                suggestions.append(topicTitle)
            }
        }

        // Suggestion from agent name + first few words
        if let agent = conv.agentName,
           let firstUser = conv.messages.first(where: { $0.role == .user }) {
            let shortContent = firstUser.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let firstWords = shortContent.components(separatedBy: " ").prefix(4).joined(separator: " ")
            let agentTitle = truncateTitle("\(agent): \(firstWords)")
            if !suggestions.contains(agentTitle) {
                suggestions.append(agentTitle)
            }
        }

        return Array(suggestions.prefix(3))
    }

    func toggleGateway() {
        let wasRunning = gatewayRunning
        Task {
            if wasRunning {
                _ = try? await service.run(args: ["gateway", "--stop"])
            } else {
                _ = try? await service.run(args: ["gateway", "--background"])
            }
            try? await Task.sleep(for: .seconds(1))
            refreshStatus()
            let gwMsg = wasRunning ? "Gateway stopped" : "Gateway started"
            showToast(gwMsg, type: .success)
            addNotification(title: "Gateway", message: gwMsg, type: wasRunning ? .warning : .success)
        }
    }

    func createAgent(name: String, description: String, model: String, systemPrompt: String, triggers: [String]) {
        let backend = model == "claude-code" ? "claude-code" : "api"

        var content = "---\n"
        content += "name: \(name)\n"
        content += "description: \(description)\n"
        content += "model: \(model)\n"
        if backend != "api" {
            content += "backend: \(backend)\n"
        }
        if !triggers.isEmpty {
            content += "triggers:\n"
            for t in triggers {
                content += "  - \(t)\n"
            }
        }
        content += "---\n"
        if !systemPrompt.isEmpty {
            content += systemPrompt + "\n"
        }

        let agentsDir = NSHomeDirectory() + "/.desktop-agent/agents"
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        let path = "\(agentsDir)/\(name).md"

        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            agents = service.loadAgents()
            showToast("Agent \"\(name)\" created", type: .success)
        } catch {
            showToast("Failed to create agent: \(error.localizedDescription)", type: .error)
        }
    }

    func saveAgent(_ agent: AgentInfo, description: String, model: String, systemPrompt: String, triggers: [String]) {
        let backend = model == "claude-code" ? "claude-code" : "api"

        var content = "---\n"
        content += "name: \(agent.name)\n"
        content += "description: \(description)\n"
        content += "model: \(model)\n"
        if backend != "api" {
            content += "backend: \(backend)\n"
        }
        if !triggers.isEmpty {
            content += "triggers:\n"
            for t in triggers {
                content += "  - \(t)\n"
            }
        }
        content += "---\n"
        if !systemPrompt.isEmpty {
            content += systemPrompt + "\n"
        }

        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(agent.name).md"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)

        agents = service.loadAgents()
        showToast("Agent \"\(agent.name)\" updated", type: .success)
    }

    func deleteAgent(_ agent: AgentInfo) {
        let name = agent.name
        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(name).md"
        try? FileManager.default.removeItem(atPath: path)
        agents = service.loadAgents()
        showToast("Agent \"\(name)\" deleted", type: .success)
    }

    /// Deletes an agent by name, removing its .md file and refreshing the agent list.
    func deleteAgent(name: String) {
        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(name).md"
        try? FileManager.default.removeItem(atPath: path)
        agents = service.loadAgents()
        showToast("Agent \"\(name)\" deleted", type: .success)
    }

    /// Updates an existing agent, optionally renaming the file if the name changed.
    func updateAgent(originalName: String, name: String, description: String, model: String, systemPrompt: String, triggers: [String]) {
        let backend = model == "claude-code" ? "claude-code" : "api"

        var content = "---\n"
        content += "name: \(name)\n"
        content += "description: \(description)\n"
        content += "model: \(model)\n"
        if backend != "api" {
            content += "backend: \(backend)\n"
        }
        if !triggers.isEmpty {
            content += "triggers:\n"
            for t in triggers {
                content += "  - \(t)\n"
            }
        }
        content += "---\n"
        if !systemPrompt.isEmpty {
            content += systemPrompt + "\n"
        }

        let agentsDir = NSHomeDirectory() + "/.desktop-agent/agents"

        // If the name changed, delete the old file
        if name != originalName {
            let oldPath = "\(agentsDir)/\(originalName).md"
            try? FileManager.default.removeItem(atPath: oldPath)
        }

        let path = "\(agentsDir)/\(name).md"
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            agents = service.loadAgents()
            showToast("Agent \"\(name)\" updated", type: .success)
        } catch {
            showToast("Failed to update agent: \(error.localizedDescription)", type: .error)
        }
    }

    /// Duplicates an agent by copying its .md file with a "-copy" suffix appended to the name.
    func duplicateAgent(name: String) {
        let sourcePath = NSHomeDirectory() + "/.desktop-agent/agents/\(name).md"
        guard let content = try? String(contentsOfFile: sourcePath, encoding: .utf8) else {
            showToast("Agent file not found", type: .error)
            return
        }

        // Find a unique copy name
        let agentsDir = NSHomeDirectory() + "/.desktop-agent/agents"
        var copyName = "\(name)-copy"
        var counter = 2
        while FileManager.default.fileExists(atPath: "\(agentsDir)/\(copyName).md") {
            copyName = "\(name)-copy-\(counter)"
            counter += 1
        }

        // Replace the name in frontmatter
        let newContent = content.replacingOccurrences(
            of: "(?m)^name:.*$",
            with: "name: \(copyName)",
            options: .regularExpression
        )

        let destPath = "\(agentsDir)/\(copyName).md"
        do {
            try newContent.write(toFile: destPath, atomically: true, encoding: .utf8)
            agents = service.loadAgents()
            showToast("Agent \"\(copyName)\" created", type: .success)
        } catch {
            showToast("Failed to duplicate agent: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Agent Import/Export

    /// Returns the raw .md content for the named agent.
    func exportAgent(name: String) -> String {
        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(name).md"
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    /// Copies an agent .md file into ~/.desktop-agent/agents/ and reloads.
    @discardableResult
    func importAgent(from url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            showToast("Failed to read agent file", type: .error)
            return false
        }
        let result = validateAgentFile(content: content)
        guard result.valid, let agentName = result.name else {
            showToast(result.error ?? "Invalid agent file", type: .error)
            return false
        }
        let agentsDir = NSHomeDirectory() + "/.desktop-agent/agents"
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        let destPath = "\(agentsDir)/\(agentName).md"
        do {
            try content.write(toFile: destPath, atomically: true, encoding: .utf8)
        } catch {
            showToast("Failed to write agent file: \(error.localizedDescription)", type: .error)
            return false
        }
        agents = service.loadAgents()
        showToast("Agent \"\(agentName)\" imported", type: .success)
        return true
    }

    /// Imports agent content with an optional name override (for rename on conflict).
    @discardableResult
    func importAgentContent(_ content: String, overrideName: String? = nil) -> Bool {
        var finalContent = content
        if let newName = overrideName {
            finalContent = content.replacingOccurrences(
                of: "(?m)^name:.*$",
                with: "name: \(newName)",
                options: .regularExpression
            )
        }
        let result = validateAgentFile(content: finalContent)
        guard result.valid, let agentName = result.name else {
            showToast(result.error ?? "Invalid agent file", type: .error)
            return false
        }
        let agentsDir = NSHomeDirectory() + "/.desktop-agent/agents"
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        let destPath = "\(agentsDir)/\(agentName).md"
        do {
            try finalContent.write(toFile: destPath, atomically: true, encoding: .utf8)
        } catch {
            showToast("Failed to write agent file: \(error.localizedDescription)", type: .error)
            return false
        }
        agents = service.loadAgents()
        showToast("Agent \"\(agentName)\" imported", type: .success)
        return true
    }

    /// Validates agent markdown content. Returns validity, parsed name, and error message.
    func validateAgentFile(content: String) -> (valid: Bool, name: String?, error: String?) {
        let lines = content.components(separatedBy: "\n")
        var name: String?
        var model: String?
        var frontmatterCount = 0
        var hasFrontmatter = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                frontmatterCount += 1
                if frontmatterCount >= 2 { hasFrontmatter = true; break }
                continue
            }
            if frontmatterCount == 1 {
                if trimmed.hasPrefix("name:") {
                    name = trimmed.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("model:") {
                    model = trimmed.replacingOccurrences(of: "model:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }

        guard hasFrontmatter else {
            return (false, nil, "File is missing YAML frontmatter (--- delimiters)")
        }
        guard let agentName = name, !agentName.isEmpty else {
            return (false, nil, "Agent file is missing a 'name' field")
        }
        if let m = model, !m.isEmpty {
            let validPrefixes = ["anthropic/", "google/", "openrouter/", "openai/", "claude-code"]
            let hasValidFormat = validPrefixes.contains(where: { m.hasPrefix($0) }) || m.contains("/")
            if !hasValidFormat {
                return (false, agentName, "Model format '\(m)' may be invalid. Expected provider/model or 'claude-code'.")
            }
        }
        return (true, agentName, nil)
    }

    // MARK: - Task CRUD

    func createTask(id: String, description: String, command: String, scheduleType: String,
                    interval: String?, cron: String?, at: String?, platform: String?) {
        var json: [String: Any] = [
            "id": id,
            "description": description,
            "command": command,
            "enabled": true,
            "runCount": 0
        ]

        var schedule: [String: Any] = ["type": scheduleType]
        if let interval = interval { schedule["interval"] = interval }
        if let cron = cron { schedule["cron"] = cron }
        if let at = at { schedule["at"] = at }
        json["schedule"] = schedule

        if let platform = platform, !platform.isEmpty {
            json["delivery"] = ["platform": platform] as [String: Any]
        }

        let tasksDir = NSHomeDirectory() + "/.desktop-agent/tasks"
        try? FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
        let path = "\(tasksDir)/\(id).json"

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }

        tasks = service.loadTasks()
        showToast("Task created", type: .success)
    }

    func deleteTask(_ task: TaskInfo) {
        let path = NSHomeDirectory() + "/.desktop-agent/tasks/\(task.id).json"
        try? FileManager.default.removeItem(atPath: path)
        tasks = service.loadTasks()
        showToast("Task deleted", type: .success)
    }

    func toggleTask(_ task: TaskInfo) {
        let path = NSHomeDirectory() + "/.desktop-agent/tasks/\(task.id).json"
        guard let data = FileManager.default.contents(atPath: path),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let newEnabled = !(task.enabled)
        json["enabled"] = newEnabled
        if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? newData.write(to: URL(fileURLWithPath: path))
        }
        tasks = service.loadTasks()
        showToast("Task \(newEnabled ? "enabled" : "disabled")", type: .info)
    }

    // MARK: - Gateway controls

    func forceStopGateway() {
        if let pid = gatewayPID {
            kill(Int32(pid), SIGKILL)
        }
        // Also try via CLI
        Task {
            _ = try? await service.run(args: ["gateway", "--stop"])
            try? await Task.sleep(for: .seconds(1))
            refreshStatus()
        }
    }

    func installGatewayStartup() {
        Task {
            _ = try? await service.run(args: ["gateway", "--startup"])
            refreshStatus()
        }
    }

    func removeGatewayStartup() {
        Task {
            _ = try? await service.run(args: ["gateway", "--no-startup"])
            refreshStatus()
        }
    }

    var isGatewayAutoStart: Bool {
        let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/com.osai.gateway.plist"
        return FileManager.default.fileExists(atPath: plistPath)
    }

    // MARK: - Export

    enum ExportFormat: String, CaseIterable, Identifiable {
        case markdown = "Markdown"
        case json = "JSON"
        case html = "HTML"
        case plainText = "Plain Text"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .json: return "json"
            case .html: return "html"
            case .plainText: return "txt"
            }
        }

        var icon: String {
            switch self {
            case .markdown: return "text.badge.star"
            case .json: return "curlybraces"
            case .html: return "globe"
            case .plainText: return "doc.plaintext"
            }
        }

        var description: String {
            switch self {
            case .markdown: return "Rich formatting with headers, code blocks, and structure"
            case .json: return "Machine-readable structured data, ideal for imports"
            case .html: return "Styled page with dark theme, bubbles, and code highlighting"
            case .plainText: return "Simple text with User/Assistant prefixes, universal"
            }
        }
    }

    struct ExportOptions {
        var format: ExportFormat = .markdown
        var includeTimestamps: Bool = true
        var includeToolActivities: Bool = true
        var includeTokenStats: Bool = true
    }

    @Published var showExportSheet: Bool = false
    @Published var showKeyboardShortcuts: Bool = false
    @Published var exportConversationTarget: Conversation?

    func presentExportSheet(for conv: Conversation) {
        exportConversationTarget = conv
        showExportSheet = true
    }

    func exportAsMarkdown(conversation conv: Conversation, options: ExportOptions = ExportOptions()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var md = "# \(conv.title)\n\n"
        md += "**Date:** \(dateFormatter.string(from: conv.createdAt))"
        if let agent = conv.agentName {
            md += "  \n**Agent:** \(agent)"
        }
        if options.includeTokenStats && conv.totalTokens > 0 {
            md += "  \n**Tokens:** \(conv.totalInputTokens) input / \(conv.totalOutputTokens) output"
            md += String(format: "  \n**Estimated cost:** $%.4f", conv.estimatedCost)
        }
        md += "\n\n---\n"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for msg in conv.messages {
            guard msg.role == .user || msg.role == .assistant else { continue }
            let label = msg.role == .user ? "You" : "Assistant"

            if options.includeTimestamps {
                md += "\n### \(label) _(\(timeFormatter.string(from: msg.timestamp)))_\n\n"
            } else {
                md += "\n### \(label)\n\n"
            }

            md += msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            md += "\n"

            if options.includeToolActivities && !msg.activities.isEmpty {
                let toolCalls = msg.activities.filter { $0.type == .toolCall }
                if !toolCalls.isEmpty {
                    md += "\n<details><summary>Tool activity (\(toolCalls.count) call\(toolCalls.count == 1 ? "" : "s"))</summary>\n\n"
                    for activity in toolCalls {
                        let status = activity.success == true ? "ok" : (activity.success == false ? "failed" : "?")
                        let duration = activity.durationMs.map { " (\($0)ms)" } ?? ""
                        md += "- **\(activity.label)** [\(status)]\(duration)"
                        if !activity.detail.isEmpty {
                            md += " -- \(activity.detail)"
                        }
                        md += "\n"
                    }
                    md += "\n</details>\n"
                }
            }

            md += "\n---\n"
        }

        return md
    }

    // MARK: - Sharing Helpers

    /// Formats a single message for sharing (plain text with role label and footer).
    func formatMessageForSharing(message: ChatMessage) -> String {
        let label = message.role == .user ? "You:" : "Assistant:"
        let body = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(label)\n\(body)\n\n\u{2014} Shared from OSAI"
    }

    /// Formats multiple messages for sharing as a conversation excerpt.
    func formatMessagesForSharing(messages: [ChatMessage]) -> String {
        var result = ""
        for msg in messages {
            guard msg.role == .user || msg.role == .assistant else { continue }
            let label = msg.role == .user ? "You:" : "Assistant:"
            let body = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            result += "\(label)\n\(body)\n\n"
        }
        result += "\u{2014} Shared from OSAI"
        return result
    }

    /// Converts a message to rich text (NSAttributedString) with basic markdown formatting.
    func messageAsRichText(message: ChatMessage) -> NSAttributedString {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = NSMutableAttributedString()

        // Role label
        let label = message.role == .user ? "You:" : "Assistant:"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ]
        result.append(NSAttributedString(string: "\(label)\n", attributes: labelAttrs))

        // Body — apply basic markdown formatting
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor
        ]

        let boldPattern = #"\*\*(.+?)\*\*"#
        let codePattern = #"`([^`]+)`"#
        var processed = content

        // Replace bold markers with a placeholder to track ranges later
        // For simplicity, build an attributed string by processing segments
        let segments = parseMarkdownSegments(processed)
        for segment in segments {
            switch segment {
            case .plain(let text):
                result.append(NSAttributedString(string: text, attributes: bodyAttrs))
            case .bold(let text):
                let boldAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
                result.append(NSAttributedString(string: text, attributes: boldAttrs))
            case .code(let text):
                let codeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .backgroundColor: NSColor.quaternaryLabelColor
                ]
                result.append(NSAttributedString(string: text, attributes: codeAttrs))
            }
        }

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        result.append(NSAttributedString(string: "\n\n\u{2014} Shared from OSAI", attributes: footerAttrs))

        _ = processed // suppress unused warning
        return result
    }

    // stripMarkdown is defined in the Text-to-Speech section below

    // MARK: - Markdown Segment Parsing (private)

    private enum MarkdownSegment {
        case plain(String)
        case bold(String)
        case code(String)
    }

    private func parseMarkdownSegments(_ text: String) -> [MarkdownSegment] {
        // Combined pattern: bold (**text**) or inline code (`text`)
        let pattern = #"\*\*(.+?)\*\*|`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.plain(text)]
        }

        var segments: [MarkdownSegment] = []
        let nsText = text as NSString
        var lastEnd = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let matchRange = match.range
            // Plain text before this match
            if matchRange.location > lastEnd {
                let plainRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                segments.append(.plain(nsText.substring(with: plainRange)))
            }

            // Check which capture group matched
            if match.range(at: 1).location != NSNotFound {
                // Bold
                segments.append(.bold(nsText.substring(with: match.range(at: 1))))
            } else if match.range(at: 2).location != NSNotFound {
                // Code
                segments.append(.code(nsText.substring(with: match.range(at: 2))))
            }

            lastEnd = matchRange.location + matchRange.length
        }

        // Trailing plain text
        if lastEnd < nsText.length {
            segments.append(.plain(nsText.substring(from: lastEnd)))
        }

        return segments
    }

    func exportAsJSON(conversation conv: Conversation, options: ExportOptions = ExportOptions()) -> String {
        var dict: [String: Any] = [
            "id": conv.id,
            "title": conv.title,
            "createdAt": ISO8601DateFormatter().string(from: conv.createdAt)
        ]
        if let agent = conv.agentName { dict["agentName"] = agent }
        if options.includeTokenStats {
            dict["totalInputTokens"] = conv.totalInputTokens
            dict["totalOutputTokens"] = conv.totalOutputTokens
            dict["estimatedCost"] = conv.estimatedCost
        }

        let timeFormatter = ISO8601DateFormatter()
        var messagesArray: [[String: Any]] = []
        for msg in conv.messages {
            guard msg.role == .user || msg.role == .assistant else { continue }
            var m: [String: Any] = [
                "role": msg.role.rawValue,
                "content": msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            if options.includeTimestamps {
                m["timestamp"] = timeFormatter.string(from: msg.timestamp)
            }
            if let agentName = msg.agentName { m["agentName"] = agentName }
            if options.includeToolActivities && !msg.activities.isEmpty {
                let acts: [[String: Any]] = msg.activities.compactMap { a in
                    guard a.type == .toolCall else { return nil }
                    var ad: [String: Any] = ["tool": a.label]
                    if !a.detail.isEmpty { ad["detail"] = a.detail }
                    if let s = a.success { ad["success"] = s }
                    if let d = a.durationMs { ad["durationMs"] = d }
                    return ad
                }
                if !acts.isEmpty { m["toolCalls"] = acts }
            }
            messagesArray.append(m)
        }
        dict["messages"] = messagesArray

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func exportAsPlainText(conversation conv: Conversation, options: ExportOptions = ExportOptions()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var text = "\(conv.title)\n"
        text += String(repeating: "=", count: conv.title.count) + "\n"
        text += "Date: \(dateFormatter.string(from: conv.createdAt))\n"
        if let agent = conv.agentName {
            text += "Agent: \(agent)\n"
        }
        if options.includeTokenStats && conv.totalTokens > 0 {
            text += "Tokens: \(conv.totalInputTokens) input / \(conv.totalOutputTokens) output\n"
            text += String(format: "Estimated cost: $%.4f\n", conv.estimatedCost)
        }
        text += "\n"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for msg in conv.messages {
            guard msg.role == .user || msg.role == .assistant else { continue }
            let label = msg.role == .user ? "You" : "Assistant"

            if options.includeTimestamps {
                text += "[\(timeFormatter.string(from: msg.timestamp))] \(label):\n"
            } else {
                text += "\(label):\n"
            }

            text += msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            text += "\n\n"

            if options.includeToolActivities && !msg.activities.isEmpty {
                let toolCalls = msg.activities.filter { $0.type == .toolCall }
                if !toolCalls.isEmpty {
                    text += "  Tools used:\n"
                    for activity in toolCalls {
                        let status = activity.success == true ? "ok" : (activity.success == false ? "failed" : "?")
                        let duration = activity.durationMs.map { " (\($0)ms)" } ?? ""
                        text += "    - \(activity.label) [\(status)]\(duration)\n"
                    }
                    text += "\n"
                }
            }
        }

        return text
    }

    func exportAsHTML(conversation conv: Conversation, options: ExportOptions = ExportOptions()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        func escapeHTML(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        /// Convert inline markdown (bold, inline code) and code blocks to HTML.
        func markdownToHTML(_ text: String) -> String {
            let escaped = escapeHTML(text)
            var result = escaped

            // Fenced code blocks: ```lang\n...\n```
            let codeBlockPattern = #"```(\w*)\n([\s\S]*?)```"#
            if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
                let ns = result as NSString
                var output = ""
                var lastEnd = 0
                for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                    let before = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                    output += ns.substring(with: before)
                    let lang = ns.substring(with: match.range(at: 1))
                    let code = ns.substring(with: match.range(at: 2))
                    let langAttr = lang.isEmpty ? "" : " data-lang=\"\(lang)\""
                    output += "<pre><code\(langAttr)>\(code)</code></pre>"
                    lastEnd = match.range.location + match.range.length
                }
                if lastEnd < ns.length { output += ns.substring(from: lastEnd) }
                result = output
            }

            // Inline code
            if let regex = try? NSRegularExpression(pattern: #"`([^`]+)`"#, options: []) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "<code>$1</code>")
            }
            // Bold
            if let regex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#, options: []) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "<strong>$1</strong>")
            }
            // Line breaks (outside of pre blocks) — simple approach: convert double newlines to <p> boundaries
            result = result.replacingOccurrences(of: "\n\n", with: "</p><p>")
            result = result.replacingOccurrences(of: "\n", with: "<br>")
            return "<p>" + result + "</p>"
        }

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(escapeHTML(conv.title))</title>
        <style>
        :root { --accent: #50c8c8; --bg: #0a0a0f; --bg2: #12121a; --card: #181822; --text: #e8e8ed; --text2: #8888a0; --border: rgba(80,200,200,0.15); }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; padding: 40px 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        header { margin-bottom: 32px; padding-bottom: 20px; border-bottom: 1px solid var(--border); }
        header h1 { font-size: 24px; font-weight: 700; color: var(--accent); margin-bottom: 8px; }
        header .meta { font-size: 13px; color: var(--text2); }
        header .meta span { margin-right: 16px; }
        .message { margin-bottom: 20px; padding: 16px 20px; border-radius: 12px; border: 1px solid var(--border); }
        .message.user { background: var(--bg2); border-left: 3px solid var(--accent); }
        .message.assistant { background: var(--card); }
        .message .role { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px; }
        .message.user .role { color: var(--accent); }
        .message.assistant .role { color: var(--text2); }
        .message .timestamp { font-size: 10px; color: var(--text2); float: right; margin-top: 2px; }
        .message .content { font-size: 14px; }
        .message .content p { margin-bottom: 8px; }
        .message .content p:last-child { margin-bottom: 0; }
        .tools { margin-top: 12px; padding-top: 10px; border-top: 1px solid var(--border); font-size: 12px; color: var(--text2); }
        .tools summary { cursor: pointer; font-weight: 500; }
        .tools ul { margin: 6px 0 0 18px; }
        .tools li { margin-bottom: 2px; }
        pre { background: #0d0d14; border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px; overflow-x: auto; margin: 8px 0; }
        code { font-family: 'SF Mono', Menlo, monospace; font-size: 13px; }
        :not(pre) > code { background: rgba(80,200,200,0.1); padding: 2px 6px; border-radius: 4px; font-size: 12px; }
        strong { font-weight: 600; }
        footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid var(--border); font-size: 11px; color: var(--text2); text-align: center; }
        </style>
        </head>
        <body>
        <div class="container">
        <header>
        <h1>\(escapeHTML(conv.title))</h1>
        <div class="meta">
        <span>\(escapeHTML(dateFormatter.string(from: conv.createdAt)))</span>
        """

        if let agent = conv.agentName {
            html += "<span>Agent: \(escapeHTML(agent))</span>\n"
        }
        if options.includeTokenStats && conv.totalTokens > 0 {
            html += "<span>\(conv.totalInputTokens) input / \(conv.totalOutputTokens) output tokens</span>\n"
            html += String(format: "<span>Est. $%.4f</span>\n", conv.estimatedCost)
        }

        html += """
        </div>
        </header>
        """

        for msg in conv.messages {
            guard msg.role == .user || msg.role == .assistant else { continue }
            let roleClass = msg.role == .user ? "user" : "assistant"
            let roleLabel = msg.role == .user ? "You" : "Assistant"
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)

            html += "<div class=\"message \(roleClass)\">\n"
            html += "<div class=\"role\">\(roleLabel)"
            if options.includeTimestamps {
                html += "<span class=\"timestamp\">\(escapeHTML(timeFormatter.string(from: msg.timestamp)))</span>"
            }
            html += "</div>\n"
            html += "<div class=\"content\">\(markdownToHTML(content))</div>\n"

            if options.includeToolActivities && !msg.activities.isEmpty {
                let toolCalls = msg.activities.filter { $0.type == .toolCall }
                if !toolCalls.isEmpty {
                    html += "<div class=\"tools\"><details><summary>Tool activity (\(toolCalls.count) call\(toolCalls.count == 1 ? "" : "s"))</summary><ul>\n"
                    for activity in toolCalls {
                        let status = activity.success == true ? "ok" : (activity.success == false ? "failed" : "?")
                        let duration = activity.durationMs.map { " (\($0)ms)" } ?? ""
                        let detail = activity.detail.isEmpty ? "" : " &mdash; \(escapeHTML(activity.detail))"
                        html += "<li><strong>\(escapeHTML(activity.label))</strong> [\(status)]\(duration)\(detail)</li>\n"
                    }
                    html += "</ul></details></div>\n"
                }
            }

            html += "</div>\n"
        }

        html += """
        <footer>Exported from OSAI</footer>
        </div>
        </body>
        </html>
        """

        return html
    }

    func exportAllAsMarkdown(options: ExportOptions = ExportOptions()) -> String {
        var md = "# All Conversations\n\n"
        md += "Exported: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n"
        md += "Total: \(conversations.count) conversation\(conversations.count == 1 ? "" : "s")\n\n"

        let sorted = conversations.sorted { $0.createdAt > $1.createdAt }
        for (i, conv) in sorted.enumerated() {
            if i > 0 { md += "\n\n---\n\n" }
            md += exportAsMarkdown(conversation: conv, options: options)
        }

        return md
    }

    func generateExport(for conv: Conversation, options: ExportOptions) -> String {
        switch options.format {
        case .markdown:
            return exportAsMarkdown(conversation: conv, options: options)
        case .json:
            return exportAsJSON(conversation: conv, options: options)
        case .html:
            return exportAsHTML(conversation: conv, options: options)
        case .plainText:
            return exportAsPlainText(conversation: conv, options: options)
        }
    }

    // MARK: - Search Scope

    enum SearchScope: String, CaseIterable, Identifiable {
        case currentChat = "currentChat"
        case allChats = "allChats"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .currentChat: return "Current Chat"
            case .allChats: return "All Chats"
            }
        }
    }

    @Published var searchScope: SearchScope = .allChats

    /// Search within the active conversation and return indices of matching messages
    func searchInCurrentConversation(query: String) -> [Int] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conv = activeConversation else { return [] }
        let lower = trimmed.lowercased()
        var indices: [Int] = []
        for (index, msg) in conv.messages.enumerated() {
            guard msg.role == .user || msg.role == .assistant else { continue }
            if msg.content.lowercased().contains(lower) {
                indices.append(index)
            }
        }
        return indices
    }

    // MARK: - Search Filters

    struct SearchFilters: Equatable {
        var hasCode: Bool = false
        var hasBookmark: Bool = false
        var modelId: String? = nil
        var role: MessageRole? = nil
        var dateRange: (start: Date, end: Date)? = nil

        var activeCount: Int {
            var count = 0
            if hasCode { count += 1 }
            if hasBookmark { count += 1 }
            if modelId != nil { count += 1 }
            if role != nil { count += 1 }
            if dateRange != nil { count += 1 }
            return count
        }

        var isEmpty: Bool { activeCount == 0 }

        static func == (lhs: SearchFilters, rhs: SearchFilters) -> Bool {
            lhs.hasCode == rhs.hasCode &&
            lhs.hasBookmark == rhs.hasBookmark &&
            lhs.modelId == rhs.modelId &&
            lhs.role == rhs.role &&
            lhs.dateRange?.start == rhs.dateRange?.start &&
            lhs.dateRange?.end == rhs.dateRange?.end
        }
    }

    func searchMessages(query: String, filters: SearchFilters) -> [(Conversation, ChatMessage)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var results: [(Conversation, ChatMessage)] = []

        for conv in conversations {
            // Model filter applies at conversation level
            if let modelFilter = filters.modelId, conv.modelId != modelFilter {
                continue
            }

            for msg in conv.messages {
                guard msg.role == .user || msg.role == .assistant else { continue }

                // Text query filter
                if !trimmed.isEmpty && !msg.content.lowercased().contains(trimmed) {
                    continue
                }

                // Role filter
                if let roleFilter = filters.role, msg.role != roleFilter {
                    continue
                }

                // Code filter: check for markdown code blocks or inline code
                if filters.hasCode {
                    let hasCodeBlock = msg.content.contains("```") || msg.content.contains("`")
                    if !hasCodeBlock { continue }
                }

                // Bookmark filter
                if filters.hasBookmark && !msg.isBookmarked {
                    continue
                }

                // Date range filter
                if let range = filters.dateRange {
                    if msg.timestamp < range.start || msg.timestamp > range.end {
                        continue
                    }
                }

                results.append((conv, msg))
            }
        }

        return results
    }

    // MARK: - Full-text search across all conversations

    struct ConversationSearchResult: Identifiable {
        let id: String
        let conversation: Conversation
        let matches: [ChatMessage]

        init(conversation: Conversation, matches: [ChatMessage]) {
            self.id = conversation.id
            self.conversation = conversation
            self.matches = matches
        }
    }

    func searchAllConversations(query: String) -> [ConversationSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()

        return conversations.compactMap { conv in
            let matchingMessages = conv.messages.filter { msg in
                (msg.role == .user || msg.role == .assistant) &&
                msg.content.lowercased().contains(lower)
            }
            guard !matchingMessages.isEmpty else { return nil }
            return ConversationSearchResult(conversation: conv, matches: matchingMessages)
        }
    }

    func exportConversation(_ conv: Conversation) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var md = "# \(conv.title)\n"
        md += "Date: \(dateFormatter.string(from: conv.createdAt))"
        if let agent = conv.agentName {
            md += " | Agent: \(agent)"
        }
        md += "\n\n---\n"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for msg in conv.messages {
            guard msg.role == .user || msg.role == .assistant else { continue }
            let label = msg.role == .user ? "User" : "Assistant"
            md += "\n**\(label)** _(\(timeFormatter.string(from: msg.timestamp)))_:\n\n"
            md += msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            md += "\n\n---\n"
        }

        return md
    }

    // MARK: - Code Block Extraction

    func extractCodeBlocks(from conversation: Conversation) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return blocks }

        for (index, message) in conversation.messages.enumerated() {
            guard message.role == .assistant else { continue }
            let content = message.content
            let nsContent = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let langRange = match.range(at: 1)
                let codeRange = match.range(at: 2)
                let language = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""
                let code = codeRange.location != NSNotFound ? nsContent.substring(with: codeRange) : ""
                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedCode.isEmpty else { continue }
                blocks.append(CodeBlock(
                    language: language.isEmpty ? "text" : language,
                    code: trimmedCode,
                    messageIndex: index
                ))
            }
        }
        return blocks
    }

    func exportAndSave(_ conv: Conversation) {
        let panel = NSSavePanel()
        panel.title = "Export Conversation"
        let safeName = conv.title
            .replacingOccurrences(of: "[^a-zA-Z0-9_ -]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = String(safeName.prefix(60)) + ".md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let markdown = exportConversation(conv)
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            showToast("Conversation exported", type: .success)
        } catch {
            showToast("Export failed: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Text-to-Speech

    func setupSpeechDelegate() {
        let delegate = SpeechDelegate { [weak self] in
            DispatchQueue.main.async {
                self?.isSpeaking = false
                self?.speakingMessageId = nil
            }
        }
        self.speechDelegate = delegate
        speechSynthesizer.delegate = delegate
    }

    func speakMessage(id: String, content: String) {
        // If already speaking this message, stop
        if isSpeaking && speakingMessageId == id {
            stopSpeaking()
            return
        }
        // Stop any current speech first
        if isSpeaking {
            speechSynthesizer.stopSpeaking()
        }

        if speechDelegate == nil {
            setupSpeechDelegate()
        }

        let stripped = stripMarkdown(content)
        guard !stripped.isEmpty else { return }

        speakingMessageId = id
        isSpeaking = true
        speechSynthesizer.startSpeaking(stripped)
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking()
        isSpeaking = false
        speakingMessageId = nil
    }

    /// Strips markdown formatting from text for clean speech output.
    func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove code blocks (```...```)
        if let regex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove inline code (`...`)
        if let regex = try? NSRegularExpression(pattern: "`[^`]+`", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove HTML tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Convert markdown links [text](url) -> text
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]+\\)", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1")
        }
        // Remove headers (# ## ### etc.)
        if let regex = try? NSRegularExpression(pattern: "^#{1,6}\\s+", options: [.anchorsMatchLines]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove bold (**text** or __text__)
        if let regex = try? NSRegularExpression(pattern: "(\\*\\*|__)(.+?)(\\*\\*|__)", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$2")
        }
        // Remove italic (*text* or _text_)
        if let regex = try? NSRegularExpression(pattern: "(?<![\\*_])(\\*|_)(.+?)(\\*|_)(?![\\*_])", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$2")
        }
        // Remove strikethrough (~~text~~)
        if let regex = try? NSRegularExpression(pattern: "~~(.+?)~~", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1")
        }
        // Remove horizontal rules
        if let regex = try? NSRegularExpression(pattern: "^[\\-\\*_]{3,}$", options: [.anchorsMatchLines]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove list markers (- * + and numbered)
        if let regex = try? NSRegularExpression(pattern: "^\\s*[\\-\\*\\+]\\s+", options: [.anchorsMatchLines]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: "^\\s*\\d+\\.\\s+", options: [.anchorsMatchLines]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Collapse multiple newlines
        if let regex = try? NSRegularExpression(pattern: "\\n{3,}", options: []) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Speech Delegate

final class SpeechDelegate: NSObject, NSSpeechSynthesizerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        onFinish()
    }
}

/// Mutable state shared between streaming callback and MainActor code.
/// Only accessed from the main thread via handleAppEvent.
class StreamState: @unchecked Sendable {
    var activeActivityIds: [String: String] = [:]  // event id -> activity id
    var accumulatedText: String = ""
    var firstTextReceived: Bool = false
}
