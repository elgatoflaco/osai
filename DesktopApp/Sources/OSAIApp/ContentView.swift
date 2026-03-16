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

enum PaletteCategory: String, CaseIterable {
    case navigation = "Navigation"
    case chat = "Chat"
    case agents = "Agents"
    case settings = "Settings"
    case recent = "Recent"

    var color: Color {
        switch self {
        case .navigation: return .blue
        case .chat: return AppTheme.accent
        case .agents: return .purple
        case .settings: return .orange
        case .recent: return AppTheme.textSecondary
        }
    }
}

struct PaletteCommand: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let shortcut: String?
    let category: PaletteCategory
    let action: () -> Void
}

/// Result of fuzzy matching: the matched command plus the indices of matched characters.
struct FuzzyMatch: Identifiable {
    var id: UUID { command.id }
    let command: PaletteCommand
    let matchedIndices: [String.Index]
    let score: Int
}

/// Performs fuzzy matching: characters in `query` must appear in `text` in order but not
/// necessarily consecutively. Returns matched character indices and a score, or nil if no match.
private func fuzzyMatch(query: String, in text: String) -> (indices: [String.Index], score: Int)? {
    let queryChars = Array(query.lowercased())
    let textLower = text.lowercased()
    guard !queryChars.isEmpty else { return ([], 0) }

    var matchedIndices: [String.Index] = []
    var queryIdx = 0
    var score = 0
    var lastMatchPos: Int? = nil
    var textPos = 0

    for idx in textLower.indices {
        guard queryIdx < queryChars.count else { break }
        if textLower[idx] == queryChars[queryIdx] {
            matchedIndices.append(text.index(text.startIndex, offsetBy: text.distance(from: textLower.startIndex, to: idx)))
            // Bonus for consecutive matches
            if let last = lastMatchPos, textPos == last + 1 {
                score += 5
            }
            // Bonus for matching at start of word
            if textPos == 0 || (textPos > 0 && text[text.index(text.startIndex, offsetBy: textPos - 1)] == " ") {
                score += 10
            }
            // Bonus for matching at start of text
            if textPos == 0 {
                score += 15
            }
            lastMatchPos = textPos
            queryIdx += 1
        }
        textPos += 1
    }

    guard queryIdx == queryChars.count else { return nil }
    // Base score: shorter labels rank higher when fully matched
    score += max(0, 50 - text.count)
    return (matchedIndices, score)
}

/// A Text view that highlights specific character indices with the accent color (for fuzzy match).
struct FuzzyHighlightedText: View {
    let text: String
    let matchedIndices: Set<String.Index>
    let baseColor: Color

    var body: some View {
        buildText()
    }

