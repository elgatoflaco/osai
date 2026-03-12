import Foundation
import SwiftUI
import Combine

final class WatchSettings: ObservableObject {
    private enum Keys {
        static let serverHost = "osai.server.host"
        static let serverPort = "osai.server.port"
        static let deviceId = "osai.device.id"
        static let healthTrackingEnabled = "osai.health.enabled"
        static let locationTrackingEnabled = "osai.location.enabled"
        static let notificationsEnabled = "osai.notifications.enabled"
        static let hapticFeedbackEnabled = "osai.haptic.enabled"
        static let lastConnectedDate = "osai.last.connected"
        static let crownSensitivity = "osai.crown.sensitivity"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Published Properties

    @Published var serverHost: String {
        didSet { defaults.set(serverHost, forKey: Keys.serverHost) }
    }

    @Published var serverPort: Int {
        didSet { defaults.set(serverPort, forKey: Keys.serverPort) }
    }

    @Published var deviceId: String {
        didSet { defaults.set(deviceId, forKey: Keys.deviceId) }
    }

    @Published var healthTrackingEnabled: Bool {
        didSet { defaults.set(healthTrackingEnabled, forKey: Keys.healthTrackingEnabled) }
    }

    @Published var locationTrackingEnabled: Bool {
        didSet { defaults.set(locationTrackingEnabled, forKey: Keys.locationTrackingEnabled) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published var hapticFeedbackEnabled: Bool {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: Keys.hapticFeedbackEnabled) }
    }

    @Published var lastConnectedDate: Date? {
        didSet {
            if let date = lastConnectedDate {
                defaults.set(date, forKey: Keys.lastConnectedDate)
            } else {
                defaults.removeObject(forKey: Keys.lastConnectedDate)
            }
        }
    }

    @Published var crownSensitivity: Double {
        didSet { defaults.set(crownSensitivity, forKey: Keys.crownSensitivity) }
    }

    // MARK: - Initialization

    init() {
        self.serverHost = defaults.string(forKey: Keys.serverHost) ?? ""
        let storedPort = defaults.integer(forKey: Keys.serverPort)
        self.serverPort = storedPort != 0 ? storedPort : 8375

        if let storedId = defaults.string(forKey: Keys.deviceId), !storedId.isEmpty {
            self.deviceId = storedId
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: Keys.deviceId)
            self.deviceId = newId
        }

        self.healthTrackingEnabled = defaults.object(forKey: Keys.healthTrackingEnabled) as? Bool ?? false
        self.locationTrackingEnabled = defaults.object(forKey: Keys.locationTrackingEnabled) as? Bool ?? false
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.hapticFeedbackEnabled = defaults.object(forKey: Keys.hapticFeedbackEnabled) as? Bool ?? true
        self.lastConnectedDate = defaults.object(forKey: Keys.lastConnectedDate) as? Date
        self.crownSensitivity = defaults.object(forKey: Keys.crownSensitivity) as? Double ?? 0.5
    }

    // MARK: - Computed Properties

    var baseURL: String {
        let host = serverHost.isEmpty ? "localhost" : serverHost
        return "http://\(host):\(serverPort)"
    }

    var formattedLastConnected: String {
        guard let date = lastConnectedDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Reset

    func resetToDefaults() {
        serverHost = ""
        serverPort = 8375
        healthTrackingEnabled = false
        locationTrackingEnabled = false
        notificationsEnabled = true
        hapticFeedbackEnabled = true
        crownSensitivity = 0.5
    }

    func regenerateDeviceId() {
        deviceId = UUID().uuidString
    }
}
