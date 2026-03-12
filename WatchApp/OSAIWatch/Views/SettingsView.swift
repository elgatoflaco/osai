import SwiftUI
import WatchKit

struct SettingsView: View {
    @EnvironmentObject var connection: AgentConnection
    @EnvironmentObject var settings: WatchSettings
    @EnvironmentObject var healthManager: HealthManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var crownSensitivity: Double = 0.5
    @State private var showResetConfirmation: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Server Connection
                serverSection

                // Device Info
                deviceSection

                // Notification Preferences
                notificationSection

                // Health Tracking
                healthSection

                // Location Tracking
                locationSection

                // Digital Crown
                crownSection

                // Reset
                resetSection
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Settings")
        .onAppear {
            crownSensitivity = settings.crownSensitivity
        }
    }

    // MARK: - Server Section

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Server", systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                HStack {
                    Text("Host")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(settings.serverHost.isEmpty ? "Auto (Bonjour)" : settings.serverHost)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Divider()

                HStack {
                    Text("Port")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(settings.serverPort)")
                        .font(.caption2)
                        .fontDesign(.monospaced)
                }

                Divider()

                HStack {
                    Text("Status")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 6, height: 6)
                        Text(connection.connectionState.displayName)
                            .font(.caption2)
                    }
                }

                if let lastConnected = settings.lastConnectedDate {
                    Divider()
                    HStack {
                        Text("Last Connected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastConnected, style: .relative)
                            .font(.caption2)
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            // Connection actions
            HStack(spacing: 8) {
                if connection.connectionState == .connected {
                    Button {
                        connection.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        connection.startDiscovery()
                    } label: {
                        Text("Connect")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                Button {
                    settings.serverHost = ""
                    connection.disconnect()
                    connection.startDiscovery()
                } label: {
                    Text("Auto-Find")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let error = connection.lastError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Device", systemImage: "applewatch")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                HStack {
                    Text("Device ID")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(settings.deviceId.prefix(8)) + "...")
                        .font(.system(size: 10))
                        .fontDesign(.monospaced)
                        .foregroundStyle(.primary)
                }

                Divider()

                HStack {
                    Text("Watch Name")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(WKInterfaceDevice.current().name)
                        .font(.caption2)
                        .lineLimit(1)
                }

                Divider()

                HStack {
                    Text("System")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("watchOS \(WKInterfaceDevice.current().systemVersion)")
                        .font(.caption2)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Button {
                settings.regenerateDeviceId()
                if settings.hapticFeedbackEnabled {
                    WKInterfaceDevice.current().play(.click)
                }
            } label: {
                Label("Regenerate Device ID", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications", systemImage: "bell")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $settings.notificationsEnabled) {
                Text("Push Notifications")
                    .font(.caption)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Toggle(isOn: $settings.hapticFeedbackEnabled) {
                Text("Haptic Feedback")
                    .font(.caption)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Health Section

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Health Tracking", systemImage: "heart")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { settings.healthTrackingEnabled },
                set: { newValue in
                    settings.healthTrackingEnabled = newValue
                    if newValue {
                        Task { await healthManager.requestAuthorization() }
                    } else {
                        healthManager.stopObserving()
                    }
                }
            )) {
                Text("Enable Health Data")
                    .font(.caption)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            if healthManager.isAuthorized {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text("HealthKit authorized")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Location Tracking", systemImage: "location")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { settings.locationTrackingEnabled },
                set: { newValue in
                    settings.locationTrackingEnabled = newValue
                    if newValue {
                        locationManager.requestAuthorization()
                        locationManager.startTracking()
                    } else {
                        locationManager.stopTracking()
                    }
                }
            )) {
                Text("Enable Location")
                    .font(.caption)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            if locationManager.isAuthorized {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                    Text("Location authorized")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Crown Sensitivity

    private var crownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Digital Crown", systemImage: "digitalcrown.horizontal.arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                HStack {
                    Text("Sensitivity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(sensitivityLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                }

                Slider(value: $crownSensitivity, in: 0.1...1.0, step: 0.1)
                    .tint(.blue)
                    .onChange(of: crownSensitivity) { _, newValue in
                        settings.crownSensitivity = newValue
                    }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        VStack(spacing: 8) {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset Settings", systemImage: "arrow.counterclockwise")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .confirmationDialog(
                "Reset all settings to defaults?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    settings.resetToDefaults()
                    crownSensitivity = settings.crownSensitivity
                    connection.disconnect()
                    if settings.hapticFeedbackEnabled {
                        WKInterfaceDevice.current().play(.failure)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }

            Text("v1.0.0")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private var connectionStatusColor: Color {
        switch connection.connectionState {
        case .disconnected: return .gray
        case .searching: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private var sensitivityLabel: String {
        switch crownSensitivity {
        case 0.1...0.3: return "Low"
        case 0.3...0.7: return "Medium"
        default: return "High"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AgentConnection())
            .environmentObject(WatchSettings())
            .environmentObject(HealthManager())
            .environmentObject(LocationManager())
    }
}