    private func buildText() -> Text {
        var result = Text("")
        for idx in text.indices {
            let char = String(text[idx])
            if matchedIndices.contains(idx) {
                result = result + Text(char)
                    .foregroundColor(AppTheme.accent)
                    .fontWeight(.bold)
            } else {
                result = result + Text(char)
                    .foregroundColor(baseColor)
            }
        }
        return result
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Binding var selectedTab: SidebarItem
    @State private var search = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var allCommands: [PaletteCommand] {
        var cmds: [PaletteCommand] = []

        // -- Navigation --
        cmds.append(PaletteCommand(icon: "house.fill", label: "Go to Dashboard", shortcut: "\u{2318}1", category: .navigation) {
            selectedTab = .home; isPresented = false
        })
        cmds.append(PaletteCommand(icon: "bubble.left.and.bubble.right.fill", label: "Go to Chat", shortcut: "\u{2318}2", category: .navigation) {
            selectedTab = .chat; isPresented = false
        })
        cmds.append(PaletteCommand(icon: "person.3.fill", label: "Go to Agents", shortcut: "\u{2318}3", category: .navigation) {
            selectedTab = .agents; isPresented = false
        })
        cmds.append(PaletteCommand(icon: "clock.fill", label: "Go to Tasks", shortcut: "\u{2318}4", category: .navigation) {
            selectedTab = .tasks; isPresented = false
        })
        cmds.append(PaletteCommand(icon: "gearshape.fill", label: "Go to Settings", shortcut: "\u{2318},", category: .navigation) {
            selectedTab = .settings; isPresented = false
        })

        // -- Chat --
        cmds.append(PaletteCommand(icon: "plus.bubble", label: "New Conversation", shortcut: "\u{2318}N", category: .chat) {
            appState.startNewChat(); isPresented = false
        })
        cmds.append(PaletteCommand(icon: "xmark.circle", label: "Clear Chat", shortcut: "\u{2318}W", category: .chat) {
            appState.closeCurrentConversation(); isPresented = false
        })
        cmds.append(PaletteCommand(icon: "square.and.arrow.up", label: "Export Conversation", shortcut: nil, category: .chat) {
            if let conv = appState.activeConversation { appState.exportAndSave(conv) }
            isPresented = false
        })
        cmds.append(PaletteCommand(icon: "magnifyingglass", label: "Search Messages", shortcut: "\u{2318}F", category: .chat) {
            selectedTab = .chat; appState.shouldFocusInput = true; isPresented = false
        })

        // -- Agents --
        cmds.append(PaletteCommand(icon: "person.3.fill", label: "List Agents", shortcut: nil, category: .agents) {
            selectedTab = .agents; isPresented = false
        })
        for agent in appState.agents {
            cmds.append(PaletteCommand(icon: agent.backendIcon, label: "Chat with \(agent.name)", shortcut: nil, category: .agents) {
                let conv = Conversation(
                    id: UUID().uuidString,
                    title: agent.name,
                    messages: [],
                    createdAt: Date(),
                    agentName: agent.name
                )
                appState.conversations.insert(conv, at: 0)
                appState.activeConversation = conv
                appState.selectedTab = .chat
                isPresented = false
            })
        }

        // -- Settings --
        cmds.append(PaletteCommand(icon: "moon.fill", label: "Toggle Dark Mode", shortcut: nil, category: .settings) {
            appState.isDarkMode.toggle(); isPresented = false
        })
        cmds.append(PaletteCommand(icon: "paintpalette.fill", label: "Change Accent Color", shortcut: nil, category: .settings) {
            selectedTab = .settings; isPresented = false
        })
        cmds.append(PaletteCommand(icon: "bolt.fill", label: "Toggle Gateway", shortcut: nil, category: .settings) {
            appState.toggleGateway(); isPresented = false
        })
        cmds.append(PaletteCommand(icon: "eye.slash", label: "Toggle Focus Mode", shortcut: nil, category: .settings) {
            appState.focusModeEnabled.toggle(); isPresented = false
        })

        // -- Recent (max 3) --
        for conv in appState.conversations.prefix(3) {
            cmds.append(PaletteCommand(icon: "text.bubble", label: conv.title, shortcut: nil, category: .recent) {
                appState.openConversation(conv); isPresented = false
            })
        }

        return cmds
    }

    private var filtered: [FuzzyMatch] {
        let commands = allCommands
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return commands.map { FuzzyMatch(command: $0, matchedIndices: [], score: 0) }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [FuzzyMatch] = []
        for cmd in commands {
            if let result = fuzzyMatch(query: query, in: cmd.label) {
                matches.append(FuzzyMatch(command: cmd, matchedIndices: result.indices, score: result.score))
            }
        }
        return matches.sorted { $0.score > $1.score }
    }

    /// The visible results, capped at 8.
    private var visibleResults: [FuzzyMatch] {
        Array(filtered.prefix(8))
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
                    Image(systemName: "command")
                        .foregroundColor(AppTheme.accent)
                        .font(.system(size: 14, weight: .semibold))
                    TextField("Search commands...", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textPrimary)
                        .focused($isSearchFocused)
                        .onSubmit { executeSelected() }

                    if !search.isEmpty {
                        Button(action: { search = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.textMuted)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("esc")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.bgSecondary.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .background(AppTheme.borderGlass)

                // Command list
                if visibleResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No matching commands")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(visibleResults.enumerated()), id: \.element.id) { index, match in
                                    let cmd = match.command
                                    let isSelected = index == selectedIndex

                                    HStack(spacing: 10) {
                                        // Icon
                                        Image(systemName: cmd.icon)
                                            .font(.system(size: 13))
                                            .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                                            .frame(width: 24, height: 24)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(isSelected ? AppTheme.accent.opacity(0.15) : AppTheme.bgSecondary.opacity(0.4))
                                            )

                                        // Label with highlighted matched chars
                                        if match.matchedIndices.isEmpty {
                                            Text(cmd.label)
                                                .font(.system(size: 13))
                                                .foregroundColor(AppTheme.textPrimary)
                                                .lineLimit(1)
                                        } else {
                                            FuzzyHighlightedText(
                                                text: cmd.label,
                                                matchedIndices: Set(match.matchedIndices),
                                                baseColor: AppTheme.textPrimary
                                            )
                                            .font(.system(size: 13))
                                            .lineLimit(1)
                                        }

                                        Spacer()

                                        // Category badge
                                        Text(cmd.category.rawValue)
                                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                                            .foregroundColor(cmd.category.color.opacity(0.9))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(cmd.category.color.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))

                                        // Keyboard shortcut
                                        if let shortcut = cmd.shortcut {
                                            Text(shortcut)
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(AppTheme.textMuted)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.bgSecondary.opacity(0.5))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? AppTheme.accent.opacity(0.1) : Color.clear)
                                            .padding(.horizontal, 4)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { cmd.action() }
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIndex) {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(selectedIndex, anchor: .center)
                            }
                        }
                    }
                }

                // Footer hint
                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 7))
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                        Text("navigate")
                            .font(.system(size: 10))
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "return")
                            .font(.system(size: 8))
                        Text("select")
                            .font(.system(size: 10))
                    }
                    Spacer()
                    Text("\(filtered.count) commands")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppTheme.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.bgSecondary.opacity(0.3))
            }
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(AppTheme.borderGlass, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)
            .padding(.bottom, 100)
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
            if selectedIndex < visibleResults.count - 1 { selectedIndex += 1 }
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
        guard !visibleResults.isEmpty, selectedIndex < visibleResults.count else { return }
        visibleResults[selectedIndex].command.action()
    }
}

