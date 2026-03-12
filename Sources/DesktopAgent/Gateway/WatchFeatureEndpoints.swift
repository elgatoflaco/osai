import Foundation

/// Handles advanced Watch feature endpoints beyond basic messaging.
/// Called by WatchGatewayAdapter when it receives requests on feature paths.
final class WatchFeatureEndpoints {

    // In-memory state
    private var geofences: [String: GeofenceDefinition] = [:]  // name → definition
    private var activeGeofenceAlerts: [GeofenceAlert] = []
    private let lock = NSLock()

    struct GeofenceDefinition: Codable {
        let name: String
        let latitude: Double
        let longitude: Double
        let radius: Double  // meters
        let action: String  // agent command to run on trigger
        var isActive: Bool
    }

    struct GeofenceAlert: Codable {
        let geofenceName: String
        let eventType: String  // "enter" or "exit"
        let timestamp: Date
        let latitude: Double
        let longitude: Double
    }

    struct AgentStatusResponse: Codable {
        let status: String       // "idle", "working", "error"
        let activeTasks: Int
        let lastActivity: String // ISO8601 timestamp
        let uptime: Int          // seconds
        let version: String
    }

    struct HealthCommandResponse: Codable {
        let status: String
        let message: String
    }

    private let startTime = Date()
    private var lastActivityTime = Date()
    private var activeTasks = 0
    private var currentStatus = "idle"

    /// Route a request to the appropriate handler. Returns (statusCode, responseJSON).
    func handleRequest(method: String, path: String, body: String?, deviceId: String?) -> (Int, String) {
        // Update last activity
        lastActivityTime = Date()

        switch (method, path) {
        case ("GET", "/status"):
            return handleStatus()

        case ("POST", "/health"):
            return handleHealthData(body: body, deviceId: deviceId)

        case ("POST", "/location"):
            return handleLocation(body: body, deviceId: deviceId)

        case ("GET", "/geofences"):
            return handleListGeofences()

        case ("POST", "/geofence"):
            return handleAddGeofence(body: body)

        case ("DELETE", "/geofence"):
            return handleRemoveGeofence(body: body)

        case ("POST", "/geofence/trigger"):
            return handleGeofenceTrigger(body: body, deviceId: deviceId)

        case ("POST", "/shortcut"):
            return handleShortcut(body: body, deviceId: deviceId)

        case ("GET", "/complications"):
            return handleComplicationData()

        default:
            return (404, "{\"error\":\"unknown feature endpoint\"}")
        }
    }

    // MARK: - Status

    func updateStatus(_ status: String, taskCount: Int) {
        currentStatus = status
        activeTasks = taskCount
        lastActivityTime = Date()
    }

