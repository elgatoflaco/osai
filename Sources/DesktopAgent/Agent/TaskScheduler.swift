import Foundation

// MARK: - Task Scheduler
//
// Allows the agent to schedule tasks that run automatically.
// Uses macOS launchd plists to execute `osai "command"` at specific times.
//
// ~/.desktop-agent/tasks/
//   daily-briefing.json     → Runs every day at 8:00
//   reminder-5min.json      → Runs once in 5 minutes
//
// Each task generates a LaunchAgent plist at:
//   ~/Library/LaunchAgents/com.desktop-agent.task.<id>.plist

struct ScheduledTask: Codable {
    let id: String
    let description: String
    let command: String          // The prompt to send to osai
    var schedule: TaskSchedule
    var enabled: Bool
    let created: Date
    var lastRun: Date?
    var runCount: Int
    var delivery: DeliveryTarget?  // Where to send results (Discord, Telegram, etc.)

    struct DeliveryTarget: Codable {
        let platform: String   // "discord", "telegram", "whatsapp", "slack"
        let chatId: String     // Channel/chat ID to send to
    }

    enum TaskSchedule: Codable {
        case once(at: Date)                           // Run once at specific time
        case recurring(hour: Int, minute: Int)        // Daily at HH:MM
        case interval(minutes: Int)                   // Every N minutes
        case cron(minute: Int?, hour: Int?, weekday: Int?)  // Cron-like

        enum CodingKeys: String, CodingKey {
            case type, at, hour, minute, minutes, weekday
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .once(let at):
                try container.encode("once", forKey: .type)
                try container.encode(at, forKey: .at)
            case .recurring(let hour, let minute):
                try container.encode("recurring", forKey: .type)
                try container.encode(hour, forKey: .hour)
                try container.encode(minute, forKey: .minute)
            case .interval(let minutes):
                try container.encode("interval", forKey: .type)
                try container.encode(minutes, forKey: .minutes)
            case .cron(let minute, let hour, let weekday):
                try container.encode("cron", forKey: .type)
                if let m = minute { try container.encode(m, forKey: .minute) }
                if let h = hour { try container.encode(h, forKey: .hour) }
                if let w = weekday { try container.encode(w, forKey: .weekday) }
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "once":
                let at = try container.decode(Date.self, forKey: .at)
                self = .once(at: at)
            case "recurring":
                let hour = try container.decode(Int.self, forKey: .hour)
                let minute = try container.decode(Int.self, forKey: .minute)
                self = .recurring(hour: hour, minute: minute)
            case "interval":
                let minutes = try container.decode(Int.self, forKey: .minutes)
                self = .interval(minutes: minutes)
            case "cron":
                let minute = try container.decodeIfPresent(Int.self, forKey: .minute)
                let hour = try container.decodeIfPresent(Int.self, forKey: .hour)
                let weekday = try container.decodeIfPresent(Int.self, forKey: .weekday)
                self = .cron(minute: minute, hour: hour, weekday: weekday)
            default:
                self = .once(at: Date())
            }
        }

        var displayString: String {
            switch self {
            case .once(let at):
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd HH:mm"
                return "once at \(fmt.string(from: at))"
            case .recurring(let hour, let minute):
                return "daily at \(String(format: "%02d:%02d", hour, minute))"
            case .interval(let minutes):
                return "every \(minutes) min"
            case .cron(let minute, let hour, let weekday):
                var parts: [String] = []
                if let h = hour, let m = minute { parts.append("\(String(format: "%02d:%02d", h, m))") }
                if let w = weekday {
                    let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
                    parts.append(w < days.count ? days[w] : "day \(w)")
                }
                return parts.isEmpty ? "cron" : parts.joined(separator: " ")
            }
        }
    }
}

final class TaskScheduler {
    static let tasksDir = NSHomeDirectory() + "/.desktop-agent/tasks"
    static let launchAgentsDir = NSHomeDirectory() + "/Library/LaunchAgents"
    static let plistPrefix = "com.desktop-agent.task."
    static let osaiPath = "/usr/local/bin/osai"

    // MARK: - CRUD

