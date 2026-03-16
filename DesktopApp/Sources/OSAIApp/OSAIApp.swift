import SwiftUI

@main
struct OSAIApp: App {
    @StateObject var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // File menu additions
            CommandGroup(after: .newItem) {
                Button("New Chat") {
                    appState.startNewChat()
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()
            }

            // View menu
            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.sidebarCollapsed.toggle()
                    }
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Focus Mode") {
                    appState.selectedTab = .chat
                    appState.shouldFocusInput = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.sidebarCollapsed = true
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            // Chat menu
            CommandMenu("Chat") {
                Button("Send Message") {
                    appState.shouldFocusInput = true
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cancel") {
                    appState.cancelProcessing()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!appState.isProcessing)
            }
        }
    }
}
