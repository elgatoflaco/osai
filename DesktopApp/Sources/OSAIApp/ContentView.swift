import SwiftUI

// MARK: - Toast View

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(toast.type.color)

            Text(toast.message)
                .font(AppTheme.fontBody)
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(AppTheme.bgCard)
                .overlay(
                    Capsule()
                        .strokeBorder(toast.type.color.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: toast.type.color.opacity(0.2), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var showContent = false

    private var hasAPIKeys: Bool {
        !appState.config.apiKeys.isEmpty
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {} // Prevent taps from passing through

            // Modal card
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    VStack(spacing: 20) {
                        GhostIcon(size: 72)
                            .padding(.top, 32)

                        Text("Welcome to OSAI")
                            .font(AppTheme.fontTitle)
                            .foregroundColor(AppTheme.textPrimary)

                        Text("Your local AI command center")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.bottom, 28)

                    // Feature highlights
                    VStack(spacing: 14) {
                        OnboardingFeatureRow(icon: "bubble.left.and.bubble.right.fill",
                                             title: "Chat with AI agents",
                                             subtitle: "Have conversations powered by multiple AI models")
                        OnboardingFeatureRow(icon: "person.3.fill",
                                             title: "Automatic agent routing",
                                             subtitle: "Messages are dispatched to the best agent for the job")
                        OnboardingFeatureRow(icon: "clock.fill",
                                             title: "Schedule automated tasks",
                                             subtitle: "Set up recurring AI jobs with cron-like scheduling")
                        OnboardingFeatureRow(icon: "message.fill",
                                             title: "Connect via Telegram/WhatsApp",
                                             subtitle: "Access your agents from any messaging platform")
                    }
                    .padding(.horizontal, 32)

                    // API key hint
                    if !hasAPIKeys {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.warning)
                            Text("Run `osai config set-key anthropic <your-key>` in Terminal to get started")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.warning.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.warning.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                    }

                    // Get Started button
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            appState.hasCompletedOnboarding = true
                        }
                    }) {
                        Text("Get Started")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.bgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: 500)
            .padding(40)
            .scaleEffect(showContent ? 1.0 : 0.95)
            .opacity(showContent ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                showContent = true
            }
        }
    }
}

struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Content View

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
        // Onboarding overlay
        .overlay {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: appState.hasCompletedOnboarding)
        .overlay(alignment: .top) {
            if let toast = appState.toastMessage {
                ToastView(toast: toast)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .onTapGesture {
                        appState.toastMessage = nil
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.toastMessage)
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
                    .keyboardShortcut("5", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedTab = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                    .hidden()
                Button("") { appState.startNewChat() }
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
                Button("") {
                    appState.selectedTab = .chat
                    appState.shouldFocusInput = true
                }
                    .keyboardShortcut("l", modifiers: .command)
                    .hidden()
                Button("") { appState.cancelProcessing() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
        )
    }
}
