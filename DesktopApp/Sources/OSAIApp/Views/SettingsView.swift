import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    private let configService = ConfigService()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppTheme.paddingLg) {
                HStack {
                    Text("Settings")
                        .font(AppTheme.fontTitle)
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Button(action: { appState.loadAll() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Active Model
                SettingsSection(title: "Active Model", icon: "cpu") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(appState.config.activeModel)
                                .font(AppTheme.fontMono)
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                        }

                        Picker("Model", selection: Binding(
                            get: { appState.config.activeModel },
                            set: { newVal in
                                appState.config.activeModel = newVal
                                configService.saveActiveModel(newVal)
                            }
                        )) {
                            Section("Anthropic") {
                                Text("Claude Sonnet 4").tag("anthropic/claude-sonnet-4-20250514")
                                Text("Claude Haiku 4.5").tag("anthropic/claude-haiku-4-5-20251001")
                            }
                            Section("Google") {
                                Text("Gemini 2.5 Flash").tag("google/gemini-2.5-flash")
                                Text("Gemini 2.5 Pro").tag("google/gemini-2.5-pro")
                            }
                            Section("OpenAI") {
                                Text("GPT-4.1").tag("openai/gpt-4.1")
                                Text("o4-mini").tag("openai/o4-mini")
                            }
                            Section("Other") {
                                Text("Grok 3").tag("xai/grok-3")
                                Text("DeepSeek Chat").tag("deepseek/deepseek-chat")
                                Text("Claude Code (local)").tag("claude-code")
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppTheme.accent)
                    }
                }

                // Gateway
                SettingsSection(title: "Gateway", icon: "network") {
                    VStack(spacing: 14) {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(appState.gatewayRunning ? AppTheme.success : AppTheme.textMuted)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: appState.gatewayRunning ? AppTheme.success.opacity(0.5) : .clear, radius: 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appState.gatewayRunning ? "Running" : "Stopped")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(appState.gatewayRunning ? AppTheme.success : AppTheme.textSecondary)
                                    if let pid = appState.gatewayPID {
                                        Text("PID: \(pid)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(AppTheme.textMuted)
                                    }
                                }
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button(action: { appState.toggleGateway() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: appState.gatewayRunning ? "stop.fill" : "play.fill")
                                        Text(appState.gatewayRunning ? "Stop" : "Start")
                                    }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(appState.gatewayRunning ? AppTheme.error : AppTheme.success)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background((appState.gatewayRunning ? AppTheme.error : AppTheme.success).opacity(0.12))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                if appState.gatewayRunning {
                                    Button(action: { appState.forceStopGateway() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "xmark.circle")
                                            Text("Force Kill")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppTheme.error)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.error.opacity(0.08))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Auto-start
                        Divider().background(AppTheme.borderGlass)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start on Login")
                                    .font(AppTheme.fontBody)
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Automatically start gateway when you log in")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { appState.isGatewayAutoStart },
                                set: { enable in
                                    if enable {
                                        appState.installGatewayStartup()
                                    } else {
                                        appState.removeGatewayStartup()
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .tint(AppTheme.accent)
                        }

                        if !appState.config.gateways.isEmpty {
                            Divider().background(AppTheme.borderGlass)

                            ForEach(Array(appState.config.gateways.keys.sorted()), id: \.self) { name in
                                if let gw = appState.config.gateways[name] {
                                    HStack {
                                        Image(systemName: gw.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(AppTheme.textSecondary)
                                            .frame(width: 20)
                                        Text(name.capitalized)
                                            .font(AppTheme.fontBody)
                                            .foregroundColor(AppTheme.textPrimary)
                                        Spacer()
                                        Text(gw.enabled ? "Enabled" : "Disabled")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(gw.enabled ? AppTheme.success : AppTheme.textMuted)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background((gw.enabled ? AppTheme.success : AppTheme.textMuted).opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }

                // Usage & Spending
                SettingsSection(title: "Usage & Spending", icon: "chart.bar") {
                    VStack(spacing: 16) {
                        // Today
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Today")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Text(String(format: "$%.2f / $%.0f", appState.costToday, appState.config.spendingLimits.dailyUSD))
                                    .font(AppTheme.fontMono)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            let dailyProgress = appState.config.spendingLimits.dailyUSD > 0
                                ? min(appState.costToday / appState.config.spendingLimits.dailyUSD, 1.0) : 0
                            ProgressBar(progress: dailyProgress,
                                        color: dailyProgress > 0.7 ? AppTheme.warning : AppTheme.accent)
                                .frame(height: 6)
                        }

                        // Month
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("This Month")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                                Text(String(format: "$%.2f / $%.0f", appState.costMonth, appState.config.spendingLimits.monthlyUSD))
                                    .font(AppTheme.fontMono)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            let monthProgress = appState.config.spendingLimits.monthlyUSD > 0
                                ? min(appState.costMonth / appState.config.spendingLimits.monthlyUSD, 1.0) : 0
                            ProgressBar(progress: monthProgress,
                                        color: monthProgress > 0.7 ? AppTheme.warning : AppTheme.accent)
                                .frame(height: 6)
                        }

                        Divider().background(AppTheme.borderGlass)

                        // Limits
                        VStack(spacing: 8) {
                            SpendingRow(label: "Daily Limit", value: appState.config.spendingLimits.dailyUSD)
                            SpendingRow(label: "Monthly Limit", value: appState.config.spendingLimits.monthlyUSD)
                            SpendingRow(label: "Per Session", value: appState.config.spendingLimits.perSessionUSD)
                        }

                        HStack {
                            Text("Warning at")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("\(appState.config.spendingLimits.warnAtPercent)%")
                                .font(AppTheme.fontMono)
                                .foregroundColor(AppTheme.warning)
                        }

                        HStack {
                            Text("Tokens today")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text(formatTokens(appState.tokensToday))
                                .font(AppTheme.fontMono)
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    }
                }

                // API Keys
                SettingsSection(title: "API Keys", icon: "key.fill") {
                    if appState.config.apiKeys.isEmpty {
                        HStack {
                            Image(systemName: "key")
                                .foregroundColor(AppTheme.textMuted)
                            Text("No API keys configured. Run 'osai doctor' to set up.")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textMuted)
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(appState.config.apiKeys.keys.sorted()), id: \.self) { provider in
                                if let entry = appState.config.apiKeys[provider] {
                                    APIKeyRow(provider: provider, entry: entry)
                                }
                            }
                        }
                    }
                }

                // Appearance
                SettingsSection(title: "Appearance", icon: "paintbrush") {
                    HStack {
                        Text("Dark Mode")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Toggle("", isOn: $appState.isDarkMode)
                            .toggleStyle(.switch)
                            .tint(AppTheme.accent)
                    }

                    HStack {
                        Text("Sidebar collapsed")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Toggle("", isOn: $appState.sidebarCollapsed)
                            .toggleStyle(.switch)
                            .tint(AppTheme.accent)
                    }
                }

                // Paths
                SettingsSection(title: "Paths & Info", icon: "folder") {
                    VStack(spacing: 8) {
                        PathRow(label: "Config", path: "~/.desktop-agent/")
                        PathRow(label: "Agents", path: "~/.desktop-agent/agents/")
                        PathRow(label: "Tasks", path: "~/.desktop-agent/tasks/")
                        PathRow(label: "Conversations", path: "~/.desktop-agent/conversations/")
                        PathRow(label: "Binary", path: "/usr/local/bin/osai")

                        Divider().background(AppTheme.borderGlass)

                        HStack {
                            Text("osai Desktop")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Text("v1.0.0")
                                .font(AppTheme.fontMono)
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }
                }

                // Quick Actions
                SettingsSection(title: "Quick Actions", icon: "bolt") {
                    HStack(spacing: 10) {
                        SettingsActionButton(label: "Open Config", icon: "folder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.desktop-agent"))
                        }
                        SettingsActionButton(label: "Run Doctor", icon: "stethoscope") {
                            Task {
                                _ = try? await appState.service.run(args: ["doctor"])
                            }
                        }
                        SettingsActionButton(label: "Reveal in Finder", icon: "magnifyingglass") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: NSHomeDirectory() + "/.desktop-agent")
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppTheme.paddingXl)
            .padding(.vertical, AppTheme.paddingLg)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accent)
                Text(title)
                    .font(AppTheme.fontHeadline)
                    .foregroundColor(AppTheme.textPrimary)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.borderGlass, lineWidth: 1)
        )
    }
}

struct APIKeyRow: View {
    let provider: String
    let entry: APIKeyEntry
    @State private var showKey = false
    @State private var copied = false

    var body: some View {
        HStack {
            Text(provider.capitalized)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 90, alignment: .leading)

            Text(showKey ? entry.apiKey : entry.maskedKey)
                .font(AppTheme.fontMono)
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(1)

            Spacer()

            Button(action: { showKey.toggle() }) {
                Image(systemName: showKey ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textMuted)
            }
            .buttonStyle(.plain)

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.apiKey, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
            }) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(copied ? AppTheme.success : AppTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(AppTheme.bgPrimary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SpendingRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
                .font(AppTheme.fontBody)
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(String(format: "$%.0f", value))
                .font(AppTheme.fontMono)
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

struct PathRow: View {
    let label: String
    let path: String

    var body: some View {
        HStack {
            Text(label)
                .font(AppTheme.fontBody)
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.textMuted)
        }
    }
}

struct SettingsActionButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(AppTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHovered ? AppTheme.accent.opacity(0.15) : AppTheme.accent.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppTheme.accent.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
