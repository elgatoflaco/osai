import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var taskInput = ""
    @State private var selectedTemplateCategory: TemplateCategory = .all
    @State private var templateSearchQuery = ""
    @State private var showTemplateEditor = false
    @State private var editingTemplate: ConversationTemplate?
    @State private var templateToDelete: ConversationTemplate?
    @State private var showDeleteConfirmation = false
    @State private var gatewayStartedAt: Date? = nil
    @State private var gatewayStoppedAt: Date? = nil
    @State private var gatewayUptimeTimer: Timer? = nil
    @State private var gatewayUptimeString: String = "—"
    @State private var gatewayRequestCount: Int = 0
    @State private var gatewayIsRestarting: Bool = false
    @State private var gatewayStatusPulse: Bool = false

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
        case .quickStart:
            CollapsibleSection(section: .quickStart) {
                quickStartContent
            }
            .frame(maxWidth: 800)

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

        case .performance:
            CollapsibleSection(section: .performance) {
                PerformanceSection()
            }
            .frame(maxWidth: 800)

        case .recentConversations:
            CollapsibleSection(section: .recentConversations) {
                recentConversationsContent
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

        case .systemStatus:
            CollapsibleSection(section: .systemStatus) {
                SystemStatusContent()
                    .environmentObject(appState)
            }
            .frame(maxWidth: 800)

        case .activity:
            CollapsibleSection(section: .activity) {
                ActivityStreakContent()
                    .environmentObject(appState)
            }
            .frame(maxWidth: 800)

        case .modelUsage:
            CollapsibleSection(section: .modelUsage) {
                ModelUsageSection()
                    .environmentObject(appState)
            }
            .frame(maxWidth: 800)

        case .tips:
            CollapsibleSection(section: .tips) {
                TipsAndTricksContent()
                    .environmentObject(appState)
            }
            .frame(maxWidth: 800)

        case .quickActions:
            CollapsibleSection(section: .quickActions) {
                QuickActionsContent()
                    .environmentObject(appState)
            }
            .frame(maxWidth: 800)
        }
    }

    // MARK: - Section Content

    private var quickStartContent: some View {
        let columns = [
            GridItem(.flexible(), spacing: AppTheme.paddingMd),
            GridItem(.flexible(), spacing: AppTheme.paddingMd),
        ]
        let filteredTemplates = appState.templates(for: selectedTemplateCategory, searchQuery: templateSearchQuery)

        return VStack(spacing: 12) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textMuted)
                TextField("Search templates...", text: $templateSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textPrimary)
                if !templateSearchQuery.isEmpty {
                    Button(action: { templateSearchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.borderGlass, lineWidth: 0.5)
            )

            // Category filter tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TemplateCategory.allCases) { category in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTemplateCategory = category
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 10))
                                Text(category.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(selectedTemplateCategory == category ? AppTheme.accent : AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedTemplateCategory == category ? AppTheme.accent.opacity(0.12) : AppTheme.bgCard.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selectedTemplateCategory == category ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Template grid
            LazyVGrid(columns: columns, spacing: AppTheme.paddingMd) {
                // Create Template card
                Button(action: {
                    editingTemplate = nil
                    showTemplateEditor = true
                }) {
                    GlassCard(padding: AppTheme.paddingMd) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Create Template")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                                Text("Add your own starter")
                                    .font(AppTheme.fontCaption)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)

                ForEach(filteredTemplates) { template in
                    Button(action: {
                        appState.startFromTemplate(template)
                    }) {
                        GlassCard(padding: AppTheme.paddingMd) {
                            HStack(spacing: 12) {
                                Image(systemName: template.icon)
                                    .font(.system(size: 22))
                                    .foregroundColor(AppTheme.accent)
                                    .frame(width: 36, height: 36)
                                    .background(AppTheme.accent.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text(template.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        if !template.isBuiltIn {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 8))
                                                .foregroundColor(AppTheme.textMuted)
                                        }
                                    }
                                    Text(template.description)
                                        .font(AppTheme.fontCaption)
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(template.category)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(AppTheme.textMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.bgCard.opacity(0.5))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !template.isBuiltIn {
                            Button(action: {
                                editingTemplate = template
                                showTemplateEditor = true
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        Button(action: {
                            appState.duplicateTemplate(template)
                        }) {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        if !template.isBuiltIn {
                            Divider()
                            Button(role: .destructive, action: {
                                templateToDelete = template
                                showDeleteConfirmation = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if filteredTemplates.isEmpty && !templateSearchQuery.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No templates match \"\(templateSearchQuery)\"")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showTemplateEditor) {
            TemplateEditorSheet(template: editingTemplate) { saved in
                appState.saveUserTemplate(saved)
            }
            .environmentObject(appState)
        }
        .alert("Delete Template", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let t = templateToDelete {
                    appState.deleteUserTemplate(id: t.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(templateToDelete?.name ?? "")\"? This cannot be undone.")
        }
    }

    private var gatewayStatusColor: Color {
        if gatewayIsRestarting { return AppTheme.warning }
        return appState.gatewayRunning ? AppTheme.success : AppTheme.error
    }

    private var gatewayContent: some View {
        GlassCard {
            VStack(spacing: 12) {
                // Top row: status LED, title, and controls
                HStack(spacing: 14) {
                    // Status LED with pulse animation
                    Circle()
                        .fill(gatewayStatusColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: gatewayStatusColor.opacity(0.6), radius: gatewayStatusPulse ? 6 : 2)
                        .scaleEffect(appState.gatewayRunning && gatewayStatusPulse ? 1.2 : 1.0)
                        .animation(
                            appState.gatewayRunning
                                ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                                : .default,
                            value: gatewayStatusPulse
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gateway")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(gatewayIsRestarting
                             ? "Restarting..."
                             : appState.gatewayRunning
                                ? "Running" + (appState.gatewayPID != nil ? " (PID \(appState.gatewayPID!))" : "")
                                : "Stopped")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()

                    // Restart button (only when running)
                    if appState.gatewayRunning && !gatewayIsRestarting {
                        Button(action: { restartGateway() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text("Restart")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(AppTheme.warning)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.warning.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.warning.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Restart gateway")
                    }

                    // Start/Stop button
                    Button(action: {
                        let wasRunning = appState.gatewayRunning
                        appState.toggleGateway()
                        if !wasRunning {
                            gatewayStartedAt = Date()
                            gatewayStoppedAt = nil
                            startUptimeTimer()
                        } else {
                            gatewayStoppedAt = Date()
                            stopUptimeTimer()
                        }
                    }) {
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
                    .disabled(gatewayIsRestarting)
                    .accessibilityLabel(appState.gatewayRunning ? "Stop gateway" : "Start gateway")
                }

                // Detail stats row
                HStack(spacing: 0) {
                    // Uptime
                    gatewayStatItem(
                        icon: "clock",
                        label: "Uptime",
                        value: appState.gatewayRunning ? gatewayUptimeString : "—"
                    )

                    Divider()
                        .frame(height: 24)
                        .background(AppTheme.textSecondary.opacity(0.2))

                    // Request count
                    gatewayStatItem(
                        icon: "arrow.left.arrow.right",
                        label: "Requests",
                        value: "\(gatewayRequestCount)"
                    )

                    Divider()
                        .frame(height: 24)
                        .background(AppTheme.textSecondary.opacity(0.2))

                    // Last event timestamp
                    gatewayStatItem(
                        icon: "calendar.badge.clock",
                        label: appState.gatewayRunning ? "Started" : "Stopped",
                        value: gatewayTimestampDisplay
                    )
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gateway status")
        .onAppear {
            gatewayStatusPulse = appState.gatewayRunning
            if appState.gatewayRunning && gatewayStartedAt == nil {
                gatewayStartedAt = Date()
                startUptimeTimer()
            }
        }
        .onChange(of: appState.gatewayRunning) { running in
            gatewayStatusPulse = running
            if running && gatewayStartedAt == nil {
                gatewayStartedAt = Date()
                startUptimeTimer()
            }
        }
    }

    private func gatewayStatItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var gatewayTimestampDisplay: String {
        let date = appState.gatewayRunning ? gatewayStartedAt : gatewayStoppedAt
        guard let date = date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func startUptimeTimer() {
        gatewayUptimeTimer?.invalidate()
        gatewayRequestCount = 0
        gatewayUptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let start = gatewayStartedAt else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let hours = elapsed / 3600
            let minutes = (elapsed % 3600) / 60
            let seconds = elapsed % 60
            if hours > 0 {
                gatewayUptimeString = String(format: "%dh %02dm %02ds", hours, minutes, seconds)
            } else if minutes > 0 {
                gatewayUptimeString = String(format: "%dm %02ds", minutes, seconds)
            } else {
                gatewayUptimeString = String(format: "%ds", seconds)
            }
            // Simulate request count growth while running
            if appState.gatewayRunning && Int.random(in: 0...2) == 0 {
                gatewayRequestCount += Int.random(in: 1...3)
            }
        }
    }

    private func stopUptimeTimer() {
        gatewayUptimeTimer?.invalidate()
        gatewayUptimeTimer = nil
        gatewayUptimeString = "—"
    }

    private func restartGateway() {
        gatewayIsRestarting = true
        appState.toggleGateway()
        gatewayStoppedAt = Date()
        stopUptimeTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            appState.toggleGateway()
            gatewayStartedAt = Date()
            gatewayRequestCount = 0
            startUptimeTimer()
            gatewayIsRestarting = false
        }
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
                color: appState.dailyBudget > 0 && appState.dailySpendingPercentage > 0.8
                    ? AppTheme.error : appState.dailySpendingPercentage > 0.6
                    ? AppTheme.warning : AppTheme.accent,
                progress: appState.dailyBudget > 0
                    ? appState.dailySpendingPercentage : nil
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
        VStack(spacing: 10) {
            // Daily budget bar
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionHeader(title: "Daily Budget", icon: "clock")
                        Spacer()
                        Text(String(format: "$%.2f / $%.2f", appState.costToday, appState.dailyBudget))
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    let dp = appState.dailyBudget > 0
                        ? min(appState.dailySpendingPercentage, 1.0) : 0
                    ProgressBar(progress: dp,
                                color: dp > 0.8 ? AppTheme.error : dp > 0.6 ? AppTheme.warning : AppTheme.success)
                        .frame(height: 6)
                }
            }

            // Monthly budget bar
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionHeader(title: "Monthly Budget", icon: "calendar")
                        Spacer()
                        Text(String(format: "$%.2f / $%.2f", appState.costMonth, appState.monthlyBudget))
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    let mp = appState.monthlyBudget > 0
                        ? min(appState.monthlySpendingPercentage, 1.0) : 0
                    ProgressBar(progress: mp,
                                color: mp > 0.8 ? AppTheme.error : mp > 0.6 ? AppTheme.warning : AppTheme.success)
                        .frame(height: 6)
                }
            }
        }
    }

    // MARK: - Recent Conversations

    private var recentConversationsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.recentConversationsForDashboard.isEmpty {
                GlassCard {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundColor(AppTheme.textMuted)
                        Text("No conversations yet. Start chatting!")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                    }
                }
            } else {
                ForEach(appState.recentConversationsForDashboard) { conv in
                    Button(action: { appState.openConversation(conv) }) {
                        HoverGlassCard {
                            HStack(spacing: 12) {
                                // Agent icon or default chat icon
                                if let agent = conv.agentName {
                                    GhostIcon(size: 24, animate: false, tint: agentColor(agent))
                                } else {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppTheme.accent.opacity(0.7))
                                        .frame(width: 24, height: 24)
                                }

                                // Title and preview
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conv.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(conv.preview)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                // Message count badge
                                Text("\(conv.messages.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.accent.opacity(0.12))
                                    .clipShape(Capsule())

                                // Time ago
                                Text(relativeTime(conv.lastUpdated))
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textMuted)
                                    .frame(minWidth: 40, alignment: .trailing)

                                // Continue button
                                Button(action: {
                                    appState.openConversation(conv)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 11))
                                        Text("Continue")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppTheme.accent.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // View all button
                if appState.conversations.count > 5 {
                    HStack {
                        Spacer()
                        Button(action: { appState.selectedTab = .chat }) {
                            HStack(spacing: 4) {
                                Text("View all conversations")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
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

// MARK: - System Status Widget

struct SystemStatusContent: View {
    @EnvironmentObject var appState: AppState
    @State private var stats: SystemStats?
    @State private var refreshTimer: Timer?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "System Status", icon: "cpu")
                    Spacer()
                    if stats != nil {
                        Button(action: { refreshStats() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Refresh system stats")
                    }
                }

                if let stats = stats {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ], spacing: 10) {
                        // CPU Usage
                        SystemStatCard(
                            icon: "cpu",
                            label: "CPU",
                            value: String(format: "%.1f%%", stats.cpuUsage),
                            progress: stats.cpuUsage / 100.0,
                            color: stats.cpuUsage > 80 ? AppTheme.error :
                                   stats.cpuUsage > 50 ? AppTheme.warning : AppTheme.success
                        )

                        // Memory Usage
                        SystemStatCard(
                            icon: "memorychip",
                            label: "Memory",
                            value: "\(formatBytes(stats.memoryUsed)) / \(formatBytes(stats.memoryTotal))",
                            progress: stats.memoryTotal > 0 ? Double(stats.memoryUsed) / Double(stats.memoryTotal) : 0,
                            color: memoryColor(used: stats.memoryUsed, total: stats.memoryTotal)
                        )

                        // Disk Space
                        SystemStatCard(
                            icon: "internaldrive",
                            label: "Disk",
                            value: "\(formatBytes(stats.diskUsed)) / \(formatBytes(stats.diskTotal))",
                            progress: stats.diskTotal > 0 ? Double(stats.diskUsed) / Double(stats.diskTotal) : 0,
                            color: diskColor(used: stats.diskUsed, total: stats.diskTotal)
                        )

                        // Uptime
                        SystemStatCard(
                            icon: "clock",
                            label: "Uptime",
                            value: formatUptime(stats.uptime),
                            progress: nil,
                            color: AppTheme.accent
                        )

                        // Process Count
                        SystemStatCard(
                            icon: "list.number",
                            label: "Processes",
                            value: "\(stats.processCount)",
                            progress: nil,
                            color: AppTheme.accent
                        )
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading system info...")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            refreshStats()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func refreshStats() {
        DispatchQueue.global(qos: .utility).async {
            let fetched = appState.fetchSystemStats()
            DispatchQueue.main.async {
                stats = fetched
                appState.systemStats = fetched
            }
        }
    }

    private func startTimer() {
        stopTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            refreshStats()
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 100 {
            return String(format: "%.0f GB", gb)
        } else if gb >= 10 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.2f GB", gb)
        }
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func memoryColor(used: UInt64, total: UInt64) -> Color {
        guard total > 0 else { return AppTheme.success }
        let ratio = Double(used) / Double(total)
        if ratio > 0.85 { return AppTheme.error }
        if ratio > 0.65 { return AppTheme.warning }
        return AppTheme.success
    }

    private func diskColor(used: UInt64, total: UInt64) -> Color {
        guard total > 0 else { return AppTheme.success }
        let ratio = Double(used) / Double(total)
        if ratio > 0.9 { return AppTheme.error }
        if ratio > 0.75 { return AppTheme.warning }
        return AppTheme.success
    }
}

struct SystemStatCard: View {
    let icon: String
    let label: String
    let value: String
    let progress: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
            }

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let progress = progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppTheme.bgSecondary)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geometry.size.width * min(1.0, CGFloat(progress)), height: 6)
                    }
                }
                .frame(height: 6)

                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
            }
        }
        .padding(10)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                .stroke(AppTheme.borderGlass, lineWidth: 0.5)
        )
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

// MARK: - Template Editor Sheet

struct TemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    let template: ConversationTemplate?
    let onSave: (ConversationTemplate) -> Void

    @State private var name: String = ""
    @State private var selectedIcon: String = "star"
    @State private var descriptionText: String = ""
    @State private var initialMessage: String = ""
    @State private var selectedCategory: String = "General"

    private let iconOptions: [String] = [
        "star", "heart", "bolt", "flame", "leaf",
        "brain.head.profile", "lightbulb", "book", "pencil", "doc.text",
        "magnifyingglass", "globe", "network", "server.rack", "cpu",
        "chevron.left.forwardslash.chevron.right", "terminal", "hammer",
        "wrench", "gearshape", "paintbrush", "photo", "camera",
        "music.note", "mic", "bubble.left", "envelope", "paperplane",
        "calendar", "clock", "chart.bar", "chart.pie", "list.bullet",
        "checkmark.shield", "lock", "key", "person", "person.2",
        "ladybug", "ant", "hare", "tortoise", "pawprint",
        "sun.max", "moon", "cloud", "drop", "wind",
        "airplane", "car", "bicycle", "figure.walk", "map",
        "flag", "tag", "bookmark", "folder", "tray",
        "archivebox", "puzzlepiece", "gamecontroller", "film", "theatermasks",
    ]

    private let categories = ["Development", "Writing", "Research", "General"]

    var isEditing: Bool { template != nil }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(template: ConversationTemplate?, onSave: @escaping (ConversationTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Template" : "Create Template")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(6)
                        .background(AppTheme.bgCard.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().background(AppTheme.borderGlass)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        TextField("Template name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(10)
                            .background(AppTheme.bgGlass)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                            )
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Icon")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            Image(systemName: selectedIcon)
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.accent)
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 10), spacing: 6) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button(action: { selectedIcon = icon }) {
                                    Image(systemName: icon)
                                        .font(.system(size: 13))
                                        .foregroundColor(selectedIcon == icon ? AppTheme.accent : AppTheme.textSecondary)
                                        .frame(width: 32, height: 32)
                                        .background(selectedIcon == icon ? AppTheme.accent.opacity(0.15) : AppTheme.bgCard.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    selectedIcon == icon ? AppTheme.accent.opacity(0.5) : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Category picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        HStack(spacing: 6) {
                            ForEach(categories, id: \.self) { cat in
                                Button(action: { selectedCategory = cat }) {
                                    Text(cat)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(selectedCategory == cat ? AppTheme.accent : AppTheme.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedCategory == cat ? AppTheme.accent.opacity(0.12) : AppTheme.bgCard.opacity(0.4))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    selectedCategory == cat ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass,
                                                    lineWidth: 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Description field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        TextField("Brief description of this template", text: $descriptionText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(10)
                            .background(AppTheme.bgGlass)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                            )
                    }

                    // Initial message field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Initial Message")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        TextEditor(text: $initialMessage)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80, maxHeight: 140)
                            .padding(10)
                            .background(AppTheme.bgGlass)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                            )
                    }

                    // Preview
                    if canSave {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Preview")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            GlassCard(padding: AppTheme.paddingMd) {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedIcon)
                                        .font(.system(size: 22))
                                        .foregroundColor(AppTheme.accent)
                                        .frame(width: 36, height: 36)
                                        .background(AppTheme.accent.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                        Text(descriptionText.isEmpty ? "No description" : descriptionText)
                                            .font(AppTheme.fontCaption)
                                            .foregroundColor(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(selectedCategory)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(AppTheme.textMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.bgCard.opacity(0.5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider().background(AppTheme.borderGlass)

            // Action buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.bgCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.borderGlass, lineWidth: 1)
                    )

                Spacer()

                Button(action: {
                    let saved = ConversationTemplate(
                        id: template?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        icon: selectedIcon,
                        description: descriptionText.trimmingCharacters(in: .whitespaces),
                        initialMessage: initialMessage,
                        isBuiltIn: false,
                        category: selectedCategory
                    )
                    onSave(saved)
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isEditing ? "checkmark" : "plus")
                            .font(.system(size: 11))
                        Text(isEditing ? "Save Changes" : "Create Template")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(canSave ? AppTheme.accent : AppTheme.accent.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 600)
        .background(AppTheme.bgPrimary)
        .onAppear {
            if let t = template {
                name = t.name
                selectedIcon = t.icon
                descriptionText = t.description
                initialMessage = t.initialMessage
                selectedCategory = t.category
            }
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

// MARK: - Performance Section

struct PerformanceSection: View {
    @EnvironmentObject var appState: AppState

    private var avgMs: Double { appState.averageResponseTime }

    private var responseTimeColor: Color {
        if avgMs <= 0 { return AppTheme.textMuted }
        if avgMs < 2000 { return AppTheme.success }
        if avgMs < 5000 { return AppTheme.warning }
        return AppTheme.error
    }

    private func colorForMs(_ ms: Int) -> Color {
        if ms < 2000 { return AppTheme.success }
        if ms < 5000 { return AppTheme.warning }
        return AppTheme.error
    }

    private func formatMs(_ ms: Double) -> String {
        if ms <= 0 { return "--" }
        if ms < 1000 { return String(format: "%.0fms", ms) }
        return String(format: "%.1fs", ms / 1000.0)
    }

    private func formatMs(_ ms: Int) -> String {
        formatMs(Double(ms))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Primary metric: average response time
            HStack(alignment: .top, spacing: 20) {
                // Big average number
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg Response Time")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)

                    Text(formatMs(avgMs))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(responseTimeColor)

                    if avgMs > 0 {
                        Text(avgMs < 2000 ? "Fast" : avgMs < 5000 ? "Moderate" : "Slow")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(responseTimeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(responseTimeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // Fastest / Slowest
                VStack(alignment: .trailing, spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Fastest")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                        if let fastest = appState.fastestResponseTime {
                            Text(formatMs(fastest))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(colorForMs(fastest))
                        } else {
                            Text("--")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Slowest")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                        if let slowest = appState.slowestResponseTime {
                            Text(formatMs(slowest))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(colorForMs(slowest))
                        } else {
                            Text("--")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }
                }
            }
            .padding()
            .background(AppTheme.bgCard.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.borderGlass, lineWidth: 0.5))

            // Response time trend chart (last 7 days)
            VStack(alignment: .leading, spacing: 8) {
                Text("Response Time Trend (7 days)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)

                let data = appState.responseTimesLastWeek
                let maxMs = max(data.map(\.avgMs).max() ?? 1, 1)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, entry in
                        VStack(spacing: 4) {
                            if entry.avgMs > 0 {
                                Text(formatMs(entry.avgMs))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(AppTheme.textMuted)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .fill(entry.avgMs > 0 ? colorForMs(entry.avgMs) : AppTheme.textMuted.opacity(0.15))
                                .frame(height: entry.avgMs > 0 ? max(CGFloat(entry.avgMs) / CGFloat(maxMs) * 80, 8) : 4)

                            Text(dayLabel(entry.date))
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110)
            }
            .padding()
            .background(AppTheme.bgCard.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.borderGlass, lineWidth: 0.5))

            // Activity metrics row
            HStack(spacing: 12) {
                perfMetricCard(
                    title: "Msgs/Hour",
                    value: String(format: "%.1f", appState.messagesPerHour),
                    icon: "bubble.left.and.bubble.right",
                    color: AppTheme.accent
                )

                perfMetricCard(
                    title: "Today",
                    value: "\(appState.conversationsToday)",
                    subtitle: "conversations",
                    icon: "calendar",
                    color: AppTheme.accent
                )

                perfMetricCard(
                    title: "This Week",
                    value: "\(appState.conversationsThisWeek)",
                    subtitle: "conversations",
                    icon: "calendar.badge.clock",
                    color: AppTheme.accent
                )
            }
        }
    }

    private func perfMetricCard(title: String, value: String, subtitle: String? = nil, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textMuted)

            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textMuted.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.borderGlass, lineWidth: 0.5))
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Activity Streak Content

struct ActivityStreakContent: View {
    @EnvironmentObject var appState: AppState

    private var warmOrange: Color {
        Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
    }

    private var warmRed: Color {
        Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Top row: Streak + Longest streak
            HStack(spacing: 16) {
                // Current streak
                GlassCard(hoverEnabled: false) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(streakColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: appState.streakEmoji)
                                .font(.system(size: 20))
                                .foregroundColor(streakColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(appState.currentStreak)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("day streak")
                                .font(AppTheme.fontCaption)
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        Spacer()
                    }
                }

                // Longest streak
                GlassCard(hoverEnabled: false) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.accent.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(appState.longestStreak)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("best streak")
                                .font(AppTheme.fontCaption)
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        Spacer()
                    }
                }
            }

            // Stats row: Conversations + Messages
            HStack(spacing: 16) {
                activityStatCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    value: "\(appState.totalConversationsCreated)",
                    label: "conversations",
                    color: AppTheme.accent
                )

                activityStatCard(
                    icon: "text.bubble.fill",
                    value: "\(appState.totalMessagesCount)",
                    label: "messages",
                    color: Color(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255)
                )
            }

            // Milestone badge (if applicable)
            if let milestone = appState.checkMilestone() {
                HStack(spacing: 10) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(warmOrange)

                    Text(milestone)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(warmOrange)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(warmOrange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                        .stroke(warmOrange.opacity(0.25), lineWidth: 1)
                )
            }

            // Mini heatmap: last 7 days
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 7 days")
                    .font(AppTheme.fontCaption)
                    .foregroundColor(AppTheme.textSecondary)

                HStack(spacing: 6) {
                    ForEach(Array(appState.last7DaysActivity().enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(heatmapColor(count: day.count))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(day.count > 0 ? "\(day.count)" : "")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                )

                            Text(shortDayLabel(day.date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }
                    Spacer()
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private var streakColor: Color {
        if appState.currentStreak >= 30 { return warmOrange }
        if appState.currentStreak >= 7 { return warmRed }
        return warmOrange
    }

    private func activityStatCard(icon: String, value: String, label: String, color: Color) -> some View {
        GlassCard(hoverEnabled: false) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)

                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(label)
                        .font(AppTheme.fontCaption)
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()
            }
        }
    }

    private func heatmapColor(count: Int) -> Color {
        if count == 0 { return AppTheme.bgCard.opacity(0.4) }
        if count <= 2 { return warmOrange.opacity(0.3) }
        if count <= 5 { return warmOrange.opacity(0.5) }
        if count <= 10 { return warmOrange.opacity(0.7) }
        return warmOrange
    }

    private func shortDayLabel(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return "" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        return String(dayFormatter.string(from: date).prefix(2))
    }
}

// MARK: - Model Usage Section

struct ModelUsageSection: View {
    @EnvironmentObject var appState: AppState

    private static let modelColors: [Color] = [
        Color(red: 88/255, green: 166/255, blue: 255/255),   // blue
        Color(red: 200/255, green: 80/255, blue: 200/255),   // purple
        Color(red: 80/255, green: 200/255, blue: 120/255),   // green
        Color(red: 255/255, green: 160/255, blue: 60/255),   // orange
        Color(red: 255/255, green: 90/255, blue: 90/255),    // red
        Color(red: 100/255, green: 220/255, blue: 220/255),  // teal
        Color(red: 220/255, green: 200/255, blue: 80/255),   // yellow
        Color(red: 160/255, green: 120/255, blue: 255/255),  // violet
    ]

    private func colorFor(index: Int) -> Color {
        Self.modelColors[index % Self.modelColors.count]
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func shortModelName(_ modelId: String) -> String {
        // Show a friendly short name for common model IDs
        let id = modelId.lowercased()
        if id.contains("opus") { return "Opus" }
        if id.contains("sonnet") { return "Sonnet" }
        if id.contains("haiku") { return "Haiku" }
        if id.contains("gpt-4o") { return "GPT-4o" }
        if id.contains("gpt-4") { return "GPT-4" }
        if id.contains("gpt-3") { return "GPT-3.5" }
        if id == "unknown" { return "Unknown" }
        // Fallback: last path component or full string
        return modelId.components(separatedBy: "/").last ?? modelId
    }

    var body: some View {
        let usageData = appState.modelUsageData

        if usageData.isEmpty {
            GlassCard {
                HStack {
                    Image(systemName: "chart.pie")
                        .foregroundColor(AppTheme.textMuted)
                    Text("No conversation data yet")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        } else {
            VStack(spacing: 14) {
                // Donut chart
                GlassCard {
                    VStack(spacing: 12) {
                        Text("Model Distribution")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        HStack(spacing: 24) {
                            // Donut
                            ZStack {
                                ModelDonutChart(data: usageData, colors: usageData.indices.map { colorFor(index: $0) })
                                    .frame(width: 120, height: 120)

                                VStack(spacing: 2) {
                                    Text("\(usageData.count)")
                                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Text(usageData.count == 1 ? "model" : "models")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppTheme.textMuted)
                                }
                            }

                            // Legend
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(usageData.prefix(6).enumerated()), id: \.element.id) { index, stat in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(colorFor(index: index))
                                            .frame(width: 8, height: 8)
                                        Text(shortModelName(stat.modelId))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(String(format: "%.0f%%", stat.percentage * 100))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                }
                            }
                            .frame(minWidth: 120)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Horizontal bar chart
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Usage by Model")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        let maxTokens = usageData.first?.totalTokens ?? 1

                        ForEach(Array(usageData.enumerated()), id: \.element.id) { index, stat in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(shortModelName(stat.modelId))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Spacer()
                                    Text("\(stat.conversationCount) conv")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(AppTheme.textMuted)
                                    Text(formatTokens(stat.totalTokens) + " tokens")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(AppTheme.textSecondary)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppTheme.bgPrimary.opacity(0.5))

                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(colorFor(index: index))
                                            .frame(width: geo.size.width * CGFloat(stat.totalTokens) / CGFloat(max(maxTokens, 1)))
                                    }
                                }
                                .frame(height: 8)

                                HStack {
                                    Spacer()
                                    Text(String(format: "%.1f%% of total", stat.percentage * 100))
                                        .font(.system(size: 9))
                                        .foregroundColor(AppTheme.textMuted)
                                }
                            }
                            .padding(.bottom, index < usageData.count - 1 ? 4 : 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Model Donut Chart

struct ModelDonutChart: View {
    let data: [ModelUsageStats]
    let colors: [Color]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2
            let innerRadius = outerRadius * 0.6
            var startAngle = Angle.degrees(-90)

            for (index, stat) in data.enumerated() {
                let sweepAngle = Angle.degrees(stat.percentage * 360)
                let endAngle = startAngle + sweepAngle

                let path = Path { p in
                    p.addArc(center: center, radius: outerRadius,
                             startAngle: startAngle, endAngle: endAngle, clockwise: false)
                    p.addArc(center: center, radius: innerRadius,
                             startAngle: endAngle, endAngle: startAngle, clockwise: true)
                    p.closeSubpath()
                }

                let color = index < colors.count ? colors[index] : Color.gray
                context.fill(path, with: .color(color))

                startAngle = endAngle
            }
        }
    }
}

// MARK: - Tips & Tricks Widget

struct TipsAndTricksContent: View {
    @EnvironmentObject var appState: AppState
    @State private var currentTipIndex: Int = 0
    @State private var showAllTips: Bool = false
    @State private var autoRotateTimer: Timer?

    private var tips: [TipItem] {
        appState.activeTips
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tips.isEmpty {
                emptyState
            } else if showAllTips {
                allTipsListView
            } else {
                singleTipView
            }
        }
        .onAppear { startAutoRotate() }
        .onDisappear { stopAutoRotate() }
        .onChange(of: tips.count) { _ in
            if currentTipIndex >= tips.count {
                currentTipIndex = max(0, tips.count - 1)
            }
        }
    }

    // MARK: - Single Tip View

    private var singleTipView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !tips.isEmpty {
                let tip = tips[currentTipIndex % max(tips.count, 1)]

                HStack(alignment: .top, spacing: 14) {
                    // Tip icon
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: tip.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        Text(tip.description)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        if let actionLabel = tip.actionLabel {
                            Button(action: {
                                tip.actionHandler?()
                            }) {
                                Text(actionLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }

                    Spacer()

                    // Dismiss button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.dismissTip(tip.id)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.textMuted)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss this tip")
                }
                .id(tip.id)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity
                ))
                .animation(.easeInOut(duration: 0.4), value: currentTipIndex)
            }

            // Navigation bar
            HStack(spacing: 8) {
                // Previous
                Button(action: { navigatePrevious() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(6)
                        .background(AppTheme.bgCard.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Previous tip")

                // Progress dots
                HStack(spacing: 4) {
                    ForEach(0..<min(tips.count, 10), id: \.self) { index in
                        Circle()
                            .fill(index == (currentTipIndex % max(tips.count, 1))
                                  ? AppTheme.accent
                                  : AppTheme.textMuted.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                    if tips.count > 10 {
                        Text("+\(tips.count - 10)")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                }

                // Next
                Button(action: { navigateNext() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(6)
                        .background(AppTheme.bgCard.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Next tip")

                Spacer()

                // Tip count
                Text("\(currentTipIndex % max(tips.count, 1) + 1) of \(tips.count)")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textMuted)

                // Show all tips button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showAllTips = true
                        stopAutoRotate()
                    }
                }) {
                    Text("Show all tips")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Show all tips in a list")
            }
        }
    }

    // MARK: - All Tips List View

    private var allTipsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All Tips (\(tips.count))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                if !appState.dismissedTipIds.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            appState.restoreAllTips()
                        }
                    }) {
                        Text("Restore dismissed")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showAllTips = false
                        startAutoRotate()
                    }
                }) {
                    Text("Collapse")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    ForEach(tips) { tip in
                        HStack(spacing: 10) {
                            Image(systemName: tip.icon)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)

                                Text(tip.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if let actionLabel = tip.actionLabel {
                                Button(action: { tip.actionHandler?() }) {
                                    Text(actionLabel)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(AppTheme.accent.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.dismissTip(tip.id)
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(AppTheme.textMuted)
                                    .padding(3)
                            }
                            .buttonStyle(.plain)
                            .help("Dismiss this tip")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(AppTheme.bgCard.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("All tips dismissed")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.restoreAllTips()
                }
            }) {
                Text("Restore all tips")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Navigation

    private func navigateNext() {
        guard !tips.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            currentTipIndex = (currentTipIndex + 1) % tips.count
        }
        restartAutoRotate()
    }

    private func navigatePrevious() {
        guard !tips.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            currentTipIndex = (currentTipIndex - 1 + tips.count) % tips.count
        }
        restartAutoRotate()
    }

    // MARK: - Auto-Rotate Timer

    private func startAutoRotate() {
        stopAutoRotate()
        autoRotateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            DispatchQueue.main.async {
                guard !tips.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentTipIndex = (currentTipIndex + 1) % tips.count
                }
            }
        }
    }

    private func stopAutoRotate() {
        autoRotateTimer?.invalidate()
        autoRotateTimer = nil
    }

    private func restartAutoRotate() {
        stopAutoRotate()
        startAutoRotate()
    }
}

// MARK: - Quick Actions Content

struct QuickActionsContent: View {
    @EnvironmentObject var appState: AppState
    @State private var showClearConfirmation = false

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.paddingMd),
        GridItem(.flexible(), spacing: AppTheme.paddingMd),
        GridItem(.flexible(), spacing: AppTheme.paddingMd),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.paddingMd) {
            QuickActionCard(icon: "plus.bubble", label: "New Chat") {
                appState.startNewChat()
            }

            QuickActionCard(icon: "trash", label: "Clear History", destructive: true) {
                showClearConfirmation = true
            }

            QuickActionCard(icon: "power", label: "Toggle Gateway", active: appState.gatewayRunning) {
                appState.toggleGateway()
            }

            QuickActionCard(icon: "square.and.arrow.up", label: "Export All") {
                // Placeholder
            }

            QuickActionCard(icon: "arrow.clockwise", label: "Check Updates") {
                // Placeholder
            }

            QuickActionCard(icon: "folder", label: "Open Config") {
                let configPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".desktop-agent")
                NSWorkspace.shared.open(configPath)
            }
        }
        .alert("Clear All Conversations?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                appState.clearAllConversations()
            }
        } message: {
            Text("This will permanently delete all conversation history. This action cannot be undone.")
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let label: String
    var destructive: Bool = false
    var active: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var accentColor: Color {
        if destructive { return Color.red }
        if active { return AppTheme.success }
        return AppTheme.accent
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isHovered ? accentColor : AppTheme.textSecondary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? AppTheme.textPrimary : AppTheme.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isHovered ? accentColor.opacity(0.08) : AppTheme.bgCard.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHovered ? accentColor.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
    }
}
