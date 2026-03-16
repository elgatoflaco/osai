import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()

            Divider()
                .background(AppTheme.borderGlass)

            // Main content area
            ZStack {
                AppTheme.bgPrimary
                    .ignoresSafeArea()

                Group {
                    switch appState.selectedTab {
                    case .home:
                        DashboardView()
                    case .chat:
                        ChatView()
                    case .agents:
                        AgentsView()
                    case .tasks:
                        TasksView()
                    case .settings:
                        SettingsView()
                    }
                }
                .animation(.easeOut(duration: 0.25), value: appState.selectedTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.bgPrimary)
        .onAppear {
            appState.loadAll()
        }
        // Hidden buttons for keyboard shortcuts
        .background(
            Group {
                Button("") { appState.selectedTab = .home }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedTab = .chat }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedTab = .agents }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedTab = .tasks }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedTab = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                    .hidden()
                Button("") { appState.startNewChat() }
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
            }
        )
    }
}
