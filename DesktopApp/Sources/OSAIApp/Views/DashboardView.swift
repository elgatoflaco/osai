import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var taskInput = ""

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppTheme.paddingLg) {
                    // Hero section (always visible)
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            GhostIcon(size: 64)
                            Spacer()

                            // Customize button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    appState.showDashboardCustomizer.toggle()
                                }
                            }) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 14))
                                    .foregroundColor(appState.showDashboardCustomizer ? AppTheme.accent : AppTheme.textSecondary)
                                    .padding(8)
                                    .background(
                                        appState.showDashboardCustomizer
                                            ? AppTheme.accent.opacity(0.12)
                                            : AppTheme.bgCard.opacity(0.4)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                appState.showDashboardCustomizer
                                                    ? AppTheme.accent.opacity(0.3)
                                                    : AppTheme.borderGlass,
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Customize dashboard sections")
                        }
                        .padding(.top, 20)

                        Text("What can I help you with?")
                            .font(AppTheme.fontTitle)
                            .foregroundColor(AppTheme.textPrimary)

                        TaskInputField(text: $taskInput, placeholder: "Ask anything...") {
                            appState.sendMessage(taskInput)
                            taskInput = ""
                        }
                        .frame(maxWidth: 600)

                        // Quick actions
                        HStack(spacing: 10) {
                            QuickAction(icon: "plus.bubble", label: "New chat") {
                                appState.startNewChat()
                            }
                            QuickAction(icon: "person.3", label: "Agents") {
                                appState.selectedTab = .agents
                            }
                            QuickAction(icon: "clock", label: "Tasks") {
                                appState.selectedTab = .tasks
                            }
                            QuickAction(icon: "gearshape", label: "Settings") {
                                appState.selectedTab = .settings
                            }
                        }
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 10)

                    // Dynamic sections based on user customization
                    ForEach(appState.visibleDashboardSections) { section in
                        dashboardSection(section)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            ))
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppTheme.paddingXl)
                .animation(.easeInOut(duration: 0.3), value: appState.visibleDashboardSections)
                .animation(.easeInOut(duration: 0.25), value: appState.collapsedDashboardSections)
            }

            // Customizer overlay
            if appState.showDashboardCustomizer {
                DashboardCustomizerOverlay()
                    .environmentObject(appState)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func dashboardSection(_ section: DashboardSection) -> some View {
        switch section {
        case .gateway:
            CollapsibleSection(section: .gateway) {
                gatewayContent
            }
            .frame(maxWidth: 800)

        case .stats:
            CollapsibleSection(section: .stats) {
                statsContent
            }
            .frame(maxWidth: 800)

        case .spending:
            CollapsibleSection(section: .spending) {
                spendingContent
            }
            .frame(maxWidth: 800)

        case .tokenStats:
            CollapsibleSection(section: .tokenStats) {
                TokenStatsSection(conversations: appState.conversations)
            }
            .frame(maxWidth: 800)

        case .analytics:
            CollapsibleSection(section: .analytics) {
                AnalyticsSectionView(conversations: appState.conversations, agents: appState.agents)
            }
            .frame(maxWidth: 800)

        case .chatInsights:
            CollapsibleSection(section: .chatInsights) {
                ChatInsightsSection(conversations: appState.conversations)
            }
            .frame(maxWidth: 800)

        case .recentActivity:
            CollapsibleSection(section: .recentActivity) {
                recentActivityContent
            }

        case .systemHealth:
            CollapsibleSection(section: .systemHealth) {
                systemHealthContent
            }
        }
    }

    // MARK: - Section Content

    private var gatewayContent: some View {
        GlassCard {
            HStack(spacing: 14) {
                Circle()
                    .fill(appState.gatewayRunning ? AppTheme.success : AppTheme.error)
                    .frame(width: 10, height: 10)
                    .shadow(color: appState.gatewayRunning ? AppTheme.success.opacity(0.6) : .clear, radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gateway")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(appState.gatewayRunning
                         ? "Running" + (appState.gatewayPID != nil ? " (PID \(appState.gatewayPID!))" : "")
                         : "Stopped")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                Button(action: { appState.toggleGateway() }) {
                    HStack(spacing: 6) {
                        Image(systemName: appState.gatewayRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 10))
                        Text(appState.gatewayRunning ? "Stop" : "Start")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(appState.gatewayRunning ? AppTheme.error : AppTheme.success)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        (appState.gatewayRunning ? AppTheme.error : AppTheme.success).opacity(0.12)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                (appState.gatewayRunning ? AppTheme.error : AppTheme.success).opacity(0.3),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.gatewayRunning ? "Stop gateway" : "Start gateway")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gateway status")
    }

    private var statsContent: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14),
        ], spacing: 14) {
            StatCard(
                icon: "dollarsign.circle", label: "Cost today",
                value: String(format: "$%.2f", appState.costToday),
                color: appState.config.spendingLimits.dailyUSD > 0 && appState.costToday / appState.config.spendingLimits.dailyUSD > 0.7
                    ? AppTheme.warning : AppTheme.accent,
                progress: appState.config.spendingLimits.dailyUSD > 0
                    ? appState.costToday / appState.config.spendingLimits.dailyUSD : nil
            )
            StatCard(
                icon: "cpu", label: "Tokens today",
                value: formatNumber(appState.tokensToday),
                color: AppTheme.accent
            )
            StatCard(
                icon: "bubble.left.and.bubble.right", label: "Conversations",
                value: "\(appState.conversations.count)",
                color: Color(red: 80/255, green: 120/255, blue: 200/255)
            )
            StatCard(
                icon: "person.3", label: "Agents",
                value: "\(appState.agents.count)",
                color: Color(red: 200/255, green: 80/255, blue: 200/255)
            )
        }
    }

    private var spendingContent: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Monthly Spending", icon: "chart.bar")
                    Spacer()
                    Text(String(format: "$%.2f / $%.0f", appState.costMonth, appState.config.spendingLimits.monthlyUSD))
                        .font(AppTheme.fontMono)
                        .foregroundColor(AppTheme.textSecondary)
                }

                let progress = appState.config.spendingLimits.monthlyUSD > 0
                    ? min(appState.costMonth / appState.config.spendingLimits.monthlyUSD, 1.0) : 0
                ProgressBar(progress: progress,
                            color: progress > 0.7 ? AppTheme.warning : AppTheme.accent)
                    .frame(height: 6)
            }
        }
    }

    private var recentActivityContent: some View {
        HStack(alignment: .top, spacing: AppTheme.paddingLg) {
            // Recent Conversations
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Recent Conversations", icon: "clock.arrow.circlepath")
                    Spacer()
                    if !appState.conversations.isEmpty {
                        Button(action: { appState.selectedTab = .chat }) {
                            Text("View all")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if appState.conversations.isEmpty {
                    GlassCard {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundColor(AppTheme.textMuted)
                            Text("No conversations yet")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                        }
                    }
                } else {
                    ForEach(appState.conversations.prefix(5)) { conv in
                        Button(action: { appState.openConversation(conv) }) {
                            HoverGlassCard {
                                HStack(spacing: 12) {
                                    if let agent = conv.agentName {
                                        GhostIcon(size: 20, animate: false, tint: agentColor(agent))
                                    } else {
                                        Image(systemName: "bubble.left")
                                            .font(.system(size: 14))
                                            .foregroundColor(AppTheme.textMuted)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(conv.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(conv.preview)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(relativeTime(conv.createdAt))
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textMuted)
                                        Text("\(conv.messages.count) msgs")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.textMuted)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: Active Tasks + Agents
            VStack(alignment: .leading, spacing: 20) {
                // Active Tasks
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(title: "Active Tasks", icon: "clock.fill")
                        Spacer()
                        Button(action: { appState.selectedTab = .tasks }) {
                            Text("View all")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.tasks.filter({ $0.enabled }).isEmpty {
                        GlassCard {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(AppTheme.textMuted)
                                Text("No active tasks")
                                    .font(AppTheme.fontBody)
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                            }
                        }
                    } else {
                        ForEach(appState.tasks.filter { $0.enabled }.prefix(3)) { task in
                            MiniTaskRow(task: task) {
                                appState.selectedTab = .tasks
                            }
                        }
                    }
                }

                // Agents preview
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(title: "Agents", icon: "person.3.fill")
                        Spacer()
                        Button(action: { appState.selectedTab = .agents }) {
                            Text("View all")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.agents.isEmpty {
                        GlassCard {
                            HStack {
                                Image(systemName: "person.3")
                                    .foregroundColor(AppTheme.textMuted)
                                Text("No agents configured")
                                    .font(AppTheme.fontBody)
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                            }
                        }
                    } else {
                        ForEach(appState.agents.prefix(4)) { agent in
                            AgentPill(agent: agent)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var systemHealthContent: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "System", icon: "server.rack")

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 10) {
                    SystemItem(label: "osai binary", status: FileManager.default.isExecutableFile(atPath: "/usr/local/bin/osai"))
                    SystemItem(label: "Gateway", status: appState.gatewayRunning)
                    SystemItem(label: "Config", status: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.desktop-agent/config.json"))
                }
            }
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Collapsible Section Wrapper

struct CollapsibleSection<Content: View>: View {
    @EnvironmentObject var appState: AppState
    let section: DashboardSection
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsible header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    appState.toggleSectionCollapsed(section)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                        .rotationEffect(.degrees(appState.isSectionCollapsed(section) ? 0 : 90))

                    Image(systemName: section.icon)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accent)

                    Text(section.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)

                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.displayName), \(appState.isSectionCollapsed(section) ? "collapsed" : "expanded")")
            .accessibilityHint("Double tap to \(appState.isSectionCollapsed(section) ? "expand" : "collapse")")

            if !appState.isSectionCollapsed(section) {
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Dashboard Customizer Overlay

struct DashboardCustomizerOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredSection: DashboardSection?

    var body: some View {
        HStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.accent)

                    Text("Customize Dashboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appState.showDashboardCustomizer = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(6)
                            .background(AppTheme.bgCard.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()
                    .background(AppTheme.borderGlass)

                // Section list
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        // Visible sections (ordered)
                        ForEach(Array(appState.visibleDashboardSections.enumerated()), id: \.element) { index, section in
                            customizerRow(
                                section: section,
                                isVisible: true,
                                canMoveUp: index > 0,
                                canMoveDown: index < appState.visibleDashboardSections.count - 1
                            )
                        }

                        // Hidden sections
                        let hiddenSections = DashboardSection.allCases.filter { !appState.visibleDashboardSections.contains($0) }
                        if !hiddenSections.isEmpty {
                            HStack {
                                Text("Hidden")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(AppTheme.textMuted)
                                    .textCase(.uppercase)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                            ForEach(hiddenSections) { section in
                                customizerRow(
                                    section: section,
                                    isVisible: false,
                                    canMoveUp: false,
                                    canMoveDown: false
                                )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Divider()
                    .background(AppTheme.borderGlass)

                // Reset button
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.resetDashboardSections()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                            Text("Reset to Default")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.bgCard.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.borderGlass, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .frame(width: 300)
            .background(.ultraThinMaterial)
            .background(AppTheme.bgPrimary.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.borderGlass, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: -4, y: 4)
            .padding(.trailing, 20)
            .padding(.top, 80)
            .frame(maxHeight: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    @ViewBuilder
    private func customizerRow(section: DashboardSection, isVisible: Bool, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        HStack(spacing: 10) {
            // Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.toggleSectionVisibility(section)
                }
            }) {
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isVisible ? AppTheme.accent : AppTheme.textMuted)
            }
            .buttonStyle(.plain)

            // Icon and name
            Image(systemName: section.icon)
                .font(.system(size: 12))
                .foregroundColor(isVisible ? AppTheme.accent : AppTheme.textMuted)
                .frame(width: 18)

            Text(section.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isVisible ? AppTheme.textPrimary : AppTheme.textMuted)

            Spacer()

            // Reorder buttons (only for visible sections)
            if isVisible {
                HStack(spacing: 4) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.moveSectionUp(section)
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(canMoveUp ? AppTheme.textSecondary : AppTheme.textMuted.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .background(canMoveUp ? AppTheme.bgCard.opacity(0.5) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveUp)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.moveSectionDown(section)
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(canMoveDown ? AppTheme.textSecondary : AppTheme.textMuted.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .background(canMoveDown ? AppTheme.bgCard.opacity(0.5) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveDown)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(hoveredSection == section ? AppTheme.bgCard.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered in
            hoveredSection = isHovered ? section : nil
        }
    }
}

// MARK: - Components

struct QuickAction: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isHovered ? AppTheme.accent : AppTheme.textSecondary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isHovered ? AppTheme.textPrimary : AppTheme.textMuted)
            }
            .frame(width: 80, height: 54)
            .background(isHovered ? AppTheme.accent.opacity(0.08) : AppTheme.bgCard.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Double tap to navigate")
        .onHover { isHovered = $0 }
    }
}

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = AppTheme.accent
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textPrimary)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textMuted)

            if let progress = progress {
                ProgressBar(progress: min(progress, 1.0), color: color)
                    .frame(height: 4)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.borderGlass, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityValue(progress != nil ? "\(Int((progress ?? 0) * 100)) percent of limit" : "")
    }
}

struct ProgressBar: View {
    let progress: Double
    var color: Color = AppTheme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.bgPrimary.opacity(0.5))

                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * progress)
            }
        }
    }
}

struct MiniTaskRow: View {
    let task: TaskInfo
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(task.enabled ? AppTheme.success : AppTheme.textMuted)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.id)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(task.schedule.displayLabel)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textMuted)
                }

                Spacer()

                Text("\(task.runCount)x")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)

                if let delivery = task.delivery {
                    Image(systemName: delivery.icon)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .padding(10)
            .background(isHovered ? AppTheme.bgCard.opacity(0.5) : AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.borderGlass, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task: \(task.id)")
        .accessibilityValue("\(task.schedule.displayLabel), \(task.runCount) runs")
        .accessibilityHint("Double tap to view tasks")
        .onHover { isHovered = $0 }
    }
}

