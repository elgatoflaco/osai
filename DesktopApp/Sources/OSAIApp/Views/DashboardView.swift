import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var taskInput = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppTheme.paddingLg) {
                // Hero section
                VStack(spacing: 20) {
                    GhostIcon(size: 64)
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

                // Gateway status bar
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
                .frame(maxWidth: 800)

                // Stats grid
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
                .frame(maxWidth: 800)

                // Monthly spending
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
                .frame(maxWidth: 800)

                // Token & Cost Statistics
                TokenStatsSection(conversations: appState.conversations)
                    .frame(maxWidth: 800)

                // Usage Analytics
                AnalyticsSectionView(conversations: appState.conversations, agents: appState.agents)
                    .frame(maxWidth: 800)

                // Two-column layout
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

                // System Health
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

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppTheme.paddingXl)
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
