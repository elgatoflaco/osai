import Foundation
import SwiftUI
import Combine
import Network
import WatchKit

final class AgentConnection: ObservableObject, @unchecked Sendable {
    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published var messages: [WatchMessage] = []
    @Published var agentStatus: AgentStatus = .offline
    @Published var activeTasks: Int = 0
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var lastActivity: String = "N/A"
    @Published var lastError: String?

    // MARK: - Private

    private var settings: WatchSettings?
    private var nwBrowser: NWBrowser?
    private var discoveredHost: String?
    private var discoveredPort: Int?
    private var pollTimer: Timer?
    private var statusTimer: Timer?
    private var reconnectTimer: Timer?
    private var session: URLSession
    private let maxMessages = 50

    // Connection stability
    private var consecutiveFailures = 0
    private let maxToleratedFailures = 5
    private var isPollInFlight = false
    private var isStatusInFlight = false
    private var reconnectAttempts = 0

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true  // Essential for watchOS — network goes through iPhone
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Configuration

    func configure(settings: WatchSettings) {
        self.settings = settings
    }

    // MARK: - Connection Lifecycle

    func startDiscovery() {
        guard connectionState != .connected else { return }
        connectionState = .searching
        lastError = nil

        // If we have a manual host, try direct connection first
        if let settings = settings, !settings.serverHost.isEmpty {
            var host = settings.serverHost
            if let percentIndex = host.firstIndex(of: "%") {
                host = String(host[host.startIndex..<percentIndex])
                settings.serverHost = host
            }
            discoveredHost = host
            discoveredPort = settings.serverPort
            Task { await verifyConnection() }
            return
        }

        // Use NWBrowser for Bonjour discovery (watchOS compatible)
        let params = NWParameters()
        params.includePeerToPeer = true
        nwBrowser = NWBrowser(for: .bonjour(type: "_osai._tcp", domain: "local."), using: params)

        nwBrowser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                Task { @MainActor in
                    self?.connectionState = .error
                    self?.lastError = "Bonjour failed: \(error.localizedDescription)"
                    self?.scheduleReconnect()
                }
            default:
                break
            }
        }

        nwBrowser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            for result in results {
                if case .service(_, _, _, _) = result.endpoint {
                    let connection = NWConnection(to: result.endpoint, using: .tcp)
                    connection.stateUpdateHandler = { @Sendable [weak self] state in
                        if case .ready = state {
                            if let path = connection.currentPath,
                               let endpoint = path.remoteEndpoint,
                               case .hostPort(let host, let port) = endpoint {
                                var hostStr: String
                                switch host {
                                case .ipv4(let addr): hostStr = "\(addr)"
                                case .ipv6(let addr): hostStr = "\(addr)"
                                case .name(let name, _): hostStr = name
                                @unknown default: hostStr = "localhost"
                                }
                                if let percentIndex = hostStr.firstIndex(of: "%") {
                                    hostStr = String(hostStr[hostStr.startIndex..<percentIndex])
                                }
                                let portValue = Int(port.rawValue)
                                // Set host/port and verify in the SAME task to avoid race condition
                                Task { @MainActor [weak self] in
                                    guard let self = self else { return }
                                    self.discoveredHost = hostStr
                                    self.discoveredPort = portValue
                                    await self.verifyConnection()
                                }
                            }
                            connection.cancel()
                        }
                    }
                    connection.start(queue: .global())
                    break
                }
            }
        }

        nwBrowser?.start(queue: .global())
    }

    func disconnect() {
        stopPolling()
        stopStatusUpdates()
        nwBrowser?.cancel()
        nwBrowser = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        discoveredHost = nil
        discoveredPort = nil
        connectionState = .disconnected
        agentStatus = .offline
        consecutiveFailures = 0
        reconnectAttempts = 0
    }

    func connectManual(host: String, port: Int) {
        connectionState = .searching
        discoveredHost = host
        discoveredPort = port
        consecutiveFailures = 0
        Task { await verifyConnection() }
    }

    private func verifyConnection() async {
        guard let url = makeURL(path: "/ping") else {
            await MainActor.run { connectionState = .error; lastError = "No host configured" }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run { connectionState = .error; lastError = "Server error" }
                scheduleReconnect()
                return
            }

            if let json = try? JSONDecoder().decode(StatusResponse.self, from: data), json.status == "ok" {
                await MainActor.run {
                    connectionState = .connected
                    lastError = nil
                    consecutiveFailures = 0
                    reconnectAttempts = 0
                    settings?.lastConnectedDate = Date()
                    // Start timers on MainActor directly to ensure they schedule on the right RunLoop
                    self.pollTimer?.invalidate()
                    self.pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                        Task { await self?.pollResponses() }
                    }
                    self.statusTimer?.invalidate()
                    self.statusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                        Task { await self?.fetchStatus() }
                    }
                }
                // Also do an immediate fetch
                await fetchStatus()
            } else {
                await MainActor.run { connectionState = .error; lastError = "Invalid ping response" }
                scheduleReconnect()
            }
        } catch {
            await MainActor.run { connectionState = .error; lastError = error.localizedDescription }
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        Task { @MainActor in
            reconnectTimer?.invalidate()
            reconnectAttempts += 1
            if connectionState == .error {
                connectionState = .searching
            }
            let delay = min(3.0 * pow(2.0, Double(min(reconnectAttempts, 3))), 15.0)
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                // After 3 failed reconnects, clear discovered IP and redo Bonjour
                if self.reconnectAttempts > 3 {
                    self.discoveredHost = nil
                    self.discoveredPort = nil
                    self.nwBrowser?.cancel()
                    self.nwBrowser = nil
                    self.reconnectAttempts = 0
                }
                if let host = self.discoveredHost, let port = self.discoveredPort {
                    self.connectManual(host: host, port: port)
                } else {
                    self.startDiscovery()
                }
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        Task { @MainActor in
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { await self?.pollResponses() }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPollInFlight = false
    }

    private func startStatusUpdates() {
        Task { @MainActor in
            statusTimer?.invalidate()
            statusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { await self?.fetchStatus() }
            }
        }
        Task { await fetchStatus() }
    }

    private func stopStatusUpdates() {
        statusTimer?.invalidate()
        statusTimer = nil
        isStatusInFlight = false
    }

    // MARK: - API Methods

    func sendMessage(text: String) async {
        guard let settings = settings else { return }
        guard connectionState == .connected else {
            await MainActor.run { lastError = "Not connected" }
            return
        }

        let userMessage = WatchMessage(text: text, isFromAgent: false)
        await MainActor.run {
            messages.append(userMessage)
            trimMessages()
        }

        guard let url = makeURL(path: "/message") else { return }

        let payload: [String: Any] = [
            "device_id": settings.deviceId,
            "user_name": "Watch User",
            "text": text
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let respBody = String(data: data, encoding: .utf8) ?? ""
                await MainActor.run { lastError = "Error \(statusCode): \(respBody)" }
                return
            }
            await MainActor.run { lastError = nil; consecutiveFailures = 0 }
            // Immediately poll for response after sending
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await pollResponses()
        } catch {
            await MainActor.run { lastError = "Send: \(error.localizedDescription)" }
            recordFailure()
        }
    }

    func pollResponses() async {
        guard !isPollInFlight else { return }
        guard let settings = settings,
              let url = makeURL(path: "/poll"),
              connectionState == .connected else { return }

        isPollInFlight = true
        defer { isPollInFlight = false }

        let payload: [String: Any] = ["device_id": settings.deviceId]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            await MainActor.run { consecutiveFailures = 0 }

            if let pollResponse = try? JSONDecoder().decode(PollResponse.self, from: data) {
                let newMessages = pollResponse.messages.map { msg in
                    WatchMessage(text: msg.text, isFromAgent: true)
                }
                if !newMessages.isEmpty {
                    await MainActor.run {
                        messages.append(contentsOf: newMessages)
                        trimMessages()
                        if settings.hapticFeedbackEnabled {
                            WKInterfaceDevice.current().play(.notification)
                        }
                    }
                }
            }
        } catch {
            recordFailure()
        }
    }

    func fetchStatus() async {
        guard !isStatusInFlight else { return }
        guard let url = makeURL(path: "/ping"),
              connectionState == .connected else { return }

        isStatusInFlight = true
        defer { isStatusInFlight = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            await MainActor.run { consecutiveFailures = 0 }

            if let status = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                await MainActor.run {
                    if let tasks = status.activeTasks { activeTasks = tasks }
                    if let cpu = status.cpuUsage { cpuUsage = cpu }
                    if let mem = status.memoryUsage { memoryUsage = mem }
                    if let activity = status.lastActivity { lastActivity = activity }
                    if let agentStr = status.agentStatus, let parsed = AgentStatus(rawValue: agentStr) {
                        agentStatus = parsed
                    } else if status.status == "ok" {
                        agentStatus = .idle
                    }
                }
            }
        } catch {
            recordFailure()
        }
    }

    func sendHealthData(data: HealthSnapshot) async {
        let summary = data.summary
        await sendMessage(text: "[Health Update]\n\(summary)")
    }

    func sendLocation(latitude: Double, longitude: Double) async {
        await sendMessage(text: "[Location Update] Lat: \(latitude), Lon: \(longitude)")
    }

    // MARK: - URL Helpers

    private func makeURL(path: String) -> URL? {
        guard var host = discoveredHost, let port = discoveredPort else { return nil }
        if let percentIndex = host.firstIndex(of: "%") {
            host = String(host[host.startIndex..<percentIndex])
        }
        if host.contains(":") {
            return URL(string: "http://[\(host)]:\(port)\(path)")
        }
        return URL(string: "http://\(host):\(port)\(path)")
    }

    // MARK: - Helpers

    private func trimMessages() {
        if messages.count > maxMessages {
            messages = Array(messages.suffix(maxMessages))
        }
    }

    private func recordFailure() {
        Task { @MainActor in
            guard connectionState == .connected else { return }
            consecutiveFailures += 1
            if consecutiveFailures >= maxToleratedFailures {
                connectionState = .error
                agentStatus = .offline
                lastError = "Connection lost"
                stopPolling()
                stopStatusUpdates()
                consecutiveFailures = 0
                scheduleReconnect()
            }
        }
    }

    func clearMessages() {
        messages.removeAll()
    }
}
