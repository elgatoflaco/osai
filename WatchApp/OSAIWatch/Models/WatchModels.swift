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
    var sleepHours: Double
    var sleepQuality: SleepQuality
    var activeCalories: Double
    var restingHeartRate: Double
    var heartRateVariability: Double

    static let empty = HealthSnapshot(
        heartRate: 0, steps: 0, movePercent: 0, exercisePercent: 0, standPercent: 0,
        sleepHours: 0, sleepQuality: .unknown, activeCalories: 0,
        restingHeartRate: 0, heartRateVariability: 0
    )

    var summary: String {
        var lines: [String] = []
        lines.append("Heart Rate: \(Int(heartRate)) BPM")
        if restingHeartRate > 0 {
            lines.append("Resting HR: \(Int(restingHeartRate)) BPM")
        }
        if heartRateVariability > 0 {
            lines.append("HRV: \(Int(heartRateVariability)) ms")
        }
        lines.append("Steps: \(steps)")
        lines.append("Active Calories: \(Int(activeCalories)) kcal")
        lines.append("Move: \(Int(movePercent * 100))%")
        lines.append("Exercise: \(Int(exercisePercent * 100))%")
        lines.append("Stand: \(Int(standPercent * 100))%")
        if sleepHours > 0 {
            lines.append("Sleep: \(String(format: "%.1f", sleepHours))h (\(sleepQuality.displayName))")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Sleep Quality

enum SleepQuality: String, Codable, Sendable {
    case poor, fair, good, excellent, unknown

    var displayName: String {
        switch self {
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .poor: return "moon.zzz"
        case .fair: return "moon"
        case .good: return "moon.stars"
        case .excellent: return "moon.stars.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Health Insight

struct HealthInsight: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let category: InsightCategory
    let priority: InsightPriority

    init(title: String, detail: String, icon: String, category: InsightCategory, priority: InsightPriority = .normal) {
        self.id = UUID().uuidString
        self.title = title
        self.detail = detail
        self.icon = icon
        self.category = category
        self.priority = priority
    }

    enum InsightCategory: String, Sendable {
        case heartRate, activity, sleep, recovery
    }

    enum InsightPriority: Int, Comparable, Sendable {
        case low = 0, normal = 1, high = 2, urgent = 3

        static func < (lhs: InsightPriority, rhs: InsightPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

// MARK: - Workout Summary

struct WorkoutSummary: Identifiable, Codable, Sendable {
    let id: String
    let type: String
    let duration: TimeInterval
    let calories: Double
    let startDate: Date
    let endDate: Date
    let averageHeartRate: Double

    init(type: String, duration: TimeInterval, calories: Double, startDate: Date, endDate: Date, averageHeartRate: Double) {
        self.id = UUID().uuidString
        self.type = type
        self.duration = duration
        self.calories = calories
        self.startDate = startDate
        self.endDate = endDate
        self.averageHeartRate = averageHeartRate
    }

    var formattedDuration: String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Location Suggestion

struct LocationSuggestion: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let icon: String
    let command: String
    let latitude: Double
    let longitude: Double

    init(name: String, detail: String, icon: String, command: String, latitude: Double = 0, longitude: Double = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.detail = detail
        self.icon = icon
        self.command = command
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Travel Estimate

struct TravelEstimate: Identifiable, Sendable {
    let id: String
    let destination: String
    let walkingTime: TimeInterval?
    let drivingTime: TimeInterval?
    let distance: Double

    init(destination: String, walkingTime: TimeInterval?, drivingTime: TimeInterval?, distance: Double) {
        self.id = UUID().uuidString
        self.destination = destination
        self.walkingTime = walkingTime
        self.drivingTime = drivingTime
        self.distance = distance
    }

    var formattedWalkingTime: String {
        guard let time = walkingTime else { return "N/A" }
        let minutes = Int(time / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes) min"
    }

    var formattedDrivingTime: String {
        guard let time = drivingTime else { return "N/A" }
        let minutes = Int(time / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes) min"
    }

    var formattedDistance: String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        }
        return "\(Int(distance)) m"
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
