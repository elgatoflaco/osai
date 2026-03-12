import Foundation

// MARK: - Agent Status

enum AgentStatus: String, Codable, Sendable {
    case idle
    case working
    case error
    case offline

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .error: return "Error"
        case .offline: return "Offline"
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "checkmark.circle.fill"
        case .working: return "gear.badge"
        case .error: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }

    var color: String {
        switch self {
        case .idle: return "green"
        case .working: return "blue"
        case .error: return "red"
        case .offline: return "gray"
        }
    }
}

// MARK: - Agent Task

struct AgentTask: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let status: TaskStatus
    let progress: Double

    enum TaskStatus: String, Codable, Sendable {
        case pending
        case running
        case completed
        case failed
    }

    var statusIcon: String {
        switch status {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        }
    }
}

// MARK: - Watch Message

struct WatchMessage: Identifiable, Codable, Sendable {
    let id: String
    let text: String
    let timestamp: Date
    let isFromAgent: Bool

    init(id: String = UUID().uuidString, text: String, timestamp: Date = Date(), isFromAgent: Bool) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isFromAgent = isFromAgent
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Geofence

struct Geofence: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    var isActive: Bool

    init(id: String = UUID().uuidString, name: String, latitude: Double, longitude: Double, radius: Double, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isActive = isActive
    }
}

// MARK: - Health Snapshot

struct HealthSnapshot: Codable, Sendable {
    var heartRate: Double
    var steps: Int
    var movePercent: Double
    var exercisePercent: Double
    var standPercent: Double

    static let empty = HealthSnapshot(heartRate: 0, steps: 0, movePercent: 0, exercisePercent: 0, standPercent: 0)

    var summary: String {
        var lines: [String] = []
        lines.append("Heart Rate: \(Int(heartRate)) BPM")
        lines.append("Steps: \(steps)")
        lines.append("Move: \(Int(movePercent * 100))%")
        lines.append("Exercise: \(Int(exercisePercent * 100))%")
        lines.append("Stand: \(Int(standPercent * 100))%")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Connection State

enum ConnectionState: String, Sendable {
    case disconnected
    case searching
    case connected
    case error

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .searching: return "Searching..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }

    var isConnected: Bool { self == .connected }

    var dotColor: String {
        switch self {
        case .disconnected: return "gray"
        case .searching: return "orange"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

// MARK: - Preset Command

struct PresetCommand: Identifiable, Sendable {
    let id: String
    let label: String
    let icon: String
    let command: String

    init(label: String, icon: String, command: String) {
        self.id = UUID().uuidString
        self.label = label
        self.icon = icon
        self.command = command
    }

    static let defaults: [PresetCommand] = [
        PresetCommand(label: "Status", icon: "chart.bar.fill", command: "What's my current system status?"),
        PresetCommand(label: "Tasks", icon: "checklist", command: "List my active tasks"),
        PresetCommand(label: "Summary", icon: "doc.text.fill", command: "Give me a brief summary of recent activity"),
        PresetCommand(label: "Weather", icon: "cloud.sun.fill", command: "What's the weather like?"),
        PresetCommand(label: "Calendar", icon: "calendar", command: "What's on my calendar today?"),
        PresetCommand(label: "Reminders", icon: "bell.fill", command: "What are my upcoming reminders?"),
        PresetCommand(label: "Quick Note", icon: "note.text", command: "Take a quick note:"),
        PresetCommand(label: "Emails", icon: "envelope.fill", command: "Check my recent emails"),
    ]
}

// MARK: - Status Response (from server)

struct StatusResponse: Codable, Sendable {
    let status: String
    let service: String?
    let platform: String?
    let activeTasks: Int?
    let cpuUsage: Double?
    let memoryUsage: Double?
    let agentStatus: String?
    let lastActivity: String?

    enum CodingKeys: String, CodingKey {
        case status, service, platform
        case activeTasks = "active_tasks"
        case cpuUsage = "cpu_usage"
        case memoryUsage = "memory_usage"
        case agentStatus = "agent_status"
        case lastActivity = "last_activity"
    }
}

// MARK: - Poll Response

struct PollResponse: Codable, Sendable {
    let messages: [PollMessage]

    struct PollMessage: Codable, Sendable {
        let text: String
    }
}
