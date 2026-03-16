import SwiftUI
import AppKit

// MARK: - Hotkey Manager

/// Manages global and local keyboard monitors for the summon hotkey (Cmd+Shift+Space).
/// Global monitoring requires accessibility permissions; if not granted the global monitor
/// is silently skipped so the app does not crash.
@MainActor
final class HotkeyManager: ObservableObject {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Install both global and local event monitors.
    func install(onSummon: @escaping () -> Void) {
        // Local monitor — works when the app is already focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.isSummonHotkey(event) {
                onSummon()
                return nil  // consume the event
            }
            return event
        }

        // Global monitor — works when the app is in the background.
        // This requires the Accessibility permission; if not granted the system
        // simply returns nil and we move on without crashing.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if Self.isSummonHotkey(event) {
                Task { @MainActor in
                    onSummon()
                }
            }
        }
    }

    /// Remove both monitors.
    func uninstall() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    /// Check for Cmd+Shift+Space
    private static func isSummonHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 49  // 49 = Space
            && flags.contains(.command)
            && flags.contains(.shift)
    }
}

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

// MARK: - Command Palette

struct PaletteCommand: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let shortcut: String?
    let action: () -> Void
}

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Binding var selectedTab: SidebarItem
    @State private var search = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var commands: [PaletteCommand] {
        var cmds: [PaletteCommand] = [
            PaletteCommand(icon: "plus.bubble", label: "New Chat", shortcut: "\u{2318}N") {
                appState.startNewChat(); isPresented = false
            },
            PaletteCommand(icon: "bolt.fill", label: "Toggle Gateway", shortcut: nil) {
                appState.toggleGateway(); isPresented = false
            },
            PaletteCommand(icon: "house.fill", label: "Dashboard", shortcut: "\u{2318}1") {
                selectedTab = .home; isPresented = false
            },
            PaletteCommand(icon: "bubble.left.and.bubble.right.fill", label: "Chat", shortcut: "\u{2318}2") {
                selectedTab = .chat; isPresented = false
            },
            PaletteCommand(icon: "person.3.fill", label: "Agents", shortcut: "\u{2318}3") {
                selectedTab = .agents; isPresented = false
            },
            PaletteCommand(icon: "clock.fill", label: "Tasks", shortcut: "\u{2318}4") {
                selectedTab = .tasks; isPresented = false
            },
            PaletteCommand(icon: "gearshape.fill", label: "Settings", shortcut: "\u{2318},") {
                selectedTab = .settings; isPresented = false
            },
            PaletteCommand(icon: "square.and.arrow.up", label: "Export Chat", shortcut: nil) {
                if let conv = appState.activeConversation {
                    appState.exportAndSave(conv)
                }
                isPresented = false
            },
            PaletteCommand(icon: "moon.fill", label: "Toggle Dark Mode", shortcut: nil) {
                appState.isDarkMode.toggle(); isPresented = false
            },
            PaletteCommand(icon: "eye.slash", label: "Toggle Focus Mode", shortcut: nil) {
                appState.focusModeEnabled.toggle(); isPresented = false
            },
        ]

        // Recent conversations (last 5)
        let recent = appState.conversations.prefix(5)
        for conv in recent {
            cmds.append(PaletteCommand(icon: "text.bubble", label: "Open: \(conv.title)", shortcut: nil) {
                appState.openConversation(conv)
                isPresented = false
            })
        }

        return cmds
    }

    private var filtered: [PaletteCommand] {
        if search.isEmpty { return commands }
        let query = search.lowercased()
        return commands.filter { $0.label.lowercased().contains(query) }
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.textSecondary)
                        .font(.system(size: 15))
                    TextField("Type a command...", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textPrimary)
                        .focused($isSearchFocused)
                        .onSubmit { executeSelected() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .background(AppTheme.borderGlass)

                // Command list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, cmd in
                                HStack(spacing: 12) {
                                    Image(systemName: cmd.icon)
                                        .font(.system(size: 13))
                                        .foregroundColor(index == selectedIndex ? AppTheme.accent : AppTheme.textSecondary)
                                        .frame(width: 22)

                                    Text(cmd.label)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)

                                    Spacer()

                                    if let shortcut = cmd.shortcut {
                                        Text(shortcut)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundColor(AppTheme.textSecondary.opacity(0.6))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppTheme.bgSecondary.opacity(0.5))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(index == selectedIndex ? AppTheme.accent.opacity(0.12) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    cmd.action()
                                }
                                .id(index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(selectedIndex, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(AppTheme.borderGlass, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 40)
            .padding(.bottom, 120)
        }
        .onAppear {
            search = ""
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: search) {
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filtered.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.return) {
            executeSelected()
            return .handled
        }
    }

    private func executeSelected() {
        guard !filtered.isEmpty, selectedIndex < filtered.count else { return }
        filtered[selectedIndex].action()
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var hotkeyManager = HotkeyManager()
    @State private var showCommandPalette = false
    @State private var commandSearch = ""

    var body: some View {
        GeometryReader { geo in
            let windowWidth = geo.size.width
            let isNarrow = windowWidth < 800
            let isVeryNarrow = windowWidth < 600

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    // Sidebar: hidden when very narrow, collapsed when narrow, full otherwise
                    if !isVeryNarrow {
                        Sidebar()
                            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: appState.sidebarCollapsed)
                            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isNarrow)

                        // Subtle divider between sidebar and content
                        Rectangle()
                            .fill(AppTheme.borderGlass.opacity(0.5))
                            .frame(width: 1)
                            .ignoresSafeArea()
                    }

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
                        .id(appState.selectedTab)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .animation(.easeInOut(duration: 0.2), value: appState.selectedTab)
                    .overlay(alignment: .topLeading) {
                        // Sidebar toggle when sidebar is hidden
                        if isVeryNarrow {
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    appState.showSidebarOverlay.toggle()
                                }
                            }) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppTheme.borderGlass, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                            .padding(.leading, 8)
                            .help("Show sidebar")
                        }
                    }
                }

                // Overlay sidebar for very narrow windows
                if isVeryNarrow && appState.showSidebarOverlay {
                    // Dimming backdrop
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                appState.showSidebarOverlay = false
                            }
                        }
                        .zIndex(10)

                    // Sidebar overlay
                    HStack(spacing: 0) {
                        Sidebar()
                        Rectangle()
                            .fill(AppTheme.borderGlass.opacity(0.5))
                            .frame(width: 1)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 5, y: 0)
                    .transition(.move(edge: .leading))
                    .zIndex(11)
                }
            }
            .animation(.easeOut(duration: 0.25), value: appState.showSidebarOverlay)
            .onChange(of: isNarrow) { _, narrow in
                // Auto-collapse sidebar when window becomes narrow
                if narrow && !appState.sidebarCollapsed {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        appState.sidebarCollapsed = true
                    }
                }
            }
            .onChange(of: isVeryNarrow) { _, veryNarrow in
                // Update state for ChatView to react to
                appState.sidebarHidden = veryNarrow
                if veryNarrow {
                    appState.showSidebarOverlay = false
                }
            }
            .onAppear {
                // Set initial state based on window size
                if windowWidth < 800 {
                    appState.sidebarCollapsed = true
                }
                appState.sidebarHidden = windowWidth < 600
            }
        }
        // Onboarding overlay
        .overlay {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: appState.hasCompletedOnboarding)
        // Command palette overlay
        .overlay {
            if showCommandPalette {
                CommandPaletteView(
                    isPresented: $showCommandPalette,
                    selectedTab: $appState.selectedTab
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCommandPalette)
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
            if appState.globalHotkeyEnabled {
                installHotkey()
            }
        }
        .onDisappear {
            hotkeyManager.uninstall()
        }
        .onChange(of: appState.globalHotkeyEnabled) {
            if appState.globalHotkeyEnabled {
                installHotkey()
            } else {
                hotkeyManager.uninstall()
            }
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
                Button("") { showCommandPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                    .hidden()
                Button("") { appState.closeCurrentConversation() }
                    .keyboardShortcut("w", modifiers: .command)
                    .hidden()
                Button("") { appState.copyLastAssistantMessage() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .hidden()
                Button("") { appState.navigateConversation(direction: -1) }
                    .keyboardShortcut("[", modifiers: .command)
                    .hidden()
                Button("") { appState.navigateConversation(direction: 1) }
                    .keyboardShortcut("]", modifiers: .command)
                    .hidden()
            }
        )
    }

    // MARK: - Hotkey

    private func installHotkey() {
        hotkeyManager.uninstall()
        hotkeyManager.install { [weak appState] in
            guard let appState = appState else { return }
            if NSApp.isActive {
                // Already frontmost — focus the chat input
                appState.selectedTab = .chat
                appState.shouldFocusInput = true
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
