import SwiftUI
import WatchKit
import MapKit

struct LocationView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var connection: AgentConnection
    @EnvironmentObject var settings: WatchSettings
    @State private var showAddGeofence: Bool = false
    @State private var newGeofenceName: String = ""
    @State private var newGeofenceRadius: Double = 200

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !locationManager.isAuthorized {
                    authorizationCard
                } else {
                    // Current Location
                    currentLocationCard

                    // Map snippet
                    mapCard

                    // Tracking toggle
                    trackingToggle

                    // Geofences
                    geofencesSection

                    // Active Location Tasks
                    if !locationManager.activeLocationTasks.isEmpty {
                        activeTasksSection
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Location")
        .onAppear {
            locationManager.configure(connection: connection)
            if locationManager.isAuthorized && settings.locationTrackingEnabled {
                locationManager.startTracking()
            }
        }
    }

    // MARK: - Authorization Card

    private var authorizationCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Location Access Required")
                .font(.callout)
                .fontWeight(.semibold)

            Text("Grant access to track location and use geofences.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = locationManager.authorizationError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                locationManager.requestAuthorization()
            } label: {
                Label("Authorize", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Current Location

    private var currentLocationCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, isActive: locationManager.isTracking)

                Text("Current Location")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if locationManager.isTracking {
                    Text("Live")
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.3), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(locationManager.locationName)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(locationManager.formattedCoordinates)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)

                if locationManager.currentAltitude != 0 {
                    Text("Alt: \(locationManager.formattedAltitude)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let lastUpdate = locationManager.lastLocationUpdate {
                    Text("Updated \(lastUpdate, style: .relative) ago")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button {
                Task {
                    await connection.sendLocation(
                        latitude: locationManager.currentLatitude,
                        longitude: locationManager.currentLongitude
                    )
                }
            } label: {
                Label("Send to Agent", systemImage: "paperplane")
            }

            Button {
                Task {
                    await connection.sendMessage(
                        text: "I'm at \(locationManager.locationName) (\(locationManager.formattedCoordinates)). What's nearby?"
                    )
                }
            } label: {
                Label("Ask About Area", systemImage: "questionmark.circle")
            }
        }
    }

    // MARK: - Map Card

    private var mapCard: some View {
        Group {
            if locationManager.currentLatitude != 0 || locationManager.currentLongitude != 0 {
                let coordinate = CLLocationCoordinate2D(
                    latitude: locationManager.currentLatitude,
                    longitude: locationManager.currentLongitude
                )
                let region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )

                Map(initialPosition: .region(region)) {
                    Marker("You", coordinate: coordinate)
                        .tint(.blue)

                    // Show geofences on map
                    ForEach(locationManager.geofences.filter { $0.isActive }) { geofence in
                        MapCircle(
                            center: CLLocationCoordinate2D(
                                latitude: geofence.latitude,
                                longitude: geofence.longitude
                            ),
                            radius: geofence.radius
                        )
                        .foregroundStyle(.orange.opacity(0.2))
                        .stroke(.orange, lineWidth: 1)
                    }
                }
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Tracking Toggle

    private var trackingToggle: some View {
        Toggle(isOn: Binding(
            get: { locationManager.isTracking },
            set: { newValue in
                if newValue {
                    locationManager.startTracking()
                    settings.locationTrackingEnabled = true
                } else {
                    locationManager.stopTracking()
                    settings.locationTrackingEnabled = false
                }
            }
        )) {
            HStack(spacing: 6) {
                Image(systemName: "location.circle")
                    .foregroundStyle(.blue)
                Text("Location Tracking")
                    .font(.caption)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Geofences Section

    private var geofencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Geofences")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showAddGeofence = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 4)

            if locationManager.geofences.isEmpty {
                Text("No geofences configured")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(locationManager.geofences) { geofence in
                    HStack(spacing: 8) {
                        Image(systemName: geofence.isActive ? "mappin.circle.fill" : "mappin.slash")
                            .foregroundStyle(geofence.isActive ? .orange : .gray)
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(geofence.name)
                                .font(.caption)
                                .fontWeight(.medium)

                            Text("\(Int(geofence.radius))m radius")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Circle()
                            .fill(geofence.isActive ? .green : .gray)
                            .frame(width: 6, height: 6)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .contextMenu {
                        Button {
                            locationManager.toggleGeofence(geofence)
                        } label: {
                            Label(
                                geofence.isActive ? "Disable" : "Enable",
                                systemImage: geofence.isActive ? "pause.circle" : "play.circle"
                            )
                        }

                        Button(role: .destructive) {
                            locationManager.removeGeofence(name: geofence.name)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddGeofence) {
            addGeofenceSheet
        }
    }

    // MARK: - Add Geofence Sheet

    private var addGeofenceSheet: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("New Geofence")
                    .font(.callout)
                    .fontWeight(.semibold)

                TextField("Name", text: $newGeofenceName)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Radius: \(Int(newGeofenceRadius))m")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Slider(value: $newGeofenceRadius, in: 50...1000, step: 50)
                        .tint(.orange)
                }

                Text("Uses current location as center")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    guard !newGeofenceName.isEmpty else { return }
                    locationManager.addGeofence(
                        name: newGeofenceName,
                        latitude: locationManager.currentLatitude,
                        longitude: locationManager.currentLongitude,
                        radius: newGeofenceRadius
                    )
                    newGeofenceName = ""
                    newGeofenceRadius = 200
                    showAddGeofence = false
                } label: {
                    Text("Add Geofence")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(newGeofenceName.isEmpty)
            }
            .padding(8)
        }
    }

    // MARK: - Active Location Tasks

    private var activeTasksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location Events")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(locationManager.activeLocationTasks.suffix(5), id: \.self) { task in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    Text(task)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

#Preview {
    NavigationStack {
        LocationView()
            .environmentObject(LocationManager())
            .environmentObject(AgentConnection())
            .environmentObject(WatchSettings())
    }
}
