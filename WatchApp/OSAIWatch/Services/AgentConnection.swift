import Foundation
import SwiftUI
import Combine

final class AgentConnection: NSObject, ObservableObject {
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
    private var browser: NetServiceBrowser?
    private var resolvedService: NetService?
    private var discoveredHost: String?
    private var discoveredPort: Int?
    private var pollTimer: Timer?
    private var statusTimer: Timer?
    private var reconnectTimer: Timer?
    private var session: URLSession
    private let maxMessages = 50

    // MARK: - Init

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        super.init()
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
            discoveredHost = settings.serverHost
            discoveredPort = settings.serverPort
            Task { await verifyConnection() }
            return
        }

        // Otherwise use Bonjour discovery
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_osai._tcp.", inDomain: "local.")
    }

    func disconnect() {
        stopPolling()
        stopStatusUpdates()
        browser?.stop()
        browser = nil
        resolvedService?.stop()
        resolvedService = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        discoveredHost = nil
        discoveredPort = nil
        connectionState = .disconnected
        agentStatus = .offline
    }

    private func verifyConnection() async {
        guard let host = discoveredHost, let port = discoveredPort else {
            await MainActor.run { connectionState = .error; lastError = "No host configured" }
            return
        }

        let url = URL(string: "http://\(host):\(port)/ping")!
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
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.startDiscovery()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { await self?.pollResponses() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startStatusUpdates() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { await self?.fetchStatus() }
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

        guard let host = discoveredHost, let port = discoveredPort else { return }
        let url = URL(string: "http://\(host):\(port)/message")!

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
            let (data, response) = try await session.data(for: request)
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
              let host = discoveredHost,
              let port = discoveredPort,
              connectionState == .connected else { return }

        let url = URL(string: "http://\(host):\(port)/poll")!
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
        guard let host = discoveredHost, let port = discoveredPort,
              connectionState == .connected else { return }

        let url = URL(string: "http://\(host):\(port)/ping")!

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

// MARK: - NetServiceBrowserDelegate

extension AgentConnection: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        resolvedService = service
        service.delegate = self
        service.resolve(withTimeout: 10)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor in
            connectionState = .error
            lastError = "Bonjour search failed"
            scheduleReconnect()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if service == resolvedService {
            handleConnectionLoss()
        }
    }
}

// MARK: - NetServiceDelegate

extension AgentConnection: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else {
            Task { @MainActor in
                connectionState = .error
                lastError = "Could not resolve host"
            }
            return
        }

        discoveredHost = hostName
        discoveredPort = sender.port
        settings?.serverHost = hostName
        settings?.serverPort = sender.port

        Task { await verifyConnection() }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor in
            connectionState = .error
            lastError = "Service resolution failed"
            scheduleReconnect()
        }
    }
}