struct SystemItem: View {
    let label: String
    let status: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status ? AppTheme.success : AppTheme.error)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(status ? "OK" : "Not available")")
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.accent)
            Text(title)
                .font(AppTheme.fontHeadline)
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

struct AgentPill: View {
    let agent: AgentInfo
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            GhostIcon(size: 24, animate: false, tint: agentColor(agent.name))

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(agent.displayModel)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: agent.backendIcon)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.accent)
                .padding(4)
                .background(AppTheme.accent.opacity(0.1))
                .clipShape(Circle())
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .background(isHovered ? AppTheme.bgCard.opacity(0.6) : AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent: \(agent.name), model: \(agent.displayModel)")
    }
}

// MARK: - Analytics Section

struct AnalyticsSectionView: View {
    let conversations: [Conversation]
    let agents: [AgentInfo]

    var body: some View {
        VStack(spacing: AppTheme.paddingLg) {
            // Quick stats row
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Quick Stats", icon: "chart.bar.xaxis")

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                    ], spacing: 14) {
                        QuickStatItem(
                            label: "Total Conversations",
                            value: "\(conversations.count)",
                            icon: "bubble.left.and.bubble.right"
                        )
                        QuickStatItem(
                            label: "Total Messages",
                            value: formatLargeNumber(totalMessages),
                            icon: "text.bubble"
                        )
                        QuickStatItem(
                            label: "Most Active Day",
                            value: mostActiveDay,
                            icon: "calendar.badge.clock"
                        )
                        QuickStatItem(
                            label: "Avg Msgs / Conv",
                            value: avgMessagesPerConversation,
                            icon: "divide"
                        )
                    }
                }
            }

            // Weekly activity chart
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Weekly Activity", icon: "chart.bar.fill")

                    WeeklyBarChart(dailyCounts: weeklyMessageCounts)
                        .frame(height: 120)
                }
            }

            // Top agents
            if !topAgentData.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Top Agents", icon: "person.3.sequence.fill")

                        ForEach(topAgentData, id: \.name) { entry in
                            TopAgentRow(
                                name: entry.name,
                                count: entry.count,
                                maxCount: topAgentData.first?.count ?? 1,
                                color: agentColor(entry.name)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed data

    private var totalMessages: Int {
        conversations.reduce(0) { $0 + $1.messages.count }
    }

    private var mostActiveDay: String {
        let counts = weeklyMessageCounts
        guard let maxEntry = counts.max(by: { $0.count < $1.count }), maxEntry.count > 0 else {
            return "--"
        }
        return maxEntry.label
    }

    private var avgMessagesPerConversation: String {
        guard !conversations.isEmpty else { return "0" }
        let avg = Double(totalMessages) / Double(conversations.count)
        if avg == avg.rounded() {
            return "\(Int(avg))"
        }
        return String(format: "%.1f", avg)
    }

    /// Messages per day for the last 7 days, ordered Mon-Sun ending today.
    var weeklyMessageCounts: [DayCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build array of last 7 days
        var days: [DayCount] = []
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        for offset in stride(from: -6, through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let label = dayFormatter.string(from: date)
            days.append(DayCount(label: label, date: date, count: 0))
        }

        // Count messages per day
        for conv in conversations {
            for msg in conv.messages {
                let msgDay = calendar.startOfDay(for: msg.timestamp)
                if let idx = days.firstIndex(where: { $0.date == msgDay }) {
                    days[idx].count += 1
                }
            }
        }

        return days
    }

    /// Agent usage ranked by conversation count.
    var topAgentData: [AgentCount] {
        var counts: [String: Int] = [:]
        for conv in conversations {
            if let name = conv.agentName {
                counts[name, default: 0] += 1
            }
        }
        return counts
            .map { AgentCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    private func formatLargeNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct DayCount: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    var count: Int
}

struct AgentCount {
    let name: String
    let count: Int
}

// MARK: - Weekly Bar Chart

struct WeeklyBarChart: View {
    let dailyCounts: [DayCount]

    var body: some View {
        let maxCount = max(dailyCounts.map(\.count).max() ?? 1, 1)

        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(dailyCounts) { day in
                    VStack(spacing: 6) {
                        if day.count > 0 {
                            Text("\(day.count)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                day.count > 0
                                    ? AppTheme.accent
                                    : AppTheme.textMuted.opacity(0.2)
                            )
                            .frame(
                                height: day.count > 0
                                    ? max(CGFloat(day.count) / CGFloat(maxCount) * (geo.size.height - 36), 6)
                                    : 6
                            )

                        Text(day.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Quick Stat Item

struct QuickStatItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.accent)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textPrimary)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Top Agent Row

struct TopAgentRow: View {
    let name: String
    let count: Int
    let maxCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            GhostIcon(size: 20, animate: false, tint: color)

            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.bgPrimary.opacity(0.5))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.7))
                        .frame(width: max(CGFloat(count) / CGFloat(maxCount) * geo.size.width, 4))
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent \(name): \(count) conversations")
    }
}

// MARK: - Token & Cost Statistics Section

struct TokenStatsSection: View {
    let conversations: [Conversation]

    var body: some View {
        VStack(spacing: AppTheme.paddingLg) {
            // 1. Session stats card
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Token & Cost Breakdown", icon: "number.circle")

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                    ], spacing: 14) {
                        QuickStatItem(
                            label: "Input Tokens",
                            value: formatLargeNumber(totalInputTokens),
                            icon: "arrow.down.circle"
                        )
                        QuickStatItem(
                            label: "Output Tokens",
                            value: formatLargeNumber(totalOutputTokens),
                            icon: "arrow.up.circle"
                        )
                        QuickStatItem(
                            label: "Total Cost",
                            value: formatCost(totalEstimatedCost),
                            icon: "dollarsign.circle"
                        )
                        QuickStatItem(
                            label: "Messages Sent",
                            value: formatLargeNumber(totalUserMessages),
                            icon: "paperplane"
                        )
                    }

                    // Cost rate breakdown
                    HStack(spacing: 16) {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 6, height: 6)
                            Text("Input $3/MTok")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 200/255, green: 80/255, blue: 200/255))
                                .frame(width: 6, height: 6)
                            Text("Output $15/MTok")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        Text("(Claude Sonnet)")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                    }
                }
            }

            // 2. Per-conversation breakdown
            if !conversationsBySpend.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionHeader(title: "Cost by Conversation", icon: "list.number")
                            Spacer()
                            Text("\(conversationsBySpend.count) conversation\(conversationsBySpend.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textMuted)
                        }

                        ForEach(conversationsBySpend.prefix(8), id: \.id) { conv in
                            ConversationCostRow(
                                title: conv.title,
                                inputTokens: conv.totalInputTokens,
                                outputTokens: conv.totalOutputTokens,
                                cost: conv.estimatedCost,
                                maxCost: conversationsBySpend.first?.estimatedCost ?? 0.01
                            )
                        }

                        if conversationsBySpend.count > 8 {
                            HStack {
                                Spacer()
                                Text("+\(conversationsBySpend.count - 8) more")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textMuted)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }

            // 3. Daily token usage chart (last 7 days)
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionHeader(title: "Daily Token Usage", icon: "chart.bar.fill")
                        Spacer()
                        Text("Last 7 days")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                    }

                    DailyTokenBarChart(dailyData: dailyTokenUsage)
                        .frame(height: 140)
                }
            }

            // 4. Cost projection
            if totalEstimatedCost > 0 {
                GlassCard {
                    HStack(spacing: 14) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.accent)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cost Projection")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Based on average daily usage over the last \(daysWithUsage) day\(daysWithUsage == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textMuted)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Est. monthly")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                            Text(formatCost(projectedMonthlyCost))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(projectedMonthlyCost > 50 ? AppTheme.warning : AppTheme.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed properties

    private var totalInputTokens: Int {
        conversations.reduce(0) { $0 + $1.totalInputTokens }
    }

    private var totalOutputTokens: Int {
        conversations.reduce(0) { $0 + $1.totalOutputTokens }
    }

    private var totalEstimatedCost: Double {
        conversations.reduce(0.0) { $0 + $1.estimatedCost }
    }

    private var totalUserMessages: Int {
        conversations.reduce(0) { $0 + $1.messages.filter { $0.role == .user }.count }
    }

    /// Conversations sorted by cost descending, only those with tokens
    private var conversationsBySpend: [Conversation] {
        conversations
            .filter { $0.totalTokens > 0 }
            .sorted { $0.estimatedCost > $1.estimatedCost }
    }

    /// Token usage per day for the last 7 days
    var dailyTokenUsage: [DailyTokenData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var days: [DailyTokenData] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let label = dayFormatter.string(from: date)
            days.append(DailyTokenData(label: label, date: date, inputTokens: 0, outputTokens: 0, cost: 0))
        }

        for conv in conversations {
            let convDay = calendar.startOfDay(for: conv.createdAt)
            if let idx = days.firstIndex(where: { $0.date == convDay }) {
                days[idx].inputTokens += conv.totalInputTokens
                days[idx].outputTokens += conv.totalOutputTokens
                days[idx].cost += conv.estimatedCost
            }
        }

        return days
    }

    /// Number of days that actually have usage data (for projection accuracy)
    private var daysWithUsage: Int {
        max(dailyTokenUsage.filter { $0.totalTokens > 0 }.count, 1)
    }

    /// Projected monthly cost based on average daily spend
    private var projectedMonthlyCost: Double {
        let totalCostInWindow = dailyTokenUsage.reduce(0.0) { $0 + $1.cost }
        let avgDaily = totalCostInWindow / Double(daysWithUsage)
        return avgDaily * 30.0
    }

    private func formatLargeNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 1.0 {
            return String(format: "$%.2f", cost)
        }
        return String(format: "$%.4f", cost)
    }
}

