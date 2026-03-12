import Foundation
import CoreLocation
import MapKit
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    // MARK: - Published Properties

    @Published var currentLatitude: Double = 0
    @Published var currentLongitude: Double = 0
    @Published var currentAltitude: Double = 0
    @Published var locationName: String = "Unknown"
    @Published var isAuthorized: Bool = false
    @Published var isTracking: Bool = false
    @Published var geofences: [Geofence] = []
    @Published var lastLocationUpdate: Date?
    @Published var authorizationError: String?
    @Published var activeLocationTasks: [String] = []

    // Enhanced location features
    @Published var currentSpeed: Double = 0 // m/s
    @Published var heading: Double = 0
    @Published var travelEstimates: [TravelEstimate] = []
    @Published var locationSuggestions: [LocationSuggestion] = []
    @Published var visitedPlaces: [VisitedPlace] = []
    @Published var isMoving: Bool = false

    // MARK: - Private

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var agentConnection: AgentConnection?
    private var lastGeocodeDate: Date?
    private var lastSuggestionUpdate: Date?
    private var previousLocations: [CLLocation] = []

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // Update every 10 meters for smoother tracking
        loadGeofences()
        loadVisitedPlaces()
    }

    // MARK: - Configuration

    func configure(connection: AgentConnection) {
        self.agentConnection = connection
    }

    // MARK: - Authorization

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - Tracking

    func startTracking() {
        guard isAuthorized else {
            requestAuthorization()
            return
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
    }

    // MARK: - Geofencing

    func addGeofence(name: String, latitude: Double, longitude: Double, radius: Double) {
        let geofence = Geofence(name: name, latitude: latitude, longitude: longitude, radius: radius)
        geofences.append(geofence)

        #if !os(watchOS)
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: min(radius, manager.maximumRegionMonitoringDistance),
            identifier: geofence.id
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
        #endif

        saveGeofences()
    }

    func addGeofenceAtCurrentLocation(name: String, radius: Double) {
        guard currentLatitude != 0 || currentLongitude != 0 else { return }
        addGeofence(name: name, latitude: currentLatitude, longitude: currentLongitude, radius: radius)
    }

    func removeGeofence(name: String) {
        guard let index = geofences.firstIndex(where: { $0.name == name }) else { return }
        let geofence = geofences[index]

        #if !os(watchOS)
        for region in manager.monitoredRegions {
            if region.identifier == geofence.id {
                manager.stopMonitoring(for: region)
                break
            }
        }
        #endif

        geofences.remove(at: index)
        saveGeofences()
    }

    func removeGeofence(at offsets: IndexSet) {
        for index in offsets {
            let geofence = geofences[index]
            #if !os(watchOS)
            for region in manager.monitoredRegions {
                if region.identifier == geofence.id {
                    manager.stopMonitoring(for: region)
                    break
                }
            }
            #endif
        }
        geofences.remove(atOffsets: offsets)
        saveGeofences()
    }

    func toggleGeofence(_ geofence: Geofence) {
        guard let index = geofences.firstIndex(where: { $0.id == geofence.id }) else { return }
        geofences[index].isActive.toggle()

        #if !os(watchOS)
        if geofences[index].isActive {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: geofence.latitude, longitude: geofence.longitude),
                radius: min(geofence.radius, manager.maximumRegionMonitoringDistance),
                identifier: geofence.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        } else {
            for region in manager.monitoredRegions {
                if region.identifier == geofence.id {
                    manager.stopMonitoring(for: region)
                    break
                }
            }
        }
        #endif

        saveGeofences()
    }

    // MARK: - Travel Time Estimates

    func calculateTravelTime(to destination: CLLocationCoordinate2D, name: String) async {
        guard currentLatitude != 0 || currentLongitude != 0 else { return }

        let source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: currentLatitude, longitude: currentLongitude
        )))
        let dest = MKMapItem(placemark: MKPlacemark(coordinate: destination))

        // Walking estimate
        let walkingRequest = MKDirections.Request()
        walkingRequest.source = source
        walkingRequest.destination = dest
        walkingRequest.transportType = .walking

        // Driving estimate
        let drivingRequest = MKDirections.Request()
        drivingRequest.source = source
        drivingRequest.destination = dest
        drivingRequest.transportType = .automobile

        var walkingTime: TimeInterval?
        var drivingTime: TimeInterval?
        var distance: Double = 0

        do {
            let walkingDirections = MKDirections(request: walkingRequest)
            let walkingResponse = try await walkingDirections.calculate()
            if let route = walkingResponse.routes.first {
                walkingTime = route.expectedTravelTime
                distance = route.distance
            }
        } catch {
            // Walking directions not available
        }

        do {
            let drivingDirections = MKDirections(request: drivingRequest)
            let drivingResponse = try await drivingDirections.calculate()
            if let route = drivingResponse.routes.first {
                drivingTime = route.expectedTravelTime
                if distance == 0 { distance = route.distance }
            }
        } catch {
            // Driving directions not available
        }

        let estimate = TravelEstimate(
            destination: name,
            walkingTime: walkingTime,
            drivingTime: drivingTime,
            distance: distance
        )

        await MainActor.run {
            // Replace existing estimate for same destination or add new
            if let index = travelEstimates.firstIndex(where: { $0.destination == name }) {
                travelEstimates[index] = estimate
            } else {
                travelEstimates.append(estimate)
            }
            // Keep only 5 most recent estimates
            if travelEstimates.count > 5 {
                travelEstimates = Array(travelEstimates.suffix(5))
            }
        }
    }

    /// Calculate travel times to all active geofences
    func calculateTravelToGeofences() async {
        for geofence in geofences where geofence.isActive {
            let coordinate = CLLocationCoordinate2D(latitude: geofence.latitude, longitude: geofence.longitude)
            await calculateTravelTime(to: coordinate, name: geofence.name)
        }
    }

    // MARK: - Smart Location Suggestions

    func updateLocationSuggestions() {
        let now = Date()
        if let last = lastSuggestionUpdate, now.timeIntervalSince(last) < 300 { return }
        lastSuggestionUpdate = now

        var suggestions: [LocationSuggestion] = []
        let hour = Calendar.current.component(.hour, from: now)

        // Time-based suggestions
        if hour >= 6 && hour <= 9 {
            suggestions.append(LocationSuggestion(
                name: "Morning Commute",
                detail: "Check traffic to work",
                icon: "car.fill",
                command: "What's my commute looking like this morning?"
            ))
        } else if hour >= 11 && hour <= 13 {
            suggestions.append(LocationSuggestion(
                name: "Lunch Nearby",
                detail: "Find restaurants near \(locationName)",
                icon: "fork.knife",
                command: "What are some good lunch spots near me at \(locationName)?"
            ))
        } else if hour >= 17 && hour <= 19 {
            suggestions.append(LocationSuggestion(
                name: "Evening Commute",
                detail: "Check route home",
                icon: "house.fill",
                command: "What's the traffic like for my commute home?"
            ))
        }

        // Location-aware suggestions
        if currentLatitude != 0 || currentLongitude != 0 {
            suggestions.append(LocationSuggestion(
                name: "Area Info",
                detail: "What's around \(locationName)",
                icon: "map.fill",
                command: "Tell me about the area around \(locationName) (\(formattedCoordinates))"
            ))

            suggestions.append(LocationSuggestion(
                name: "Weather Here",
                detail: "Current conditions",
                icon: "cloud.sun.fill",
                command: "What's the weather like at my current location \(locationName)?"
            ))
        }

        // Movement-based suggestions
        if isMoving && currentSpeed > 1.5 {
            suggestions.append(LocationSuggestion(
                name: "Track Journey",
                detail: "You're on the move",
                icon: "figure.walk",
                command: "I'm currently traveling from \(locationName). Track my journey."
            ))
        }

        // Geofence proximity suggestions
        for geofence in geofences where geofence.isActive {
            let distance = distanceTo(latitude: geofence.latitude, longitude: geofence.longitude)
            if distance < geofence.radius * 3 && distance > geofence.radius {
                suggestions.append(LocationSuggestion(
                    name: "Near \(geofence.name)",
                    detail: "\(Int(distance))m away",
                    icon: "mappin.circle",
                    command: "I'm approaching \(geofence.name), about \(Int(distance)) meters away.",
                    latitude: geofence.latitude,
                    longitude: geofence.longitude
                ))
            }
        }

        locationSuggestions = suggestions
    }

    // MARK: - Distance Calculation

    func distanceTo(latitude: Double, longitude: Double) -> Double {
        guard currentLatitude != 0 || currentLongitude != 0 else { return 0 }
        let current = CLLocation(latitude: currentLatitude, longitude: currentLongitude)
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return current.distance(from: target)
    }

    // MARK: - Reverse Geocoding

    private func reverseGeocode(location: CLLocation) {
        // Throttle geocoding to once per 30 seconds
        let now = Date()
        if let last = lastGeocodeDate, now.timeIntervalSince(last) < 30 { return }
        lastGeocodeDate = now

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first else { return }
            Task { @MainActor in
                if let locality = placemark.locality, let area = placemark.subLocality {
                    self?.locationName = "\(area), \(locality)"
                } else if let locality = placemark.locality {
                    self?.locationName = locality
                } else if let name = placemark.name {
                    self?.locationName = name
                }
            }
        }
    }

    // MARK: - Visited Places Tracking

    private func recordVisit(location: CLLocation) {
        let now = Date()
        // Check if we've been stationary for a while at this location
        if let lastVisit = visitedPlaces.last,
           distanceTo(latitude: lastVisit.latitude, longitude: lastVisit.longitude) < 100 {
            return // Still at the same place
        }

        // Only record if we've been here for more than 5 minutes
        let recentLocations = previousLocations.suffix(30) // ~5 min at 10s intervals
        let allNearby = recentLocations.allSatisfy { loc in
            loc.distance(from: location) < 50
        }

        if allNearby && recentLocations.count >= 10 {
            let place = VisitedPlace(
                name: locationName,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                arrivedAt: now
            )
            visitedPlaces.append(place)
            if visitedPlaces.count > 20 {
                visitedPlaces = Array(visitedPlaces.suffix(20))
            }
            saveVisitedPlaces()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            authorizationError = nil
            #if !os(watchOS)
            // Re-register monitored geofences
            for geofence in geofences where geofence.isActive {
                let region = CLCircularRegion(
                    center: CLLocationCoordinate2D(latitude: geofence.latitude, longitude: geofence.longitude),
                    radius: min(geofence.radius, manager.maximumRegionMonitoringDistance),
                    identifier: geofence.id
                )
                region.notifyOnEntry = true
                region.notifyOnExit = true
                manager.startMonitoring(for: region)
            }
            #endif
        case .denied:
            isAuthorized = false
            authorizationError = "Location access denied. Enable in Settings."
        case .restricted:
            isAuthorized = false
            authorizationError = "Location access restricted."
        case .notDetermined:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLatitude = location.coordinate.latitude
        currentLongitude = location.coordinate.longitude
        currentAltitude = location.altitude
        currentSpeed = max(location.speed, 0)
        isMoving = currentSpeed > 0.5 // Moving faster than 0.5 m/s
        lastLocationUpdate = Date()

        previousLocations.append(location)
        if previousLocations.count > 60 {
            previousLocations = Array(previousLocations.suffix(60))
        }

        reverseGeocode(location: location)
        updateLocationSuggestions()
        recordVisit(location: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading
    }

    #if !os(watchOS)
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let geofence = geofences.first(where: { $0.id == region.identifier }) else { return }
        let message = "[Location] Entered geofenced zone: \(geofence.name)"

        Task {
            await agentConnection?.sendMessage(text: message)
        }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        activeLocationTasks.append("[\(timestamp)] Entered: \(geofence.name)")
        if activeLocationTasks.count > 20 {
            activeLocationTasks = Array(activeLocationTasks.suffix(20))
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let geofence = geofences.first(where: { $0.id == region.identifier }) else { return }
        let message = "[Location] Exited geofenced zone: \(geofence.name)"

        Task {
            await agentConnection?.sendMessage(text: message)
        }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        activeLocationTasks.append("[\(timestamp)] Exited: \(geofence.name)")
        if activeLocationTasks.count > 20 {
            activeLocationTasks = Array(activeLocationTasks.suffix(20))
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region {
            authorizationError = "Monitoring failed for \(region.identifier): \(error.localizedDescription)"
        }
    }
    #endif

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Only set error for non-transient failures
        if let clError = error as? CLError, clError.code != .locationUnknown {
            authorizationError = error.localizedDescription
        }
    }

    // MARK: - Location Summary for Agent

    func generateLocationSummary() -> String {
        var lines: [String] = []
        lines.append("Location: \(locationName)")
        lines.append("Coordinates: \(formattedCoordinates)")
        if currentAltitude != 0 {
            lines.append("Altitude: \(formattedAltitude)")
        }
        if isMoving {
            lines.append("Speed: \(formattedSpeed)")
            lines.append("Heading: \(formattedHeading)")
        }
        if !geofences.isEmpty {
            let activeCount = geofences.filter(\.isActive).count
            lines.append("Geofences: \(activeCount) active of \(geofences.count)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private var geofenceStorageURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("geofences.json")
    }

    private var visitedPlacesURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("visited_places.json")
    }

    private func saveGeofences() {
        do {
            let data = try JSONEncoder().encode(geofences)
            try data.write(to: geofenceStorageURL, options: .atomic)
        } catch {
            // Silent failure for storage
        }
    }

    private func loadGeofences() {
        do {
            let data = try Data(contentsOf: geofenceStorageURL)
            geofences = try JSONDecoder().decode([Geofence].self, from: data)
        } catch {
            geofences = []
        }
    }

    private func saveVisitedPlaces() {
        do {
            let data = try JSONEncoder().encode(visitedPlaces)
            try data.write(to: visitedPlacesURL, options: .atomic)
        } catch {
            // Silent failure
        }
    }

    private func loadVisitedPlaces() {
        do {
            let data = try Data(contentsOf: visitedPlacesURL)
            visitedPlaces = try JSONDecoder().decode([VisitedPlace].self, from: data)
        } catch {
            visitedPlaces = []
        }
    }

    // MARK: - Formatted Output

    var formattedCoordinates: String {
        guard currentLatitude != 0 || currentLongitude != 0 else { return "No location data" }
        return String(format: "%.4f, %.4f", currentLatitude, currentLongitude)
    }

    var formattedAltitude: String {
        return String(format: "%.0f m", currentAltitude)
    }

    var formattedSpeed: String {
        let kmh = currentSpeed * 3.6
        if kmh < 1 { return "Stationary" }
        return String(format: "%.1f km/h", kmh)
    }

    var formattedHeading: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[max(0, min(index, 7))]
    }
}

// MARK: - Visited Place

struct VisitedPlace: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let arrivedAt: Date

    init(name: String, latitude: Double, longitude: Double, arrivedAt: Date) {
        self.id = UUID().uuidString
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.arrivedAt = arrivedAt
    }
}