    private func handleStatus() -> (Int, String) {
        let uptime = Int(Date().timeIntervalSince(startTime))
        let formatter = ISO8601DateFormatter()
        let response = AgentStatusResponse(
            status: currentStatus,
            activeTasks: activeTasks,
            lastActivity: formatter.string(from: lastActivityTime),
            uptime: uptime,
            version: "1.0"
        )
        if let data = try? JSONEncoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            return (200, json)
        }
        return (500, "{\"error\":\"encoding failed\"}")
    }

    // MARK: - Health Data

    private func handleHealthData(body: String?, deviceId: String?) -> (Int, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (400, "{\"error\":\"invalid health data\"}")
        }

        // Store health snapshot for agent context
        // The agent can use this data when asked about user health
        let heartRate = json["heart_rate"] as? Double
        let steps = json["steps"] as? Int
        let movePercent = json["move_percent"] as? Double
        let exercisePercent = json["exercise_percent"] as? Double
        let standPercent = json["stand_percent"] as? Double

        // Build a human-readable summary for the agent
        var parts: [String] = []
        if let hr = heartRate { parts.append("Heart rate: \(Int(hr)) BPM") }
        if let s = steps { parts.append("Steps: \(s)") }
        if let m = movePercent { parts.append("Move: \(Int(m * 100))%") }
        if let e = exercisePercent { parts.append("Exercise: \(Int(e * 100))%") }
        if let s = standPercent { parts.append("Stand: \(Int(s * 100))%") }

        let summary = parts.isEmpty ? "No health data" : parts.joined(separator: ", ")

        // Store for later retrieval by agent
        lock.lock()
        UserDefaults.standard.set(summary, forKey: "watch_health_\(deviceId ?? "unknown")")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "watch_health_time_\(deviceId ?? "unknown")")
        lock.unlock()

        return (200, "{\"status\":\"received\",\"message\":\"Health data stored\"}")
    }

    // MARK: - Location

    private func handleLocation(body: String?, deviceId: String?) -> (Int, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let latitude = json["latitude"] as? Double,
              let longitude = json["longitude"] as? Double else {
            return (400, "{\"error\":\"invalid location data\"}")
        }

        let accuracy = json["accuracy"] as? Double ?? -1

        // Store location for agent context
        lock.lock()
        let locationStr = String(format: "%.6f,%.6f (±%.0fm)", latitude, longitude, accuracy)
        UserDefaults.standard.set(locationStr, forKey: "watch_location_\(deviceId ?? "unknown")")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "watch_location_time_\(deviceId ?? "unknown")")
        lock.unlock()

        // Check geofences
        var triggered: [String] = []
        lock.lock()
        for (name, fence) in geofences where fence.isActive {
            let distance = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: fence.latitude, lon2: fence.longitude
            )
            if distance <= fence.radius {
                triggered.append(name)
            }
        }
        lock.unlock()

        let response: [String: Any] = [
            "status": "received",
            "triggered_geofences": triggered
        ]
        if let responseData = try? JSONSerialization.data(withJSONObject: response),
           let responseStr = String(data: responseData, encoding: .utf8) {
            return (200, responseStr)
        }
        return (200, "{\"status\":\"received\",\"triggered_geofences\":[]}")
    }

    // MARK: - Geofences

    private func handleListGeofences() -> (Int, String) {
        lock.lock()
        let fences = Array(geofences.values)
        lock.unlock()

        if let data = try? JSONEncoder().encode(["geofences": fences]),
           let json = String(data: data, encoding: .utf8) {
            return (200, json)
        }
        return (200, "{\"geofences\":[]}")
    }

    private func handleAddGeofence(body: String?) -> (Int, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let fence = try? JSONDecoder().decode(GeofenceDefinition.self, from: data) else {
            return (400, "{\"error\":\"invalid geofence definition\"}")
        }

        lock.lock()
        geofences[fence.name] = fence
        lock.unlock()

        return (200, "{\"status\":\"added\",\"name\":\"\(fence.name)\"}")
    }

    private func handleRemoveGeofence(body: String?) -> (Int, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else {
            return (400, "{\"error\":\"missing geofence name\"}")
        }

        lock.lock()
        let removed = geofences.removeValue(forKey: name) != nil
        lock.unlock()

        if removed {
            return (200, "{\"status\":\"removed\",\"name\":\"\(name)\"}")
        }
        return (404, "{\"error\":\"geofence not found\"}")
    }

    private func handleGeofenceTrigger(body: String?, deviceId: String?) -> (Int, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let eventType = json["event_type"] as? String else {
            return (400, "{\"error\":\"invalid trigger data\"}")
        }

        let latitude = json["latitude"] as? Double ?? 0
        let longitude = json["longitude"] as? Double ?? 0

        let alert = GeofenceAlert(
            geofenceName: name,
            eventType: eventType,
            timestamp: Date(),
            latitude: latitude,
            longitude: longitude
        )

        lock.lock()
        activeGeofenceAlerts.append(alert)
        // Keep only last 50 alerts
        if activeGeofenceAlerts.count > 50 {
            activeGeofenceAlerts = Array(activeGeofenceAlerts.suffix(50))
        }
        let action = geofences[name]?.action
        lock.unlock()

        var response: [String: Any] = ["status": "triggered", "geofence": name, "event": eventType]
        if let action = action {
            response["action"] = action
        }

        if let responseData = try? JSONSerialization.data(withJSONObject: response),
           let responseStr = String(data: responseData, encoding: .utf8) {
            return (200, responseStr)
        }
        return (200, "{\"status\":\"triggered\"}")
    }

    // MARK: - Shortcuts

    private func handleShortcut(body: String?, deviceId: String?) -> (Int, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shortcutId = json["shortcut_id"] as? String else {
            return (400, "{\"error\":\"invalid shortcut request\"}")
        }

        let parameters = json["parameters"] as? [String: Any] ?? [:]

        // Map shortcut IDs to agent commands
        let command: String
        switch shortcutId {
        case "ask":
            command = parameters["question"] as? String ?? "What's my status?"
        case "status":
            command = "Give me a brief system status summary"
        case "health_summary":
            command = "Summarize my latest health data from my Apple Watch"
        case "run_command":
            command = parameters["command"] as? String ?? ""
        case "quick_note":
            let note = parameters["note"] as? String ?? ""
            command = "Save this note: \(note)"
        default:
            command = "Unknown shortcut: \(shortcutId)"
        }

        let response: [String: Any] = [
            "status": "queued",
            "shortcut_id": shortcutId,
            "command": command
        ]

        if let responseData = try? JSONSerialization.data(withJSONObject: response),
           let responseStr = String(data: responseData, encoding: .utf8) {
            return (200, responseStr)
        }
        return (200, "{\"status\":\"queued\"}")
    }

    // MARK: - Complication Data

    private func handleComplicationData() -> (Int, String) {
        let uptime = Int(Date().timeIntervalSince(startTime))
        let formatter = ISO8601DateFormatter()

        let response: [String: Any] = [
            "status": currentStatus,
            "active_tasks": activeTasks,
            "last_activity": formatter.string(from: lastActivityTime),
            "uptime_minutes": uptime / 60,
            "short_status": currentStatus == "idle" ? "Ready" : currentStatus == "working" ? "Busy" : "Error"
        ]

        if let responseData = try? JSONSerialization.data(withJSONObject: response),
           let responseStr = String(data: responseData, encoding: .utf8) {
            return (200, responseStr)
        }
        return (200, "{\"status\":\"idle\",\"active_tasks\":0}")
    }

    // MARK: - Haversine Distance

    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        return R * c
    }
}
