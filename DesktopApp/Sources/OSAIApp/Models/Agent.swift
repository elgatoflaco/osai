import Foundation

struct AgentInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let description: String
    let model: String
    let backend: String
    let triggers: [String]
    var systemPrompt: String = ""

    var displayModel: String {
        if model.contains("/") {
            return String(model.split(separator: "/").last ?? Substring(model))
        }
        return model
    }

    var providerName: String {
        if model.contains("/") {
            return String(model.split(separator: "/").first ?? Substring(model)).capitalized
        }
        return model == "claude-code" ? "Local" : "Unknown"
    }

    var backendLabel: String {
        switch backend {
        case "claude-code": return "Claude Code"
        case "api": return "API"
        default: return backend.capitalized
        }
    }

    var backendIcon: String {
        switch backend {
        case "claude-code": return "terminal"
        default: return "cloud"
        }
    }

    static func == (lhs: AgentInfo, rhs: AgentInfo) -> Bool {
        lhs.name == rhs.name && lhs.model == rhs.model && lhs.backend == rhs.backend
    }
}

struct TaskInfo: Identifiable, Equatable {
    let id: String
    let description: String
    let command: String
    let schedule: TaskSchedule
    var enabled: Bool
    let lastRun: Date?
    let runCount: Int
    let delivery: TaskDelivery?

    var statusLabel: String {
        if !enabled { return "Disabled" }
        if let last = lastRun {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Ran \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "Never run"
    }

    var isOverdue: Bool {
        guard enabled, let last = lastRun else { return false }
        return Date().timeIntervalSince(last) > 86400
    }
}

struct TaskSchedule: Equatable {
    let type: String
    let at: String?
    let cron: String?
    let interval: String?

    var displayLabel: String {
        switch type {
        case "cron": return cron ?? "cron"
        case "interval": return "Every \(interval ?? "?")"
        case "once": return "Once at \(at?.prefix(16) ?? "?")"
        case "daily": return "Daily at \(at ?? "?")"
        default: return type
        }
    }

    var icon: String {
        switch type {
        case "cron": return "calendar.badge.clock"
        case "interval": return "arrow.clockwise"
        case "daily": return "sun.max"
        case "once": return "1.circle"
        default: return "clock"
        }
    }
}

struct TaskDelivery: Equatable {
    let platform: String
    let chatId: String?

    var icon: String {
        switch platform.lowercased() {
        case "discord": return "message.badge.circle"
        case "whatsapp": return "phone.circle"
        case "watch": return "applewatch"
        case "email": return "envelope"
        default: return "arrow.up.circle"
        }
    }
}

struct AppConfig {
    var activeModel: String = "google/gemini-3-flash-preview"
    var apiKeys: [String: APIKeyEntry] = [:]
    var spendingLimits: SpendingLimits = SpendingLimits()
    var gateways: [String: GatewayConfig] = [:]
}

struct APIKeyEntry {
    let provider: String
    let apiKey: String

    var maskedKey: String {
        guard apiKey.count > 8 else { return String(repeating: "*", count: apiKey.count) }
        let prefix = String(apiKey.prefix(6))
        let suffix = String(apiKey.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

struct SpendingLimits {
    var dailyUSD: Double = 15.0
    var monthlyUSD: Double = 50.0
    var perSessionUSD: Double = 5.0
    var warnAtPercent: Int = 70
}

struct GatewayConfig {
    let name: String
    let enabled: Bool

    var icon: String {
        switch name.lowercased() {
        case "discord": return "message.badge.circle"
        case "whatsapp": return "phone.circle"
        case "watch": return "applewatch"
        default: return "network"
        }
    }
}
