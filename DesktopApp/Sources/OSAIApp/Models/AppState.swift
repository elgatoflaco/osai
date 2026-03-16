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

@MainActor
class AppState: ObservableObject {
    @AppStorage("isDarkMode") var isDarkMode: Bool = true
    @AppStorage("sidebarCollapsed") var sidebarCollapsed: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("globalHotkeyEnabled") var globalHotkeyEnabled: Bool = true
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true

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
    @Published var conversationSortOrder: ConversationSortOrder = .recent
    @Published var notifications: [AppNotification] = []
    @Published var showNotificationPanel: Bool = false

    var unreadNotificationCount: Int {
        notifications.filter { !$0.isRead }.count
    }


    /// Returns conversations sorted by the selected sort order, with pinned items always first.
    var sortedConversations: [Conversation] {
        let pinned = conversations.filter { $0.isPinned }
        let unpinned = conversations.filter { !$0.isPinned }
        let sortedPinned = sortConversations(pinned)
        let sortedUnpinned = sortConversations(unpinned)
        return sortedPinned + sortedUnpinned
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

    func loadAll() {
        requestNotificationPermission()
        isLoading = true
        agents = service.loadAgents()
        tasks = service.loadTasks()
        config = service.loadConfig()
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
                agentName: nil
            )
            activeConversation = conv
            conversations.insert(conv, at: 0)
            selectedTab = .chat
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

        let streamState = StreamState()

        // Build CLI args — if this conversation is tied to an agent, use --model
        var args = [fullText]
        if let agentName = activeConversation?.agentName,
           let agent = agents.first(where: { $0.name == agentName }),
           !agent.model.isEmpty {
            args = ["--model", agent.model, fullText]
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

    func renameConversation(_ conv: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx].title = trimmed
        }
        if activeConversation?.id == conv.id {
            activeConversation?.title = trimmed
        }
        if let updated = conversations.first(where: { $0.id == conv.id }) {
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
        // Clean up: collapse newlines and trim
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count > 40 else { return cleaned }

        // Truncate at last word boundary before 40 chars
        let prefix = String(cleaned.prefix(40))
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "..."
        }
        return prefix + "..."
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
