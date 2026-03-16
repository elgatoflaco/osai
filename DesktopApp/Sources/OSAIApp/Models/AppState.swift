import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import UserNotifications

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

enum ConversationSortOrder: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case oldest = "Oldest first"
    case mostMessages = "Most messages"
    case mostTokens = "Most tokens"
    case alphabetical = "Alphabetical"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .oldest: return "clock.arrow.circlepath"
        case .mostMessages: return "bubble.left.and.bubble.right"
        case .mostTokens: return "number"
        case .alphabetical: return "textformat.abc"
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

@MainActor
class AppState: ObservableObject {
    @AppStorage("isDarkMode") var isDarkMode: Bool = true
    @AppStorage("sidebarCollapsed") var sidebarCollapsed: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("globalHotkeyEnabled") var globalHotkeyEnabled: Bool = true
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("compactMode") var compactMode: Bool = false
    @AppStorage("floatOnTop") var floatOnTop: Bool = false
    @AppStorage("windowOpacity") var windowOpacity: Double = 1.0
    @AppStorage("quickActionsCollapsed") var quickActionsCollapsed: Bool = false

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

    @Published var selectedTab: SidebarItem = .home
    @Published var agents: [AgentInfo] = []
    @Published var tasks: [TaskInfo] = []
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var gatewayRunning: Bool = false
    @Published var gatewayPID: Int?
    @Published var config: AppConfig = AppConfig()
    @Published var isLoading: Bool = false
    @Published var tokensToday: Int = 0
    @Published var costToday: Double = 0.0
    @Published var costMonth: Double = 0.0
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
    @Published var conversationSortOrder: ConversationSortOrder = .recent
    @Published var showArchived: Bool = false
    @Published var filterTag: String?
    @Published var notifications: [AppNotification] = []
    @Published var showNotificationPanel: Bool = false
    @Published var selectedModel: String = "anthropic/claude-sonnet-4-20250514"

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
        switch conversationSortOrder {
        case .recent:
            return convs.sorted { $0.lastUpdated > $1.lastUpdated }
        case .oldest:
            return convs.sorted { $0.lastUpdated < $1.lastUpdated }
        case .mostMessages:
            return convs.sorted { $0.messages.count > $1.messages.count }
        case .mostTokens:
            return convs.sorted { $0.totalTokens > $1.totalTokens }
        case .alphabetical:
            return convs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
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
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        }

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

    func branchConversation(from conversationId: String, atMessageIndex: Int) {
        guard let source = conversations.first(where: { $0.id == conversationId }) else { return }
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
        case plainText = "Plain Text"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .json: return "json"
            case .plainText: return "txt"
            }
        }

        var icon: String {
            switch self {
            case .markdown: return "text.badge.star"
            case .json: return "curlybraces"
            case .plainText: return "doc.plaintext"
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
        case .plainText:
            return exportAsPlainText(conversation: conv, options: options)
        }
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
}

/// Mutable state shared between streaming callback and MainActor code.
/// Only accessed from the main thread.
@MainActor
class StreamState {
    var activeActivityIds: [String: String] = [:]  // event id -> activity id
    var accumulatedText: String = ""
}
