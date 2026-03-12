import AppIntents
import Foundation

// MARK: - Ask Agent Intent

struct AskAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask OSAI Agent"
    static let description = IntentDescription("Ask the OSAI agent a question via voice.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Question", description: "The question to ask the agent")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask OSAI \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected. Open the app to connect.")
        }

        let response = try await connection.sendAndWaitForResponse(text: question)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Check Status Intent

struct CheckStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check OSAI Status"
    static let description = IntentDescription("Get the current status of the OSAI agent.")
    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Check OSAI agent status")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        let status = try await connection.fetchAgentStatus()
        let statusText = """
        Agent: \(status.agentStatus ?? "unknown")
        Tasks: \(status.activeTasks ?? 0)
        CPU: \(Int(status.cpuUsage ?? 0))%
        Memory: \(Int(status.memoryUsage ?? 0))%
        """
        return .result(dialog: IntentDialog(stringLiteral: statusText))
    }
}

// MARK: - Run Command Intent

struct RunCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run OSAI Command"
    static let description = IntentDescription("Execute a predefined command on the OSAI agent.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Command", description: "The command to execute")
    var command: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run OSAI command \(\.$command)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        let response = try await connection.sendAndWaitForResponse(text: command)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Health Summary Intent

struct HealthSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "OSAI Health Summary"
    static let description = IntentDescription("Send a health summary to the OSAI agent and get analysis.")
    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Get health summary from OSAI")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        let healthManager = HealthManager()
        await healthManager.requestAuthorization()
        let summary = await healthManager.generateHealthSummary()

        let response = try await connection.sendAndWaitForResponse(
            text: "[Health Summary Request]\n\(summary)\nPlease analyze my health data."
        )
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Quick Note Intent

struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "OSAI Quick Note"
    static let description = IntentDescription("Send a quick note to the OSAI agent.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Note", description: "The note to send")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send note to OSAI: \(\.$note)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        try await connection.sendMessage(text: "[Quick Note] \(note)")
        return .result(dialog: "Note sent to OSAI agent.")
    }
}

// MARK: - Health Query Intent

struct HealthQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "OSAI Health Query"
    static let description = IntentDescription("Ask OSAI about a specific health metric.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Query", description: "What health info do you want?", default: "How am I doing today?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask OSAI about health: \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        let healthManager = HealthManager()
        await healthManager.requestAuthorization()
        let summary = await healthManager.generateHealthSummary()

        let response = try await connection.sendAndWaitForResponse(
            text: "[Health Query] \(query)\n\nCurrent health data:\n\(summary)"
        )
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Location Query Intent

struct LocationQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "OSAI Location Query"
    static let description = IntentDescription("Ask OSAI about your current location or get location-based suggestions.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Query", description: "What do you want to know about your location?", default: "What's around me?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask OSAI about location: \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        let locationManager = LocationManager()
        locationManager.requestAuthorization()
        // Give a moment for location to update
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let locationSummary = locationManager.generateLocationSummary()
        let response = try await connection.sendAndWaitForResponse(
            text: "[Location Query] \(query)\n\nCurrent location:\n\(locationSummary)"
        )
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Quick Task Intent

struct QuickTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "OSAI Create Task"
    static let description = IntentDescription("Create a quick task for the OSAI agent to handle.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Task", description: "The task to create")
    var task: String

    @Parameter(title: "Priority", description: "Task priority", default: "normal")
    var priority: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create OSAI task: \(\.$task) with priority \(\.$priority)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        let response = try await connection.sendAndWaitForResponse(
            text: "[New Task] Priority: \(priority)\n\(task)"
        )
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Daily Briefing Intent

struct DailyBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "OSAI Daily Briefing"
    static let description = IntentDescription("Get a comprehensive daily briefing from OSAI.")
    static let openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Get daily briefing from OSAI")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        // Gather health data
        let healthManager = HealthManager()
        await healthManager.requestAuthorization()
        let healthSummary = await healthManager.generateHealthSummary()

        let response = try await connection.sendAndWaitForResponse(
            text: "[Daily Briefing Request]\nGive me a comprehensive daily briefing including:\n- Today's schedule and priorities\n- Weather forecast\n- Important reminders\n\nHealth context:\n\(healthSummary)"
        )
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Smart Reminder Intent

struct SmartReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "OSAI Smart Reminder"
    static let description = IntentDescription("Set a smart reminder with the OSAI agent.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Reminder", description: "What to remind about")
    var reminder: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set OSAI reminder: \(\.$reminder)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let connection = IntentConnectionHelper.shared
        guard connection.isConnected else {
            return .result(dialog: "OSAI agent is not connected.")
        }

        let response = try await connection.sendAndWaitForResponse(
            text: "[Reminder] \(reminder)"
        )
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Intent Connection Helper

/// Lightweight connection helper for Siri Intents (does not hold full AgentConnection state).
/// Uses UserDefaults for server config and makes direct HTTP calls.
final class IntentConnectionHelper: @unchecked Sendable {
    static let shared = IntentConnectionHelper()

    private let session: URLSession
    private let defaults = UserDefaults.standard

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    var isConnected: Bool {
        guard let host = defaults.string(forKey: "osai.server.host"), !host.isEmpty else { return false }
        return true
    }

    private var baseURL: String {
        let host = defaults.string(forKey: "osai.server.host") ?? "localhost"
        let port = defaults.integer(forKey: "osai.server.port")
        let effectivePort = port > 0 ? port : 8375
        return "http://\(host):\(effectivePort)"
    }

    private var deviceId: String {
        defaults.string(forKey: "osai.device.id") ?? UUID().uuidString
    }

    func sendMessage(text: String) async throws {
        let url = URL(string: "\(baseURL)/message")!
        let payload: [String: Any] = [
            "device_id": deviceId,
            "user_name": "Siri",
            "text": text
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IntentConnectionError.serverError
        }
    }

    func sendAndWaitForResponse(text: String, maxWait: TimeInterval = 30) async throws -> String {
        try await sendMessage(text: text)

        // Poll for response with backoff
        let pollIntervals: [UInt64] = [
            1_000_000_000, 2_000_000_000, 3_000_000_000, 3_000_000_000,
            3_000_000_000, 3_000_000_000, 3_000_000_000, 3_000_000_000,
            3_000_000_000, 3_000_000_000
        ]

        for interval in pollIntervals {
            try await Task.sleep(nanoseconds: interval)
            let messages = try await pollMessages()
            if let firstResponse = messages.first {
                return firstResponse
            }
        }

        return "Agent is processing your request. Check the app for the response."
    }

    func pollMessages() async throws -> [String] {
        let url = URL(string: "\(baseURL)/poll")!
        let payload: [String: Any] = ["device_id": deviceId]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IntentConnectionError.serverError
        }

        if let pollResponse = try? JSONDecoder().decode(PollResponse.self, from: data) {
            return pollResponse.messages.map { $0.text }
        }
        return []
    }

    func fetchAgentStatus() async throws -> StatusResponse {
        let url = URL(string: "\(baseURL)/ping")!
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IntentConnectionError.serverError
        }
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    enum IntentConnectionError: Error, LocalizedError {
        case serverError
        case timeout

        var errorDescription: String? {
            switch self {
            case .serverError: return "Failed to communicate with OSAI agent"
            case .timeout: return "Request timed out"
            }
        }
    }
}
