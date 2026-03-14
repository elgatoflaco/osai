import SwiftUI
import WatchKit

struct ContentView: View {
    @EnvironmentObject var connection: AgentConnection
    @EnvironmentObject var settings: WatchSettings
    @State private var crownValue: Double = 0
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Connection Status
                connectionStatusBar

                // Quick Actions
                quickActionsSection

                // Recent Messages
                recentMessagesSection
            }
            .padding(.horizontal, 4)
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: Double(max(connection.messages.count - 1, 0)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: settings.hapticFeedbackEnabled
        )
        .navigationTitle("OSAI")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.caption)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Connection Status Bar

    private var connectionStatusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionDotColor)
                .frame(width: 8, height: 8)
                .overlay {
                    if connection.connectionState == .searching {
                        Circle()
                            .stroke(connectionDotColor.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.6)
                    }
                }

            Text(connection.connectionState.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            if connection.connectionState == .connected {
                Text(connection.agentStatus.displayName)
                    .font(.caption2)
                    .foregroundStyle(agentStatusColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if connection.connectionState != .connected {
                connection.startDiscovery()
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            NavigationLink {
                CommandView()
            } label: {
                Label("Voice Command", systemImage: "mic.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            NavigationLink {
                StatusDashboardView()
            } label: {
                Label("Status Check", systemImage: "chart.bar.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            NavigationLink {
                HealthDashboardView()
            } label: {
                Label("Health", systemImage: "heart.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            NavigationLink {
                LocationView()
            } label: {
                Label("Location", systemImage: "location.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
    }

    // MARK: - Recent Messages

    private var recentMessagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !connection.messages.isEmpty {
                    Button("Clear") {
                        connection.clearMessages()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if connection.messages.isEmpty {
                Text("No messages yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(connection.messages.suffix(10).reversed()) { message in
                    MessageRow(message: message)
                        .contextMenu {
                            Button {
                                // Re-send this message
                                Task { await connection.sendMessage(text: message.text) }
                            } label: {
                                Label("Resend", systemImage: "arrow.clockwise")
                            }

                            Button(role: .destructive) {
                                if let index = connection.messages.firstIndex(where: { $0.id == message.id }) {
                                    connection.messages.remove(at: index)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Helpers

    private var connectionDotColor: Color {
        switch connection.connectionState {
        case .disconnected: return .gray
        case .searching: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private var agentStatusColor: Color {
        switch connection.agentStatus {
        case .idle: return .green
        case .working: return .blue
        case .error: return .red
        case .offline: return .gray
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: WatchMessage
    @State private var expanded = false

    var body: some View {
        VStack(alignment: message.isFromAgent ? .leading : .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if message.isFromAgent {
                    Image(systemName: "cpu")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                }

                Text(message.relativeTime)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                if !message.isFromAgent {
                    Image(systemName: "person.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                }
            }

            Text(message.text)
                .font(.caption2)
                .lineLimit(expanded ? nil : 4)
                .multilineTextAlignment(message.isFromAgent ? .leading : .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    message.isFromAgent
                        ? Color.blue.opacity(0.2)
                        : Color.green.opacity(0.2),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: message.isFromAgent ? .leading : .trailing)
    }
}

#Preview {
    NavigationStack {
        ContentView()
            .environmentObject(AgentConnection())
            .environmentObject(WatchSettings())
            .environmentObject(HealthManager())
            .environmentObject(LocationManager())
    }
}