    static func listTasks() -> [ScheduledTask] {
        ensureDir()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: tasksDir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }.compactMap { file in
            let path = tasksDir + "/" + file
            guard let data = fm.contents(atPath: path) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(ScheduledTask.self, from: data)
        }.sorted { $0.created > $1.created }
    }

    static func getTask(id: String) -> ScheduledTask? {
        let path = tasksDir + "/\(id).json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ScheduledTask.self, from: data)
    }

    static func createTask(id: String, description: String, command: String, schedule: ScheduledTask.TaskSchedule, delivery: ScheduledTask.DeliveryTarget? = nil) throws -> ScheduledTask {
        ensureDir()

        let task = ScheduledTask(
            id: id,
            description: description,
            command: command,
            schedule: schedule,
            enabled: true,
            created: Date(),
            lastRun: nil,
            runCount: 0,
            delivery: delivery
        )

        try saveTask(task)
        try installLaunchAgent(task)
        return task
    }

    static func cancelTask(id: String) throws {
        // Unload launchd plist
        let plistPath = launchAgentPath(id: id)
        if FileManager.default.fileExists(atPath: plistPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", plistPath]
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(atPath: plistPath)
        }

        // Remove task file
        let taskPath = tasksDir + "/\(id).json"
        if FileManager.default.fileExists(atPath: taskPath) {
            try FileManager.default.removeItem(atPath: taskPath)
        }
    }

    static func markRun(id: String) {
        guard var task = getTask(id: id) else { return }
        task.lastRun = Date()
        task.runCount += 1

        // If one-time task, disable it
        if case .once = task.schedule {
            task.enabled = false
        }

        try? saveTask(task)
    }

    // MARK: - LaunchAgent Integration

    private static func installLaunchAgent(_ task: ScheduledTask) throws {
        let plistPath = launchAgentPath(id: task.id)

        // Build the plist
        var programArgs: [String] = [osaiPath]
        programArgs.append("--task-id")
        programArgs.append(task.id)
        if let delivery = task.delivery {
            programArgs.append("--deliver")
            programArgs.append("\(delivery.platform):\(delivery.chatId)")
        }
        programArgs.append("[Task mode: Be direct and concise. Use simple shell commands (w3m -dump, curl). Do NOT write elaborate scripts. Do NOT save to temp files. Just execute commands and present results directly.] " + task.command)

        var plist: [String: Any] = [
            "Label": plistPrefix + task.id,
            "ProgramArguments": programArgs,
            "StandardOutPath": tasksDir + "/\(task.id).log",
            "StandardErrorPath": tasksDir + "/\(task.id).log",
            "EnvironmentVariables": [
                "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin",
                "HOME": NSHomeDirectory()
            ]
        ]

        switch task.schedule {
        case .once(let at):
            let delay = at.timeIntervalSinceNow
            if delay > 0 && delay < 1800 {
                // Short delay (< 30 min): use RunAtLoad with a wrapper script that sleeps
                // This is more reliable than StartCalendarInterval for near-future times
                let sleepSeconds = max(1, Int(delay))
                let scriptPath = tasksDir + "/\(task.id).sh"
                let cmdEscaped = programArgs.map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")
                let script = "#!/bin/bash\nsleep \(sleepSeconds)\n\(cmdEscaped)\n"
                try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
                plist["ProgramArguments"] = ["/bin/bash", scriptPath]
                plist["RunAtLoad"] = true
            } else {
                // Future time: use StartCalendarInterval
                let cal = Calendar.current
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                var calendarInterval: [String: Int] = [:]
                if let y = comps.year { calendarInterval["Year"] = y }
                if let m = comps.month { calendarInterval["Month"] = m }
                if let d = comps.day { calendarInterval["Day"] = d }
                if let h = comps.hour { calendarInterval["Hour"] = h }
                if let min = comps.minute { calendarInterval["Minute"] = min }
                plist["StartCalendarInterval"] = calendarInterval
            }

        case .recurring(let hour, let minute):
            plist["StartCalendarInterval"] = [
                "Hour": hour,
                "Minute": minute
            ]

        case .interval(let minutes):
            plist["StartInterval"] = minutes * 60

        case .cron(let minute, let hour, let weekday):
            var interval: [String: Int] = [:]
            if let m = minute { interval["Minute"] = m }
            if let h = hour { interval["Hour"] = h }
            if let w = weekday { interval["Weekday"] = w }
            plist["StartCalendarInterval"] = interval
        }

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath))

        // Load into launchd
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath]
        try process.run()
        process.waitUntilExit()
    }

    private static func launchAgentPath(id: String) -> String {
        return launchAgentsDir + "/\(plistPrefix)\(id).plist"
    }

    private static func saveTask(_ task: ScheduledTask) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(task)
        let path = tasksDir + "/\(task.id).json"
        try data.write(to: URL(fileURLWithPath: path))
    }

    private static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
    }
}
