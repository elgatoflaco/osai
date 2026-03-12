import SwiftUI
import WatchKit

struct StatusDashboardView: View {
    @EnvironmentObject var connection: AgentConnection
    @EnvironmentObject var settings: WatchSettings
    @State private var crownZoom: Double = 1.0
    @State private var isRefreshing: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Agent Status
                agentStatusCard

                // Task Gauge
                taskGaugeCard

                // System Resources
                resourcesCard

                // Last Activity
                lastActivityCard

                // Refresh Button
                refreshButton
            }
            .padding(.horizontal, 4)
            .scaleEffect(crownZoom)
            .animation(.easeInOut(duration: 0.2), value: crownZoom)
        }
        .focusable()
        .digitalCrownRotation(
            $crownZoom,
            from: 0.8,
            through: 1.4,
            by: 0.05,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: settings.hapticFeedbackEnabled
        )
        .navigationTitle("Status")
        .onAppear {
            Task { await connection.fetchStatus() }
        }
    }

    // MARK: - Agent Status Card

    private var agentStatusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: connection.agentStatus.iconName)
                .font(.title3)
                .foregroundStyle(agentStatusColor)
                .symbolEffect(.pulse, isActive: connection.agentStatus == .working)

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(connection.agentStatus.displayName)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(agentStatusColor)
            }

            Spacer()

            Circle()
                .fill(agentStatusColor)
                .frame(width: 10, height: 10)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button {
                Task {
                    await connection.sendMessage(text: "What are you currently working on?")
                }
            } label: {
                Label("Ask Status", systemImage: "questionmark.circle")
            }
        }
    }

    // MARK: - Task Gauge

    private var taskGaugeCard: some View {
        VStack(spacing: 8) {
            Text("Active Tasks")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Gauge(value: Double(min(connection.activeTasks, 10)), in: 0...10) {
                Text("Tasks")
            } currentValueLabel: {
                Text("\(connection.activeTasks)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            } minimumValueLabel: {
                Text("0")
                    .font(.caption2)
            } maximumValueLabel: {
                Text("10+")
                    .font(.caption2)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .blue, .purple]))
            .scaleEffect(1.3)
            .frame(height: 80)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button {
                Task {
                    await connection.sendMessage(text: "List my active tasks")
                }
            } label: {
                Label("List Tasks", systemImage: "list.bullet")
            }
        }
    }

    // MARK: - System Resources

    private var resourcesCard: some View {
        VStack(spacing: 8) {
            Text("System Resources")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                // CPU
                VStack(spacing: 4) {
                    Gauge(value: connection.cpuUsage, in: 0...100) {
                        Text("CPU")
                    } currentValueLabel: {
                        Text("\(Int(connection.cpuUsage))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(cpuGaugeColor)
                    .scaleEffect(0.9)

                    Text("CPU")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                // Memory
                VStack(spacing: 4) {
                    Gauge(value: connection.memoryUsage, in: 0...100) {
                        Text("MEM")
                    } currentValueLabel: {
                        Text("\(Int(connection.memoryUsage))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(memoryGaugeColor)
                    .scaleEffect(0.9)

                    Text("Memory")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Last Activity

    private var lastActivityCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Last Activity")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Text(connection.lastActivity)
                    .font(.caption2)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Refresh

    private var refreshButton: some View {
        Button {
            isRefreshing = true
            Task {
                await connection.fetchStatus()
                await MainActor.run {
                    isRefreshing = false
                    if settings.hapticFeedbackEnabled {
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
        } label: {
            HStack {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text("Refresh")
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isRefreshing)
    }

    // MARK: - Helpers

    private var agentStatusColor: Color {
        switch connection.agentStatus {
        case .idle: return .green
        case .working: return .blue
        case .error: return .red
        case .offline: return .gray
        }
    }

    private var cpuGaugeColor: Gradient {
        connection.cpuUsage > 80
            ? Gradient(colors: [.orange, .red])
            : Gradient(colors: [.green, .blue])
    }

    private var memoryGaugeColor: Gradient {
        connection.memoryUsage > 80
            ? Gradient(colors: [.orange, .red])
            : Gradient(colors: [.green, .blue])
    }
}

#Preview {
    NavigationStack {
        StatusDashboardView()
            .environmentObject(AgentConnection())
            .environmentObject(WatchSettings())
    }
}
