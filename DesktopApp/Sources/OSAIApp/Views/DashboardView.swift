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
                        QuickAction(icon: "envelope", label: "Check email") {
                            appState.sendMessage("Check my emails")
                        }
                        QuickAction(icon: "calendar", label: "Calendar") {
                            appState.sendMessage("What's on my calendar today?")
                        }
                        QuickAction(icon: "newspaper", label: "News") {
                            appState.sendMessage("Dame un briefing de noticias de hoy")
                        }
                        QuickAction(icon: "terminal", label: "Code") {
                            appState.selectedTab = .chat
                        }
                    }
                }
                .padding(.top, 30)
                .padding(.bottom, 10)

                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                ], spacing: 14) {
                    StatCard(
                        icon: "cpu", label: "Tokens today",
                        value: formatNumber(appState.tokensToday),
                        color: AppTheme.accent
                    )
                    StatCard(
                        icon: "dollarsign.circle", label: "Cost today",
                        value: String(format: "$%.2f", appState.costToday),
                        color: appState.costToday / appState.config.spendingLimits.dailyUSD > 0.7 ? AppTheme.warning : AppTheme.accent,
                        progress: appState.config.spendingLimits.dailyUSD > 0
                            ? appState.costToday / appState.config.spendingLimits.dailyUSD : 0
                    )
                    StatCard(
                        icon: "person.3", label: "Agents",
                        value: "\(appState.agents.count) active",
                        color: Color(red: 200/255, green: 80/255, blue: 200/255)
                    )
                    StatCard(
                        icon: "bolt.circle", label: "Gateway",
                        value: appState.gatewayRunning ? "Active" : "Off",
                        color: appState.gatewayRunning ? AppTheme.success : AppTheme.textMuted
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

                // Two-column layout
                HStack(alignment: .top, spacing: AppTheme.paddingLg) {
                    // Running Tasks
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Active Tasks", icon: "clock.fill")

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
                            ForEach(appState.tasks.filter { $0.enabled }.prefix(5)) { task in
                                MiniTaskRow(task: task) {
                                    appState.selectedTab = .tasks
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                            ForEach(appState.agents.prefix(5)) { agent in
                                AgentPill(agent: agent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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
                        HoverGlassCard {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .foregroundColor(AppTheme.textMuted)
                                Text("No recent conversations — start chatting!")
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
