import Foundation

// MARK: - Spending Guard (API Cost Limiter)
//
// Tracks API spending persistently and blocks calls when limits are exceeded.
// Prevents runaway costs from autonomous agents or misconfigured loops.
//
// Config in ~/.desktop-agent/config.json:
//   "spending_limits": {
//     "daily_usd": 5.0,
//     "monthly_usd": 50.0,
//     "per_session_usd": 2.0,
//     "warn_at_percent": 80
//   }

struct SpendingLimits: Codable {
    var dailyUsd: Double?
    var monthlyUsd: Double?
    var perSessionUsd: Double?
    var warnAtPercent: Int?  // 0-100, default 80

    enum CodingKeys: String, CodingKey {
        case dailyUsd = "daily_usd"
        case monthlyUsd = "monthly_usd"
        case perSessionUsd = "per_session_usd"
        case warnAtPercent = "warn_at_percent"
    }
}

final class SpendingGuard {
    private let logPath: String
    private var log: SpendingLog
    private var sessionSpend: Double = 0
    private let limits: SpendingLimits
    private var hasWarnedDaily = false
    private var hasWarnedMonthly = false
    private var hasWarnedSession = false

    struct SpendingLog: Codable {
        var entries: [DayEntry]

        struct DayEntry: Codable {
            var date: String  // "2026-03-12"
            var totalUsd: Double
            var calls: Int
        }
    }

    init(limits: SpendingLimits?) {
        self.limits = limits ?? SpendingLimits()
        self.logPath = AgentConfigFile.configDir + "/spending.json"
        self.log = SpendingGuard.loadLog(path: logPath)
        pruneOldEntries()
    }

    // MARK: - Check Before API Call

    /// Returns nil if OK to proceed, or an error message if limit exceeded
    func checkLimits() -> String? {
        let today = todayString()

        // Daily limit
        if let dailyLimit = limits.dailyUsd {
            let todaySpend = spendForDay(today)
            if todaySpend >= dailyLimit {
                return "Daily spending limit reached ($\(String(format: "%.2f", todaySpend))/$\(String(format: "%.2f", dailyLimit))). Reset tomorrow or increase limit in config."
            }
        }

        // Monthly limit
        if let monthlyLimit = limits.monthlyUsd {
            let monthSpend = spendForCurrentMonth()
            if monthSpend >= monthlyLimit {
                return "Monthly spending limit reached ($\(String(format: "%.2f", monthSpend))/$\(String(format: "%.2f", monthlyLimit))). Resets next month or increase limit in config."
            }
        }

        // Session limit
        if let sessionLimit = limits.perSessionUsd {
            if sessionSpend >= sessionLimit {
                return "Session spending limit reached ($\(String(format: "%.2f", sessionSpend))/$\(String(format: "%.2f", sessionLimit))). Start a new session or increase limit."
            }
        }

        return nil
    }

    /// Check if we should warn (approaching limit). Returns warning message or nil.
    func checkWarnings() -> String? {
        let warnPercent = Double(limits.warnAtPercent ?? 80) / 100.0
        let today = todayString()

        if let dailyLimit = limits.dailyUsd, !hasWarnedDaily {
            let todaySpend = spendForDay(today)
            if todaySpend >= dailyLimit * warnPercent {
                hasWarnedDaily = true
                return "⚠ Approaching daily limit: $\(String(format: "%.2f", todaySpend))/$\(String(format: "%.2f", dailyLimit))"
            }
        }

        if let monthlyLimit = limits.monthlyUsd, !hasWarnedMonthly {
            let monthSpend = spendForCurrentMonth()
            if monthSpend >= monthlyLimit * warnPercent {
                hasWarnedMonthly = true
                return "⚠ Approaching monthly limit: $\(String(format: "%.2f", monthSpend))/$\(String(format: "%.2f", monthlyLimit))"
            }
        }

        if let sessionLimit = limits.perSessionUsd, !hasWarnedSession {
            if sessionSpend >= sessionLimit * warnPercent {
                hasWarnedSession = true
                return "⚠ Approaching session limit: $\(String(format: "%.2f", sessionSpend))/$\(String(format: "%.2f", sessionLimit))"
            }
        }

        return nil
    }

    // MARK: - Record Spend

    func recordSpend(cost: Double) {
        guard cost > 0 else { return }
        sessionSpend += cost

        let today = todayString()
        if let idx = log.entries.firstIndex(where: { $0.date == today }) {
            log.entries[idx].totalUsd += cost
            log.entries[idx].calls += 1
        } else {
            log.entries.append(SpendingLog.DayEntry(date: today, totalUsd: cost, calls: 1))
        }
        saveLog()
    }

    // MARK: - Stats

    var stats: String {
        let today = todayString()
        let todaySpend = spendForDay(today)
        let monthSpend = spendForCurrentMonth()
        let todayCalls = log.entries.first(where: { $0.date == today })?.calls ?? 0

        var lines = ["Spending:"]
        lines.append("  Today:   $\(String(format: "%.2f", todaySpend)) (\(todayCalls) calls)")
        lines.append("  Month:   $\(String(format: "%.2f", monthSpend))")
        lines.append("  Session: $\(String(format: "%.2f", sessionSpend))")

        if let d = limits.dailyUsd {
            let pct = d > 0 ? Int(todaySpend / d * 100) : 0
            lines.append("  Daily limit:   $\(String(format: "%.2f", d)) (\(pct)% used)")
        }
        if let m = limits.monthlyUsd {
            let pct = m > 0 ? Int(monthSpend / m * 100) : 0
            lines.append("  Monthly limit: $\(String(format: "%.2f", m)) (\(pct)% used)")
        }
        if let s = limits.perSessionUsd {
            let pct = s > 0 ? Int(sessionSpend / s * 100) : 0
            lines.append("  Session limit: $\(String(format: "%.2f", s)) (\(pct)% used)")
        }
        if limits.dailyUsd == nil && limits.monthlyUsd == nil && limits.perSessionUsd == nil {
            lines.append("  No limits set. Add \"spending_limits\" to config.json")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func spendForDay(_ day: String) -> Double {
        log.entries.first(where: { $0.date == day })?.totalUsd ?? 0
    }

    private func spendForCurrentMonth() -> Double {
        let prefix = String(todayString().prefix(7)) // "2026-03"
        return log.entries.filter { $0.date.hasPrefix(prefix) }.reduce(0) { $0 + $1.totalUsd }
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func pruneOldEntries() {
        // Keep last 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let cutoffStr = fmt.string(from: cutoff)
        log.entries.removeAll { $0.date < cutoffStr }
    }

    private func saveLog() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(log)
            try data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
        } catch {
            // Silent failure for logging
        }
    }

    private static func loadLog(path: String) -> SpendingLog {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let log = try? JSONDecoder().decode(SpendingLog.self, from: data) else {
            return SpendingLog(entries: [])
        }
        return log
    }
}