// MARK: - Daily Token Data

struct DailyTokenData: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    var inputTokens: Int
    var outputTokens: Int
    var cost: Double

    var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - Daily Token Bar Chart

struct DailyTokenBarChart: View {
    let dailyData: [DailyTokenData]

    private let inputColor = AppTheme.accent
    private let outputColor = Color(red: 200/255, green: 80/255, blue: 200/255)

    var body: some View {
        let maxTokens = max(dailyData.map(\.totalTokens).max() ?? 1, 1)

        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(dailyData) { day in
                        VStack(spacing: 4) {
                            if day.totalTokens > 0 {
                                Text(formatCompact(day.totalTokens))
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppTheme.textSecondary)
                            }

                            // Stacked bar: input on bottom, output on top
                            let barHeight = day.totalTokens > 0
                                ? max(CGFloat(day.totalTokens) / CGFloat(maxTokens) * (geo.size.height - 44), 6)
                                : CGFloat(6)
                            let inputRatio = day.totalTokens > 0
                                ? CGFloat(day.inputTokens) / CGFloat(day.totalTokens)
                                : CGFloat(0.5)

                            VStack(spacing: 0) {
                                // Output portion (top)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day.totalTokens > 0 ? outputColor : AppTheme.textMuted.opacity(0.2))
                                    .frame(height: barHeight * (1 - inputRatio))

                                // Input portion (bottom)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day.totalTokens > 0 ? inputColor : AppTheme.textMuted.opacity(0.2))
                                    .frame(height: barHeight * inputRatio)
                            }
                            .frame(height: barHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(day.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Legend
                HStack(spacing: 16) {
                    Spacer()
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(inputColor)
                            .frame(width: 10, height: 6)
                        Text("Input")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(outputColor)
                            .frame(width: 10, height: 6)
                        Text("Output")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
    }

    private func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Conversation Cost Row

struct ConversationCostRow: View {
    let title: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
    let maxCost: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Text("\(formatCompact(inputTokens))in")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                    Text("\(formatCompact(outputTokens))out")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(red: 200/255, green: 80/255, blue: 200/255))
                }

                Text(formatCost(cost))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 60, alignment: .trailing)
            }

            // Cost bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.bgPrimary.opacity(0.5))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.accent.opacity(0.6))
                        .frame(width: maxCost > 0 ? max(CGFloat(cost) / CGFloat(maxCost) * geo.size.width, 2) : 2)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(formatCost(cost))")
    }

