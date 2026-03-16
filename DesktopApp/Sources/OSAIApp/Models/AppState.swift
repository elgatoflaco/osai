import SwiftUI
import Combine

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
    @Published var isProcessing: Bool = false
    @Published var contextPressurePercent: Int = 0
    private(set) var runningProcess: Process?

    let service = OSAIService()
    private let configService = ConfigService()
    private var refreshTimer: Timer?

    func loadAll() {
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
        let status = service.gatewayStatus()
        gatewayRunning = status.running
        gatewayPID = status.pid
        loadSpending()
        tasks = service.loadTasks()
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

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isProcessing else { return }

        if activeConversation == nil {
            let conv = Conversation(
                id: UUID().uuidString,
                title: String(text.prefix(50)),
                messages: [],
                createdAt: Date(),
                agentName: nil
            )
            activeConversation = conv
            conversations.insert(conv, at: 0)
            selectedTab = .chat
        }

        let userMsg = ChatMessage(id: UUID().uuidString, role: .user, content: text, timestamp: Date())
        activeConversation?.messages.append(userMsg)
        syncConversationToList()

        let assistantMsg = ChatMessage(id: UUID().uuidString, role: .assistant, content: "", timestamp: Date(), isStreaming: true)
        activeConversation?.messages.append(assistantMsg)
        syncConversationToList()

        let streamingId = assistantMsg.id
        isProcessing = true

        let streamState = StreamState()

        // Build CLI args — if this conversation is tied to an agent, use --model
        var args = [text]
        if let agentName = activeConversation?.agentName,
           let agent = agents.first(where: { $0.name == agentName }),
           !agent.model.isEmpty {
            args = ["--model", agent.model, text]
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

        case .tokens(_, _):
            break  // Could track for UI display later

        case .contextPressure(let percent):
            contextPressurePercent = percent

        case .error(let message):
            if state.accumulatedText.isEmpty {
                state.accumulatedText = "Error: \(message)"
            } else {
                state.accumulatedText += "\nError: \(message)"
            }
            activeConversation?.messages[idx].content = state.accumulatedText

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

    func startNewChat() {
        activeConversation = nil
        selectedTab = .chat
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
    }

    func toggleGateway() {
        Task {
            if gatewayRunning {
                _ = try? await service.run(args: ["gateway", "--stop"])
            } else {
                _ = try? await service.run(args: ["gateway", "--background"])
            }
            try? await Task.sleep(for: .seconds(1))
            refreshStatus()
        }
    }

    func deleteAgent(_ agent: AgentInfo) {
        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(agent.name).md"
        try? FileManager.default.removeItem(atPath: path)
        agents = service.loadAgents()
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
    }

    func deleteTask(_ task: TaskInfo) {
        let path = NSHomeDirectory() + "/.desktop-agent/tasks/\(task.id).json"
        try? FileManager.default.removeItem(atPath: path)
        tasks = service.loadTasks()
    }

    func toggleTask(_ task: TaskInfo) {
        let path = NSHomeDirectory() + "/.desktop-agent/tasks/\(task.id).json"
        guard let data = FileManager.default.contents(atPath: path),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        json["enabled"] = !(task.enabled)
        if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? newData.write(to: URL(fileURLWithPath: path))
        }
        tasks = service.loadTasks()
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
}

/// Mutable state shared between streaming callback and MainActor code.
/// Only accessed from the main thread.
@MainActor
class StreamState {
    var activeActivityIds: [String: String] = [:]  // event id -> activity id
    var accumulatedText: String = ""
}
