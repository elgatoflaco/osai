import SwiftUI

@main
struct OSAIWatchApp: App {
    @StateObject private var connection = AgentConnection()
    @StateObject private var healthManager = HealthManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var settings = WatchSettings()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .environmentObject(connection)
            .environmentObject(healthManager)
            .environmentObject(locationManager)
            .environmentObject(settings)
            .onAppear {
                connection.configure(settings: settings)
                connection.startDiscovery()
            }
        }
    }
}
