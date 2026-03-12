import WidgetKit
import SwiftUI

// MARK: - Agent Status Timeline Entry

struct AgentStatusEntry: TimelineEntry {
    let date: Date
    let agentStatus: AgentStatus
    let activeTasks: Int
    let lastActivity: String
    let isConnected: Bool
    let heartRate: Double
    let steps: Int
    let movePercent: Double

    static let placeholder = AgentStatusEntry(
        date: Date(),
        agentStatus: .idle,
        activeTasks: 0,
        lastActivity: "No activity",
        isConnected: true,
        heartRate: 72,
        steps: 5432,
        movePercent: 0.65
    )

    static let disconnected = AgentStatusEntry(
        date: Date(),
        agentStatus: .offline,
        activeTasks: 0,
        lastActivity: "Disconnected",
        isConnected: false,
        heartRate: 0,
        steps: 0,
        movePercent: 0
    )
}

// MARK: - Agent Status Timeline Provider

struct AgentStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentStatusEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        Task {
            let entry = await fetchCurrentEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentStatusEntry>) -> Void) {
        Task {
            let entry = await fetchCurrentEntry()
            // Refresh every 5 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchCurrentEntry() async -> AgentStatusEntry {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: "osai.server.host") ?? ""
        let port = defaults.integer(forKey: "osai.server.port")
        let effectivePort = port > 0 ? port : 8375

        guard !host.isEmpty else { return .disconnected }

        let url = URL(string: "http://\(host):\(effectivePort)/ping")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return .disconnected
            }

            if let status = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                let agentStatus: AgentStatus
                if let statusStr = status.agentStatus {
                    agentStatus = AgentStatus(rawValue: statusStr) ?? .idle
                } else {
                    agentStatus = status.status == "ok" ? .idle : .offline
                }

                return AgentStatusEntry(
                    date: Date(),
                    agentStatus: agentStatus,
                    activeTasks: status.activeTasks ?? 0,
                    lastActivity: status.lastActivity ?? "Active",
                    isConnected: true,
                    heartRate: 0,
                    steps: 0,
                    movePercent: 0
                )
            }
        } catch {
            // Connection failed
        }

        return .disconnected
    }
}

// MARK: - Agent Status Complication

struct AgentStatusComplication: Widget {
    let kind: String = "AgentStatusComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            AgentStatusComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Agent Status")
        .description("Shows the current OSAI agent status.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Task Count Complication

struct TaskCountComplication: Widget {
    let kind: String = "TaskCountComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            TaskCountComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Task Count")
        .description("Shows the number of active OSAI agent tasks.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Quick Action Complication

struct QuickActionComplication: Widget {
    let kind: String = "QuickActionComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            QuickActionComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Command")
        .description("Launches OSAI app for a quick command.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Health Status Complication

struct HealthStatusComplication: Widget {
    let kind: String = "HealthStatusComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            HealthStatusComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("OSAI Health")
        .description("Shows health metrics with OSAI agent insights.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Activity Complication

struct ActivityComplication: Widget {
    let kind: String = "ActivityComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            ActivityComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("OSAI Activity")
        .description("Shows activity progress with OSAI agent connection status.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Widget Bundle

// Note: @main removed — WidgetBundle goes in a separate Widget Extension target
struct OSAIWatchWidgets: WidgetBundle {
    var body: some Widget {
        AgentStatusComplication()
        TaskCountComplication()
        QuickActionComplication()
        HealthStatusComplication()
        ActivityComplication()
    }
}
