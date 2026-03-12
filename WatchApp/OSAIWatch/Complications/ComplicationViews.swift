import SwiftUI
import WidgetKit

// MARK: - Agent Status Complication Views

struct AgentStatusComplicationView: View {
    let entry: AgentStatusEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        @unknown default:
            circularView
        }
    }

    // MARK: - Circular

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 1) {
                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .widgetAccentable()

                Circle()
                    .fill(statusWidgetColor)
                    .frame(width: 4, height: 4)
            }
        }
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.caption2)
                        .widgetAccentable()

                    Text("OSAI")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }

                Text(entry.agentStatus.displayName)
                    .font(.caption)
                    .widgetAccentable()

                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 8))

                    Text("\(entry.activeTasks) tasks")
                        .font(.system(size: 10))

                    if !entry.lastActivity.isEmpty && entry.lastActivity != "No activity" {
                        Text("| \(entry.lastActivity)")
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack {
                Circle()
                    .fill(statusWidgetColor)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Corner

    private var cornerView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: statusIcon)
                .font(.title3)
                .widgetAccentable()
        }
        .widgetLabel {
            Text(entry.agentStatus.displayName)
        }
    }

    // MARK: - Inline

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text("OSAI: \(entry.agentStatus.displayName)")
            if entry.activeTasks > 0 {
                Text("(\(entry.activeTasks))")
            }
        }
    }

    // MARK: - Helpers

    private var statusIcon: String {
        if !entry.isConnected { return "wifi.slash" }
        return entry.agentStatus.iconName
    }

    private var statusWidgetColor: Color {
        if !entry.isConnected { return .gray }
        switch entry.agentStatus {
        case .idle: return .green
        case .working: return .blue
        case .error: return .red
        case .offline: return .gray
        }
    }
}

// MARK: - Task Count Complication Views

struct TaskCountComplicationView: View {
    let entry: AgentStatusEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularTaskView
        case .accessoryRectangular:
            rectangularTaskView
        case .accessoryCorner:
            cornerTaskView
        case .accessoryInline:
            inlineTaskView
        @unknown default:
            circularTaskView
        }
    }

    // MARK: - Circular

    private var circularTaskView: some View {
        Gauge(value: Double(min(entry.activeTasks, 10)), in: 0...10) {
            Image(systemName: "checklist")
        } currentValueLabel: {
            Text("\(entry.activeTasks)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    // MARK: - Rectangular

    private var rectangularTaskView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.caption2)
                    .widgetAccentable()

                Text("OSAI Tasks")
                    .font(.caption2)
                    .fontWeight(.semibold)

                Spacer()

                if entry.isConnected {
                    Circle()
                        .fill(.green)
                        .frame(width: 4, height: 4)
                }
            }

            Text("\(entry.activeTasks)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .widgetAccentable()

            Gauge(value: Double(min(entry.activeTasks, 10)), in: 0...10) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(Gradient(colors: [.blue, .purple]))
        }
    }

    // MARK: - Corner

    private var cornerTaskView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Text("\(entry.activeTasks)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .widgetAccentable()
        }
        .widgetLabel {
            Gauge(value: Double(min(entry.activeTasks, 10)), in: 0...10) {
                Text("Tasks")
            }
            .gaugeStyle(.accessoryLinear)
        }
    }

    // MARK: - Inline

    private var inlineTaskView: some View {
        HStack(spacing: 4) {
            Image(systemName: "checklist")
            Text("OSAI: \(entry.activeTasks) tasks")
        }
    }
}

// MARK: - Quick Action Complication Views

struct QuickActionComplicationView: View {
    let entry: AgentStatusEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularActionView
        case .accessoryRectangular:
            rectangularActionView
        case .accessoryCorner:
            cornerActionView
        case .accessoryInline:
            inlineActionView
        @unknown default:
            circularActionView
        }
    }

    // MARK: - Circular

    private var circularActionView: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                    .widgetAccentable()

                Text("OSAI")
                    .font(.system(size: 7, weight: .bold))
            }
        }
    }

    // MARK: - Rectangular

    private var rectangularActionView: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.circle.fill")
                .font(.title2)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 2) {
                Text("OSAI Command")
                    .font(.caption2)
                    .fontWeight(.semibold)

                Text("Tap to speak")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                if entry.isConnected {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(.green)
                            .frame(width: 4, height: 4)
                        Text("Connected")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(.gray)
                            .frame(width: 4, height: 4)
                        Text("Offline")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Corner

    private var cornerActionView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: "mic.fill")
                .font(.title3)
                .widgetAccentable()
        }
        .widgetLabel {
            Text("OSAI Command")
        }
    }

    // MARK: - Inline

    private var inlineActionView: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
            Text(entry.isConnected ? "OSAI Ready" : "OSAI Offline")
        }
    }
}

