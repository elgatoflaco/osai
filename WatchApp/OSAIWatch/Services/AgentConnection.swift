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

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
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
            // Strip interface scope ID if present (e.g. "%en8")
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
                    self?.lastError = "Bonjour search failed: \(error)"
                    self?.scheduleReconnect()
                }
            default:
                break
            }
        }

        nwBrowser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            for result in results {
                if case .service(let name, let type, let domain, _) = result.endpoint {
                    // Resolve the endpoint by connecting to it
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
                                // Strip interface scope ID (e.g. "%en8") from resolved address
                                if let percentIndex = hostStr.firstIndex(of: "%") {
                                    hostStr = String(hostStr[hostStr.startIndex..<percentIndex])
                                }
                                let portValue = Int(port.rawValue)
                                Task { @MainActor [weak self] in
                                    self?.discoveredHost = hostStr
                                    self?.discoveredPort = portValue
                                    self?.settings?.serverHost = hostStr
                                    self?.settings?.serverPort = portValue
                                }
                                Task { [weak self] in await self?.verifyConnection() }
                            }
                            connection.cancel()
                        }
                    }
                    connection.start(queue: .global())
                    break // Take first found service
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
    }

    private func verifyConnection() async {
        guard let url = makeURL(path: "/ping") else {
            await MainActor.run { connectionState = .error; lastError = "No host configured" }
            return
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run { connectionState = .error; lastError = "Server returned error" }
                scheduleReconnect()
                return
            }

            if let json = try? JSONDecoder().decode(StatusResponse.self, from: data), json.status == "ok" {
                await MainActor.run {
                    connectionState = .connected
                    lastError = nil
                    settings?.lastConnectedDate = Date()
                }
                startPolling()
                startStatusUpdates()
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
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                self?.startDiscovery()
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        Task { @MainActor in
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { await self?.pollResponses() }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startStatusUpdates() {
        Task { @MainActor in
            statusTimer?.invalidate()
            statusTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { await self?.fetchStatus() }
            }
        }
        Task { await fetchStatus() }
    }

    private func stopStatusUpdates() {
        statusTimer?.invalidate()
        statusTimer = nil
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run { lastError = "Server error: \(statusCode)" }
                return
            }
            await MainActor.run { lastError = nil }
        } catch {
            await MainActor.run { lastError = "Send failed: \(error.localizedDescription)" }
            handleConnectionLoss()
        }
    }

    func pollResponses() async {
        guard let settings = settings,
              let url = makeURL(path: "/poll"),
              connectionState == .connected else { return }
        let payload: [String: Any] = ["device_id": settings.deviceId]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

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
            handleConnectionLoss()
        }
    }

    func fetchStatus() async {
        guard let url = makeURL(path: "/ping"),
              connectionState == .connected else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

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
            handleConnectionLoss()
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

    /// Sanitize host by stripping interface scope ID (e.g. "%en8") and build URL
    private func makeURL(path: String) -> URL? {
        guard var host = discoveredHost, let port = discoveredPort else { return nil }
        // Strip interface scope ID from resolved addresses
        if let percentIndex = host.firstIndex(of: "%") {
            host = String(host[host.startIndex..<percentIndex])
        }
        return URL(string: "http://\(host):\(port)\(path)")
    }

    // MARK: - Helpers

    private func trimMessages() {
        if messages.count > maxMessages {
            messages = Array(messages.suffix(maxMessages))
        }
    }

    private func handleConnectionLoss() {
        Task { @MainActor in
            if connectionState == .connected {
                connectionState = .error
                agentStatus = .offline
                lastError = "Connection lost"
                stopPolling()
                stopStatusUpdates()
                scheduleReconnect()
            }
        }
    }

    func clearMessages() {
        messages.removeAll()
    }
}