// MARK: - Window Accessor

/// NSViewRepresentable that provides access to the hosting NSWindow for frame tracking and settings.
struct WindowAccessor: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.observeWindow(window, appState: appState)

            // Restore saved frame
            if let savedFrame = appState.savedWindowFrame {
                let screens = NSScreen.screens
                let onScreen = screens.contains { $0.visibleFrame.intersects(savedFrame) }
                if onScreen {
                    window.setFrame(savedFrame, display: true)
                }
            }

            // Apply float-on-top and opacity
            window.level = appState.floatOnTop ? .floating : .normal
            window.alphaValue = CGFloat(appState.windowOpacity)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        private var moveObserver: Any?
        private var resizeObserver: Any?

        func observeWindow(_ window: NSWindow, appState: AppState) {
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { _ in
                Task { @MainActor in appState.saveWindowFrame(window.frame) }
            }
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { _ in
                Task { @MainActor in appState.saveWindowFrame(window.frame) }
            }
        }

        deinit {
            if let o = moveObserver { NotificationCenter.default.removeObserver(o) }
            if let o = resizeObserver { NotificationCenter.default.removeObserver(o) }
        }
    }
}

// MARK: - Compact Mode Header

struct CompactModeHeader: View {
    @EnvironmentObject var appState: AppState
    @Binding var showCompactMenu: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { showCompactMenu.toggle() }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.borderGlass, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Navigation menu")