// MARK: - Health Status Complication Views

struct HealthStatusComplicationView: View {
    let entry: AgentStatusEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularHealthView
        case .accessoryRectangular:
            rectangularHealthView
        case .accessoryCorner:
            cornerHealthView
        case .accessoryInline:
            inlineHealthView
        @unknown default:
            circularHealthView
        }
    }

    private var circularHealthView: some View {
        ZStack {
            if entry.heartRate > 0 {
                Gauge(value: min(entry.heartRate, 200), in: 40...200) {
                    Image(systemName: "heart.fill")
                } currentValueLabel: {
                    Text("\(Int(entry.heartRate))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.pink, .red]))
            } else {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .widgetAccentable()
                    Text("--")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var rectangularHealthView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .widgetAccentable()

                Text("OSAI Health")
                    .font(.caption2)
                    .fontWeight(.semibold)

                Spacer()

                if entry.isConnected {
                    Circle()
                        .fill(.green)
                        .frame(width: 4, height: 4)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                if entry.heartRate > 0 {
                    Text("\(Int(entry.heartRate))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("BPM")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                } else {
                    Text("-- BPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 2) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 7))
                        Text("\(entry.steps)")
                            .font(.system(size: 9, design: .rounded))
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cornerHealthView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: "heart.fill")
                .font(.title3)
                .widgetAccentable()
        }
        .widgetLabel {
            if entry.heartRate > 0 {
                Text("\(Int(entry.heartRate)) BPM")
            } else {
                Text("OSAI Health")
            }
        }
    }

    private var inlineHealthView: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
            if entry.heartRate > 0 {
                Text("\(Int(entry.heartRate)) BPM | \(entry.steps) steps")
            } else {
                Text("OSAI Health")
            }
        }
    }
}

// MARK: - Activity Complication Views

struct ActivityComplicationView: View {
    let entry: AgentStatusEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularActivityView
        case .accessoryRectangular:
            rectangularActivityView
        case .accessoryCorner:
            cornerActivityView
        case .accessoryInline:
            inlineActivityView
        @unknown default:
            circularActivityView
        }
    }

    private var circularActivityView: some View {
        Gauge(value: min(entry.movePercent, 1.0)) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(Int(entry.movePercent * 100))")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.orange, .red]))
    }

    private var rectangularActivityView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .widgetAccentable()

                Text("OSAI Activity")
                    .font(.caption2)
                    .fontWeight(.semibold)

                Spacer()

                if entry.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(entry.steps)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("steps")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(entry.movePercent * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("move")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }

            Gauge(value: min(entry.movePercent, 1.0)) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(Gradient(colors: [.orange, .red]))
        }
    }

    private var cornerActivityView: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: "flame.fill")
                .font(.title3)
                .widgetAccentable()
        }
        .widgetLabel {
            Gauge(value: min(entry.movePercent, 1.0)) {
                Text("Move")
            }
            .gaugeStyle(.accessoryLinear)
            .tint(.red)
        }
    }

    private var inlineActivityView: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
            Text("\(entry.steps) steps | \(Int(entry.movePercent * 100))% move")
        }
    }
}

// MARK: - Previews

#Preview("Agent Status Circular", as: .accessoryCircular) {
    AgentStatusComplication()
} timeline: {
    AgentStatusEntry.placeholder
    AgentStatusEntry(date: Date(), agentStatus: .working, activeTasks: 3, lastActivity: "Processing query", isConnected: true, heartRate: 0, steps: 0, movePercent: 0)
    AgentStatusEntry.disconnected
}

#Preview("Task Count Rectangular", as: .accessoryRectangular) {
    TaskCountComplication()
} timeline: {
    AgentStatusEntry.placeholder
    AgentStatusEntry(date: Date(), agentStatus: .working, activeTasks: 5, lastActivity: "Active", isConnected: true, heartRate: 0, steps: 0, movePercent: 0)
}

#Preview("Health Status Circular", as: .accessoryCircular) {
    HealthStatusComplication()
} timeline: {
    AgentStatusEntry.placeholder
}

#Preview("Activity Rectangular", as: .accessoryRectangular) {
    ActivityComplication()
} timeline: {
    AgentStatusEntry.placeholder
}

#Preview("Quick Action Circular", as: .accessoryCircular) {
    QuickActionComplication()
} timeline: {
    AgentStatusEntry.placeholder
}
