import SwiftUI

struct MenuBarChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @State private var lastResponse = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                GhostIcon(size: 20, animate: false)
                Text("OSAI Quick Chat")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                // Spending today
                Text("$\(String(format: "%.2f", appState.costToday))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Last response (scrollable, max height)
            if !lastResponse.isEmpty {
                ScrollView {
                    Text(lastResponse)
                        .font(.system(size: 11))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)

                Divider()
            }

            // Input
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { sendQuickMessage() }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button(action: sendQuickMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(10)

            Divider()

            // Quick actions
            HStack(spacing: 12) {
                Button("New Chat") {
                    NSApp.activate(ignoringOtherApps: true)
                    appState.startNewChat()
                }
                Button("Dashboard") {
                    NSApp.activate(ignoringOtherApps: true)
                    appState.selectedTab = .home
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 340)
    }

    private func sendQuickMessage() {
        guard !inputText.isEmpty else { return }
        let message = inputText
        inputText = ""
        isLoading = true

        // Open main window and send
        NSApp.activate(ignoringOtherApps: true)
        appState.startNewChat()
        appState.sendMessage(message)

        isLoading = false
    }
}