    private func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM ", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK ", Double(n) / 1_000) }
        return "\(n) "
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 1.0 {
            return String(format: "$%.2f", cost)
        }
        return String(format: "$%.4f", cost)
    }
}

// MARK: - Chat Insights Section

struct ChatInsightsSection: View {
    let conversations: [Conversation]

    var body: some View {
        VStack(spacing: AppTheme.paddingLg) {
            // 1. Top stats row
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Chat Insights", icon: "lightbulb")

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                    ], spacing: 14) {
                        QuickStatItem(
                            label: "Conversations",
                            value: "\(conversations.count)",
                            icon: "bubble.left.and.bubble.right"
                        )
                        QuickStatItem(
                            label: "Messages Sent",
                            value: formatLargeNumber(insightTotalMessages),
                            icon: "text.bubble"
                        )
                        QuickStatItem(
                            label: "Avg / Conv",
                            value: insightAvgMessages,
                            icon: "divide"
                        )
                        QuickStatItem(
                            label: "Longest Conv",
                            value: "\(insightLongestConversation)",
                            icon: "arrow.up.to.line"
                        )
                        QuickStatItem(
                            label: "Most Active Day",
                            value: insightMostActiveDay,
                            icon: "calendar.badge.clock"
                        )
                    }
                }
            }

            // 2. Activity heatmap (last 30 days)
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionHeader(title: "Activity Heatmap", icon: "square.grid.3x3.fill")
                        Spacer()
                        Text("Last 30 days")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                    }

                    ActivityHeatmap(heatmapData: heatmapGrid)
                }
            }

            // 3. Most used agents (horizontal bar chart)
            if !insightAgentUsage.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Most Used Agents", icon: "person.3.sequence.fill")

                        ForEach(insightAgentUsage, id: \.name) { entry in
                            AgentBarRow(
                                name: entry.name,
                                count: entry.count,
                                maxCount: insightAgentUsage.first?.count ?? 1,
                                color: agentColor(entry.name)
                            )
                        }
                    }
                }
            }

            // 4. Conversation length distribution
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Conversation Length Distribution", icon: "chart.bar.xaxis.ascending")

                    ConversationLengthHistogram(buckets: insightLengthBuckets)
                        .frame(height: 120)
                }
            }
        }
    }

    // MARK: - Computed properties

    private var insightTotalMessages: Int {
        conversations.reduce(0) { $0 + $1.messages.count }
    }

    private var insightAvgMessages: String {
        guard !conversations.isEmpty else { return "0" }
        let avg = Double(insightTotalMessages) / Double(conversations.count)
        if avg == avg.rounded() {
            return "\(Int(avg))"
        }
        return String(format: "%.1f", avg)
    }

    private var insightLongestConversation: Int {
        conversations.map(\.messages.count).max() ?? 0
    }

    private var insightMostActiveDay: String {
        guard !conversations.isEmpty else { return "--" }
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var dayCounts: [Int: Int] = [:] // weekday number -> count
        for conv in conversations {
            for msg in conv.messages {
                let weekday = calendar.component(.weekday, from: msg.timestamp)
                dayCounts[weekday, default: 0] += 1
            }
        }

        guard let topDay = dayCounts.max(by: { $0.value < $1.value }) else { return "--" }
        // Convert weekday number to name
        let names = calendar.shortWeekdaySymbols
        let index = topDay.key - 1 // weekday is 1-based
        guard index >= 0, index < names.count else { return "--" }
        return names[index]
    }

    /// Agent usage ranked by conversation count
    private var insightAgentUsage: [AgentCount] {
        var counts: [String: Int] = [:]
        for conv in conversations {
            if let name = conv.agentName {
                counts[name, default: 0] += 1
            }
        }
        return counts
            .map { AgentCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(6)
            .map { $0 }
    }

    /// Heatmap grid data: 30 days, grouped into weeks (7 rows x ~5 columns)
    var heatmapGrid: [HeatmapDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d (EEE)"

        // Count messages per day across all conversations
        var messageCounts: [Date: Int] = [:]
        for conv in conversations {
            for msg in conv.messages {
                let day = calendar.startOfDay(for: msg.timestamp)
                messageCounts[day, default: 0] += 1
            }
        }

        var days: [HeatmapDay] = []
        for offset in stride(from: -29, through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let count = messageCounts[date] ?? 0
            let weekday = calendar.component(.weekday, from: date) // 1=Sun, 7=Sat
            let label = dateFormatter.string(from: date)
            days.append(HeatmapDay(date: date, count: count, weekday: weekday, label: label))
        }
        return days
    }

    /// Conversation length distribution buckets
    var insightLengthBuckets: [LengthBucket] {
        var b1 = 0, b2 = 0, b3 = 0, b4 = 0
        for conv in conversations {
            let c = conv.messages.count
            if c <= 5 { b1 += 1 }
            else if c <= 10 { b2 += 1 }
            else if c <= 20 { b3 += 1 }
            else { b4 += 1 }
        }
        return [
            LengthBucket(label: "1-5", count: b1),
            LengthBucket(label: "6-10", count: b2),
            LengthBucket(label: "11-20", count: b3),
            LengthBucket(label: "20+", count: b4),
        ]
    }

    private func formatLargeNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Heatmap Data

struct HeatmapDay: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let weekday: Int // 1=Sun..7=Sat
    let label: String
}