            GhostIcon(size: 20, isProcessing: appState.isProcessing)

            Text("osai")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            if appState.floatOnTop {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.accent)
                    .help("Floating on top")
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.bgSecondary.opacity(0.8))
    }
}

// MARK: - Compact Navigation Menu

struct CompactNavigationMenu: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SidebarItem.allCases) { item in
                Button(action: {
                    appState.selectedTab = item
                    isPresented = false
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .foregroundColor(appState.selectedTab == item ? AppTheme.accent : AppTheme.textSecondary)
                            .frame(width: 20)

                        Text(item.rawValue)
                            .font(.system(size: 13, weight: appState.selectedTab == item ? .semibold : .regular))
                            .foregroundColor(appState.selectedTab == item ? AppTheme.textPrimary : AppTheme.textSecondary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(appState.selectedTab == item ? AppTheme.accent.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Divider().background(AppTheme.borderGlass).padding(.vertical, 4)

            Button(action: {
                appState.toggleCompactMode()
                isPresented = false
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 20)
                    Text("Exit Compact Mode")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(AppTheme.borderGlass, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var hotkeyManager = HotkeyManager()
    @State private var showCommandPalette = false
    @State private var commandSearch = ""
    @State private var showCompactMenu = false

    var body: some View {
        GeometryReader { geo in
            let windowWidth = geo.size.width
            let isNarrow = windowWidth < 800
            let isVeryNarrow = windowWidth < 600
            let hideSidebar = isVeryNarrow || appState.compactMode

            ZStack(alignment: .leading) {
                if appState.compactMode {
                    // Compact mode: no sidebar, minimal header + content
                    VStack(spacing: 0) {
                        CompactModeHeader(showCompactMenu: $showCompactMenu)
                            .environmentObject(appState)

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .animation(.easeInOut(duration: 0.2), value: appState.selectedTab)
                    }
                    .overlay(alignment: .topLeading) {
                        if showCompactMenu {
                            Color.black.opacity(0.01)
                                .ignoresSafeArea()
                                .onTapGesture { showCompactMenu = false }

                            CompactNavigationMenu(isPresented: $showCompactMenu)
                                .environmentObject(appState)
                                .padding(.top, 44)
                                .padding(.leading, 8)
                                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                                .zIndex(20)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: showCompactMenu)
                } else {
                    HStack(spacing: 0) {
                        // Sidebar: hidden when very narrow, collapsed when narrow, full otherwise
                        if !hideSidebar {
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
                            if hideSidebar {
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
                        // Float-on-top pin indicator (non-compact mode)
                        .overlay(alignment: .topTrailing) {
                            if appState.floatOnTop {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.accent)
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .padding(.top, 8)
                                    .padding(.trailing, 8)
                                    .help("Window floating on top")
                            }
                        }
                    }

                    // Overlay sidebar for very narrow / compact windows
                    if hideSidebar && appState.showSidebarOverlay {
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
            }
            .animation(.easeOut(duration: 0.25), value: appState.showSidebarOverlay)
            .animation(.easeInOut(duration: 0.3), value: appState.compactMode)
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
                appState.sidebarHidden = veryNarrow || appState.compactMode
                if veryNarrow {
                    appState.showSidebarOverlay = false
                }
            }
            .onAppear {
                // Set initial state based on window size
                if windowWidth < 800 {
                    appState.sidebarCollapsed = true
                }
                appState.sidebarHidden = windowWidth < 600 || appState.compactMode
            }
        }
        // Window accessor for frame persistence and window-level settings
        .background(WindowAccessor(appState: appState))
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
        // React to float-on-top and opacity changes
        .onChange(of: appState.floatOnTop) {
            appState.applyWindowSettings()
        }
        .onChange(of: appState.windowOpacity) {
            appState.applyWindowSettings()
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
