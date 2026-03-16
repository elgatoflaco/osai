import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    private let configService = ConfigService()

    // Well-known providers to always show status for
    private let knownProviders = ["anthropic", "openai", "google", "openrouter", "xai", "deepseek"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppTheme.paddingLg) {
                // Header
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

                // 1. API Keys
                apiKeysSection

                // 2. Active Model
                activeModelSection

                // 3. Gateway
                gatewaySection

                // 4. Usage & Spending
                spendingSection

                // 5. Appearance
                appearanceSection

                // 6. Quick Actions & Paths
                pathsSection

                // 7. About
                aboutSection

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppTheme.paddingXl)
            .padding(.vertical, AppTheme.paddingLg)
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        SettingsSection(title: "API Keys", icon: "key.fill") {
            VStack(spacing: 10) {
                // Show all known providers with status
                ForEach(allProviders, id: \.self) { provider in
                    let entry = appState.config.apiKeys[provider]
                    let hasKey = entry != nil && !(entry!.apiKey.isEmpty)

                    HStack(spacing: 10) {
                        // Status dot
                        Circle()
                            .fill(hasKey ? AppTheme.success : AppTheme.error.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .shadow(color: hasKey ? AppTheme.success.opacity(0.4) : .clear, radius: 3)

                        Text(providerDisplayName(provider))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(minWidth: 90, alignment: .leading)

                        if let entry = entry, hasKey {
                            Text(entry.maskedKey)
                                .font(AppTheme.fontMono)
                                .foregroundColor(AppTheme.textMuted)
                                .lineLimit(1)
                        } else {
                            Text("Not configured")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textMuted)
                        }

                        Spacer()

                        if hasKey {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.success)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.success.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(AppTheme.bgPrimary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider().background(AppTheme.borderGlass)

                // CLI hint
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                    Text("Use ")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                    + Text("osai config set-key <provider>")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                    + Text(" to add or update keys")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Active Model

    private var activeModelSection: some View {
        SettingsSection(title: "Active Model", icon: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                // Current model display
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(modelDisplayName(appState.config.activeModel))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(appState.config.activeModel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                    Text(modelProvider(appState.config.activeModel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(Capsule())
                }

                Divider().background(AppTheme.borderGlass)

                // Model picker
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
                        Text("Gemini 3 Flash").tag("google/gemini-3-flash-preview")
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
    }

    // MARK: - Gateway

    private var gatewaySection: some View {
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

                Divider().background(AppTheme.borderGlass)

                // Auto-start toggle
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
                    Toggle("Start on Login", isOn: Binding(
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
                    .labelsHidden()
                    .accessibilityLabel("Start gateway on login")
                    .accessibilityValue(appState.isGatewayAutoStart ? "On" : "Off")
                }

                // Gateway integrations
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
    }

    // MARK: - Spending

    private var spendingSection: some View {
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
                                color: dailyProgress > 0.8 ? AppTheme.error : dailyProgress > 0.5 ? AppTheme.warning : AppTheme.accent)
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
                                color: monthProgress > 0.8 ? AppTheme.error : monthProgress > 0.5 ? AppTheme.warning : AppTheme.accent)
                        .frame(height: 6)
                }

                Divider().background(AppTheme.borderGlass)

                // Limits table
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
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", icon: "paintbrush") {
            VStack(spacing: 14) {
                // Dark Mode toggle
                HStack {
                    Text("Dark Mode")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Toggle("Dark Mode", isOn: $appState.isDarkMode)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .accessibilityLabel("Dark Mode")
                        .accessibilityValue(appState.isDarkMode ? "On" : "Off")
                }

                // Sidebar collapsed toggle
                HStack {
                    Text("Sidebar collapsed")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Toggle("Sidebar collapsed", isOn: $appState.sidebarCollapsed)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .accessibilityLabel("Sidebar collapsed")
                        .accessibilityValue(appState.sidebarCollapsed ? "On" : "Off")
                }

                Divider().background(AppTheme.borderGlass)

                // Accent Color
                VStack(alignment: .leading, spacing: 10) {
                    Text("Accent Color")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)

                    HStack(spacing: 12) {
                        ForEach(accentColorPresets) { preset in
                            Button(action: {
                                appState.changeAccentColor(preset.id)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 28, height: 28)
                                        .shadow(color: appState.selectedAccentColor == preset.id
                                                ? preset.color.opacity(0.6) : .clear,
                                                radius: 6)

                                    if appState.selectedAccentColor == preset.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                            .accessibilityAddTraits(appState.selectedAccentColor == preset.id ? .isSelected : [])
                        }
                    }

                    // Preview strip
                    HStack(spacing: 12) {
                        Text("Preview")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)

                        Text("Link text")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.accent)

                        Text("Button")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppTheme.accent)
                            .clipShape(Capsule())

                        RoundedRectangle(cornerRadius: 4)
                            .stroke(AppTheme.accent, lineWidth: 2)
                            .frame(width: 48, height: 22)
                            .overlay(
                                Text("Input")
                                    .font(.system(size: 9))
                                    .foregroundColor(AppTheme.textMuted)
                            )
                    }
                    .padding(.top, 2)
                }

                Divider().background(AppTheme.borderGlass)

                // Window Management
                VStack(alignment: .leading, spacing: 12) {
                    Text("Window")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)

                    // Compact mode toggle
                    HStack {
                        Text("Compact Mode")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text("\u{2318}\u{21E7}M")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.trailing, 4)
                        Toggle("Compact Mode", isOn: Binding(
                            get: { appState.compactMode },
                            set: { _ in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.toggleCompactMode()
                                }
                            }
                        ))
                            .toggleStyle(.switch)
                            .tint(AppTheme.accent)
                            .labelsHidden()
                    }

                    // Float on top toggle
                    HStack {
                        HStack(spacing: 6) {
                            Text("Float on Top")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textPrimary)
                            if appState.floatOnTop {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(AppTheme.accent)
                            }
                        }
                        Spacer()
                        Text("\u{2318}\u{21E7}T")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.trailing, 4)
                        Toggle("Float on Top", isOn: Binding(
                            get: { appState.floatOnTop },
                            set: { _ in appState.toggleFloatOnTop() }
                        ))
                            .toggleStyle(.switch)
                            .tint(AppTheme.accent)
                            .labelsHidden()
                    }

                    // Window opacity slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Window Opacity")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Text("\(Int(appState.windowOpacity * 100))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        Slider(value: $appState.windowOpacity, in: 0.8...1.0, step: 0.05)
                            .tint(AppTheme.accent)
                            .accessibilityLabel("Window Opacity")
                            .accessibilityValue("\(Int(appState.windowOpacity * 100)) percent")
                    }
                }
            }
        }
    }

    // MARK: - Paths & Quick Actions

    private var pathsSection: some View {
        SettingsSection(title: "Paths & Actions", icon: "folder") {
            VStack(spacing: 10) {
                PathRow(label: "Config", path: "~/.desktop-agent/")
                PathRow(label: "Agents", path: "~/.desktop-agent/agents/")
                PathRow(label: "Tasks", path: "~/.desktop-agent/tasks/")
                PathRow(label: "Conversations", path: "~/.desktop-agent/conversations/")
                PathRow(label: "Binary", path: "/usr/local/bin/osai")

                Divider().background(AppTheme.borderGlass)

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
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(title: "About", icon: "info.circle") {
            VStack(spacing: 10) {
                HStack {
                    Text("osai Desktop")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("v1.0.0")
                        .font(AppTheme.fontMono)
                        .foregroundColor(AppTheme.textMuted)
                }

                HStack {
                    Text("Platform")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                }

                Divider().background(AppTheme.borderGlass)

                HStack {
                    Button(action: {
                        if let url = URL(string: "https://github.com/AdrianTomin/osai") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("View on GitHub")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    /// Merged list of known + any extra configured providers
    private var allProviders: [String] {
        var providers = knownProviders
        for key in appState.config.apiKeys.keys {
            if !providers.contains(key) {
                providers.append(key)
            }
        }
        return providers
    }

    private func providerDisplayName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "anthropic": return "Anthropic"
        case "openai": return "OpenAI"
        case "google": return "Google"
        case "openrouter": return "OpenRouter"
        case "xai": return "xAI"
        case "deepseek": return "DeepSeek"
        default: return provider.capitalized
        }
    }

    private func modelDisplayName(_ model: String) -> String {
        if model == "claude-code" { return "Claude Code" }
        if model.contains("/") {
            return String(model.split(separator: "/").last ?? Substring(model))
        }
        return model
    }

    private func modelProvider(_ model: String) -> String {
        if model == "claude-code" { return "Local" }
        if model.contains("/") {
            return providerDisplayName(String(model.split(separator: "/").first ?? ""))
        }
        return "Unknown"
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(String(format: "$%.0f", value))")
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
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