// MARK: - Activity Heatmap View

struct ActivityHeatmap: View {
    let heatmapData: [HeatmapDay]

    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 3

    var body: some View {
        let grid = buildGrid()
        let maxCount = max(heatmapData.map(\.count).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 4) {
            // Day labels + grid
            HStack(alignment: .top, spacing: 4) {
                // Day-of-week labels
                VStack(spacing: cellSpacing) {
                    ForEach(dayLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                            .frame(width: 20, height: cellSize)
                    }
                }

                // Grid columns (weeks)
                HStack(spacing: cellSpacing) {
                    ForEach(0..<grid.count, id: \.self) { col in
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<grid[col].count, id: \.self) { row in
                                if let day = grid[col][row] {
                                    heatmapCell(day: day, maxCount: maxCount)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.clear)
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textMuted)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapColor(level: level, maxLevel: 4))
                        .frame(width: 10, height: 10)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textMuted)
            }
            .padding(.top, 4)
        }
    }

    private var dayLabels: [String] {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    /// Build a column-major grid: each column is a week, each row is a day of week (Sun=0..Sat=6)
    private func buildGrid() -> [[HeatmapDay?]] {
        guard !heatmapData.isEmpty else { return [] }

        // Group days into weekly columns
        var columns: [[HeatmapDay?]] = []
        var currentColumn: [HeatmapDay?] = Array(repeating: nil, count: 7)

        for day in heatmapData {
            let row = day.weekday - 1 // 0-based row index
            // If we already have a value in this row, start a new column
            if currentColumn[row] != nil {
                columns.append(currentColumn)
                currentColumn = Array(repeating: nil, count: 7)
            }
            currentColumn[row] = day
        }
        // Append the last column
        if currentColumn.contains(where: { $0 != nil }) {
            columns.append(currentColumn)
        }

        return columns
    }

    @ViewBuilder
    private func heatmapCell(day: HeatmapDay, maxCount: Int) -> some View {
        let level = day.count == 0 ? 0 : min(Int(ceil(Double(day.count) / Double(maxCount) * 4.0)), 4)

        RoundedRectangle(cornerRadius: 2)
            .fill(heatmapColor(level: level, maxLevel: 4))
            .frame(width: cellSize, height: cellSize)
            .help("\(day.label): \(day.count) message\(day.count == 1 ? "" : "s")")
    }

    private func heatmapColor(level: Int, maxLevel: Int) -> Color {
        switch level {
        case 0:
            return AppTheme.textMuted.opacity(0.15)
        case 1:
            return AppTheme.accent.opacity(0.25)
        case 2:
            return AppTheme.accent.opacity(0.5)
        case 3:
            return AppTheme.accent.opacity(0.75)
        default:
            return AppTheme.accent
        }
    }
}

