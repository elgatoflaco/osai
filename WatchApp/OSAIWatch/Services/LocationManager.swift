import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
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

    // MARK: - Private

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var agentConnection: AgentConnection?

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.allowsBackgroundLocationUpdates = false
        loadGeofences()
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
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
    }

    // MARK: - Geofencing

    func addGeofence(name: String, latitude: Double, longitude: Double, radius: Double) {
        let geofence = Geofence(name: name, latitude: latitude, longitude: longitude, radius: radius)
        geofences.append(geofence)

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: min(radius, manager.maximumRegionMonitoringDistance),
            identifier: geofence.id
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)

        saveGeofences()
    }

    func removeGeofence(name: String) {
        guard let index = geofences.firstIndex(where: { $0.name == name }) else { return }
        let geofence = geofences[index]

        for region in manager.monitoredRegions {
            if region.identifier == geofence.id {
                manager.stopMonitoring(for: region)
                break
            }
        }

        geofences.remove(at: index)
        saveGeofences()
    }

    func removeGeofence(at offsets: IndexSet) {
        for index in offsets {
            let geofence = geofences[index]
            for region in manager.monitoredRegions {
                if region.identifier == geofence.id {
                    manager.stopMonitoring(for: region)
                    break
                }
            }
        }
        geofences.remove(atOffsets: offsets)
        saveGeofences()
    }

    func toggleGeofence(_ geofence: Geofence) {
        guard let index = geofences.firstIndex(where: { $0.id == geofence.id }) else { return }
        geofences[index].isActive.toggle()

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

        saveGeofences()
    }

    // MARK: - Reverse Geocoding

    private func reverseGeocode(location: CLLocation) {
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

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
            authorizationError = nil
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
        lastLocationUpdate = Date()
        reverseGeocode(location: location)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let geofence = geofences.first(where: { $0.id == region.identifier }) else { return }
        let message = "[Location] Entered geofenced zone: \(geofence.name)"

        Task {
            await agentConnection?.sendMessage(text: message)
        }

        activeLocationTasks.append("Entered: \(geofence.name)")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let geofence = geofences.first(where: { $0.id == region.identifier }) else { return }
        let message = "[Location] Exited geofenced zone: \(geofence.name)"

        Task {
            await agentConnection?.sendMessage(text: message)
        }

        activeLocationTasks.append("Exited: \(geofence.name)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        authorizationError = error.localizedDescription
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region {
            authorizationError = "Monitoring failed for \(region.identifier): \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private var geofenceStorageURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("geofences.json")
    }

    private func saveGeofences() {
        do {
            let data = try JSONEncoder().encode(geofences)
            try data.write(to: geofenceStorageURL, options: .atomic)
        } catch {
            // Silent failure for storage - geofences will be lost on relaunch
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

    // MARK: - Formatted Output

    var formattedCoordinates: String {
        guard currentLatitude != 0 || currentLongitude != 0 else { return "No location data" }
        return String(format: "%.4f, %.4f", currentLatitude, currentLongitude)
    }

    var formattedAltitude: String {
        return String(format: "%.0f m", currentAltitude)
    }
}