// MARK: - Agent Bar Row (horizontal bar)

struct AgentBarRow: View {
    let name: String
    let count: Int
    let maxCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            GhostIcon(size: 20, animate: false, tint: color)

            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.bgPrimary.opacity(0.5))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.7))
                        .frame(width: max(CGFloat(count) / CGFloat(max(maxCount, 1)) * geo.size.width, 4))
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent \(name): \(count) conversations")
    }
}

// MARK: - Conversation Length Distribution

struct LengthBucket: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
}

struct ConversationLengthHistogram: View {
    let buckets: [LengthBucket]

    var body: some View {
        let maxCount = max(buckets.map(\.count).max() ?? 1, 1)

        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(buckets) { bucket in
                    VStack(spacing: 6) {
                        if bucket.count > 0 {
                            Text("\(bucket.count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                bucket.count > 0
                                    ? AppTheme.accent
                                    : AppTheme.textMuted.opacity(0.2)
                            )
                            .frame(
                                height: bucket.count > 0
                                    ? max(CGFloat(bucket.count) / CGFloat(maxCount) * (geo.size.height - 40), 6)
                                    : 6
                            )

                        Text(bucket.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)

                        Text("msgs")
                            .font(.system(size: 8))
                            .foregroundColor(AppTheme.textMuted.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversation length distribution")
    }
}

func agentColor(_ name: String) -> Color {
    let colors: [Color] = [
        AppTheme.accent,
        Color(red: 200/255, green: 80/255, blue: 200/255),
        Color(red: 80/255, green: 200/255, blue: 120/255),
        Color(red: 200/255, green: 160/255, blue: 80/255),
        Color(red: 80/255, green: 120/255, blue: 200/255),
        Color(red: 200/255, green: 80/255, blue: 100/255),
    ]
    let hash = abs(name.hashValue)
    return colors[hash % colors.count]
}
