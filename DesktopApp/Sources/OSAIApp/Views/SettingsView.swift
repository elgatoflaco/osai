import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    private let configService = ConfigService()
    @State private var showResetConfirmation = false
    @State private var showChangelog = false
    @State private var searchText = ""
    @State private var editingProvider: String? = nil
    @State private var editingKeyText: String = ""
    @State private var showAPIKeyEditor = false

    // Well-known providers to always show status for
    private let knownProviders = ["anthropic", "openai", "google", "openrouter", "xai", "deepseek", "groq", "mistral"]

    // MARK: - Searchable Sections

    private enum SettingsSectionID: String, CaseIterable {
        case apiKeys, activeModel, gateway, spending, budget, usageStatistics
        case appearance, notifications, backupRestore, paths, about

        var keywords: [String] {
            switch self {
            case .apiKeys:
                return ["api", "key", "keys", "provider", "anthropic", "openai", "google", "openrouter", "xai", "deepseek", "token", "secret", "credential"]
            case .activeModel:
                return ["model", "active", "claude", "gpt", "gemini", "grok", "deepseek", "sonnet", "haiku", "cpu", "llm", "ai"]
            case .gateway:
                return ["gateway", "server", "network", "start", "stop", "login", "auto-start", "pid", "running", "background"]
            case .spending:
                return ["spending", "usage", "cost", "daily", "monthly", "limit", "tokens", "dollar", "money", "session", "warning"]
            case .budget:
                return ["budget", "daily", "monthly", "cost", "spending", "alert", "limit", "dollar", "money", "reset"]
            case .usageStatistics:
                return ["usage", "statistics", "chart", "tokens", "input", "output", "weekly", "graph", "analytics"]
            case .appearance:
                return ["appearance", "theme", "dark", "light", "mode", "font", "size", "color", "accent", "sidebar", "compact", "density", "code", "syntax", "window", "opacity", "float", "smart", "paste", "speech", "tts", "timestamp", "preset"]
            case .notifications:
                return ["notification", "notifications", "sound", "alert", "bell", "task", "agent", "route", "ping", "pop", "glass"]
            case .backupRestore:
                return ["backup", "restore", "export", "import", "reset", "settings", "save", "load", "json"]
            case .paths:
                return ["path", "paths", "folder", "config", "agents", "tasks", "conversations", "binary", "doctor", "finder", "directory", "file"]
            case .about:
                return ["about", "version", "info", "swift", "macos", "github", "bug", "documentation", "changelog", "credits"]
            }
        }
    }

    private var visibleSections: Set<SettingsSectionID> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return Set(SettingsSectionID.allCases)
        }
        return Set(SettingsSectionID.allCases.filter { section in
            section.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        })
    }

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

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(searchText.isEmpty ? AppTheme.textMuted : AppTheme.accent)

                    TextField("Search settings...", text: $searchText)
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textPrimary)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .background(AppTheme.bgGlass)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                        .stroke(searchText.isEmpty ? AppTheme.borderGlass : AppTheme.accent.opacity(0.4), lineWidth: 1)
                )

                if visibleSections.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No settings match \"\(searchText)\"")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Try a different search term")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    let matched = visibleSections

                    // 1. API Keys
                    if matched.contains(.apiKeys) { apiKeysSection }

                    // 2. Active Model
                    if matched.contains(.activeModel) { activeModelSection }

                    // 3. Gateway
                    if matched.contains(.gateway) { gatewaySection }

                    // 4. Usage & Spending
                    if matched.contains(.spending) { spendingSection }

                    // 4a. Budget
                    if matched.contains(.budget) { budgetSection }

                    // 4b. Token Usage Chart
                    if matched.contains(.usageStatistics) { usageStatisticsSection }

                    // 5. Appearance
                    if matched.contains(.appearance) { appearanceSection }

                    // 5b. Behavior (YOLO mode)
                    behaviorSection

                    // 5c. Notifications
                    if matched.contains(.notifications) { notificationsSection }

                    // 5c. Backup & Restore
                    if matched.contains(.backupRestore) { backupRestoreSection }

                    // 6. Quick Actions & Paths
                    if matched.contains(.paths) { pathsSection }

                    // 7. About
                    if matched.contains(.about) { aboutSection }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppTheme.paddingXl)
            .padding(.vertical, AppTheme.paddingLg)
            .animation(.easeInOut(duration: 0.2), value: searchText)
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        SettingsSection(title: "API Keys", icon: "key.fill") {
            VStack(spacing: 10) {
                ForEach(allProviders, id: \.self) { provider in
                    let entry = appState.config.apiKeys[provider]
                    let hasKey = entry != nil && !(entry!.apiKey.isEmpty)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(hasKey ? AppTheme.success : AppTheme.error.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .shadow(color: hasKey ? AppTheme.success.opacity(0.4) : .clear, radius: 3)

                        Text(providerDisplayName(provider))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .frame(minWidth: 90, alignment: .leading)

                        if let entry = entry, hasKey {
                            if provider == "anthropic" && entry.apiKey.hasPrefix("sk-ant-oat") {
                                Text("Suscripción Pro")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }
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

                        // Edit button
                        Button(action: {
                            editingProvider = provider
                            editingKeyText = entry?.apiKey ?? ""
                            showAPIKeyEditor = true
                        }) {
                            Image(systemName: hasKey ? "pencil" : "plus.circle")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .help(hasKey ? "Edit API key" : "Add API key")

                        // Delete button (only if has key)
                        if hasKey {
                            Button(action: {
                                appState.removeAPIKey(provider: provider)
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.error.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Remove API key")
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(AppTheme.bgPrimary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .sheet(isPresented: $showAPIKeyEditor) {
                apiKeyEditorSheet
            }
        }
    }

    private var apiKeyEditorSheet: some View {
        VStack(spacing: 16) {
            Text(editingProvider.map { "\(providerDisplayName($0)) API Key" } ?? "API Key")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            SecureField("Paste API key or token...", text: $editingKeyText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

            if let provider = editingProvider, editingKeyText.hasPrefix("sk-ant-oat") && provider == "anthropic" {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("OAuth token detected — will use Bearer auth automatically")
                }
                .font(.system(size: 11))
                .foregroundColor(AppTheme.accent)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showAPIKeyEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let provider = editingProvider, !editingKeyText.isEmpty {
                        appState.saveAPIKey(provider: provider, key: editingKeyText)
                    }
                    showAPIKeyEditor = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editingKeyText.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(AppTheme.bgSecondary)
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

                // Model picker — uses shared allModelDefinitions
                Picker("Model", selection: Binding(
                    get: { appState.config.activeModel },
                    set: { newVal in
                        appState.config.activeModel = newVal
                        configService.saveActiveModel(newVal)
                    }
                )) {
                    ForEach(appState.modelsGroupedByProvider, id: \.provider) { group in
                        Section(header: Text(group.provider)) {
                            ForEach(group.models) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
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
                                    .foregroundColor(gw.enabled ? AppTheme.textSecondary : AppTheme.textMuted)
                                    .frame(width: 20)
                                Text(name.capitalized)
                                    .font(AppTheme.fontBody)
                                    .foregroundColor(gw.enabled ? AppTheme.textPrimary : AppTheme.textMuted)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { gw.enabled },
                                    set: { newValue in
                                        appState.setGatewayEnabled(name: name, enabled: newValue)
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .tint(AppTheme.success)
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

    // MARK: - Budget

    private var budgetSection: some View {
        SettingsSection(title: "Budget", icon: "shield.lefthalf.filled") {
            VStack(spacing: 16) {
                // Daily budget input
                HStack {
                    Text("Daily Budget")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("$")
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textSecondary)
                        TextField("5.00", value: Binding(
                            get: { appState.dailyBudget },
                            set: { appState.dailyBudget = $0 }
                        ), format: .number.precision(.fractionLength(2)))
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textPrimary)
                            .textFieldStyle(.plain)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.bgPrimary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                // Daily progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Today")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                        Text(String(format: "$%.2f / $%.2f (%.0f%%)", appState.costToday, appState.dailyBudget, appState.dailySpendingPercentage * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    let dp = min(appState.dailySpendingPercentage, 1.0)
                    ProgressBar(progress: dp,
                                color: dp > 0.8 ? AppTheme.error : dp > 0.6 ? AppTheme.warning : AppTheme.success)
                        .frame(height: 6)
                }

                Divider().background(AppTheme.borderGlass)

                // Monthly budget input
                HStack {
                    Text("Monthly Budget")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("$")
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textSecondary)
                        TextField("100.00", value: Binding(
                            get: { appState.monthlyBudget },
                            set: { appState.monthlyBudget = $0 }
                        ), format: .number.precision(.fractionLength(2)))
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textPrimary)
                            .textFieldStyle(.plain)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.bgPrimary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                // Monthly progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("This Month")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                        Text(String(format: "$%.2f / $%.2f (%.0f%%)", appState.costMonth, appState.monthlyBudget, appState.monthlySpendingPercentage * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    let mp = min(appState.monthlySpendingPercentage, 1.0)
                    ProgressBar(progress: mp,
                                color: mp > 0.8 ? AppTheme.error : mp > 0.6 ? AppTheme.warning : AppTheme.success)
                        .frame(height: 6)
                }

                Divider().background(AppTheme.borderGlass)

                // Budget alerts toggle
                Toggle(isOn: Binding(
                    get: { appState.budgetAlertsEnabled },
                    set: { appState.budgetAlertsEnabled = $0 }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.warning)
                        Text("Budget Alerts")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                .toggleStyle(.switch)
                .tint(AppTheme.accent)

                Text("Notifies at 80% and 100% of daily/monthly budgets")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)

                // Reset daily counter
                Button(action: { appState.resetDailySpending() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Daily Counter")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Usage Statistics

    // Chart colors
    private static let chartInputColor = Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255)   // blue
    private static let chartOutputColor = Color(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255)  // purple

    /// Sample data shown when no real usage has been recorded yet.
    private static func sampleWeeklyData() -> [DailyTokenUsage] {
        let calendar = Calendar.current
        let today = Date()
        let samples: [(Int, Int)] = [
            (4200, 1800), (6100, 2900), (3500, 1200),
            (8300, 3700), (5600, 2400), (2100, 900), (7400, 3100)
        ]
        let dateKeyFormatter = DateFormatter()
        dateKeyFormatter.dateFormat = "yyyy-MM-dd"
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 6, to: today)!
            let key = dateKeyFormatter.string(from: date)
            return DailyTokenUsage(
                dateKey: key, date: date,
                inputTokens: samples[offset].0,
                outputTokens: samples[offset].1
            )
        }
    }

    private var usageStatisticsSection: some View {
        let realData = appState.getWeeklyTokenUsage()
        let hasRealData = realData.contains { $0.totalTokens > 0 }
        let weeklyData = hasRealData ? realData : Self.sampleWeeklyData()
        let maxTokens = weeklyData.map { $0.totalTokens }.max() ?? 1
        let totalInput = weeklyData.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = weeklyData.reduce(0) { $0 + $1.outputTokens }
        let totalCost = weeklyData.reduce(0.0) { $0 + $1.estimatedCost }

        return SettingsSection(title: "Usage Statistics", icon: "chart.bar.xaxis") {
            VStack(spacing: 16) {
                // Period total header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last 7 Days")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textMuted)
                        Text(formatTokens(totalInput + totalOutput) + " tokens")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Spacer()
                    if !hasRealData {
                        Text("Sample Data")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.bgSecondary.opacity(0.6))
                            .cornerRadius(4)
                    }
                }

                // Bar chart
                HStack(alignment: .bottom, spacing: 8) {
                    // Y-axis max label
                    VStack {
                        Text(formatTokens(maxTokens))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                        Text("0")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .frame(width: 36, height: 120)

                    // Bars
                    ForEach(weeklyData) { day in
                        VStack(spacing: 2) {
                            // Token count label above bar
                            Text(day.totalTokens > 0 ? formatTokens(day.totalTokens) : "")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted)
                                .frame(height: 12)

                            // Stacked bar
                            GeometryReader { geo in
                                let totalHeight = geo.size.height
                                let scale = maxTokens > 0 ? totalHeight / CGFloat(maxTokens) : 0
                                let inputHeight = max(CGFloat(day.inputTokens) * scale, day.inputTokens > 0 ? 2 : 0)
                                let outputHeight = max(CGFloat(day.outputTokens) * scale, day.outputTokens > 0 ? 2 : 0)

                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    // Output tokens (top, purple)
                                    if day.outputTokens > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Self.chartOutputColor)
                                            .frame(height: outputHeight)
                                    }
                                    // Input tokens (bottom, blue)
                                    if day.inputTokens > 0 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Self.chartInputColor)
                                            .frame(height: inputHeight)
                                    }
                                }
                            }
                            .frame(height: 120)

                            // Day label
                            Text(day.dayLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }
                }
                .padding(.top, 4)

                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.chartInputColor)
                            .frame(width: 12, height: 12)
                        Text("Input")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.chartOutputColor)
                            .frame(width: 12, height: 12)
                        Text("Output")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }

                Divider().background(AppTheme.borderGlass)

                // Summary
                VStack(spacing: 8) {
                    HStack {
                        Text("Total tokens (7 days)")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text(formatTokens(totalInput + totalOutput))
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    HStack {
                        Text("Input / Output")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text("\(formatTokens(totalInput)) / \(formatTokens(totalOutput))")
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    HStack {
                        Text("Estimated cost (7 days)")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text(String(format: "$%.2f", totalCost))
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.accent)
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var timestampDisplayDescription: String {
        switch appState.timestampDisplay {
        case "hidden": return "Timestamps are not shown on messages"
        case "hover": return "Timestamps appear when you hover over a message"
        case "always": return "Timestamps are always shown below messages (HH:mm)"
        case "relative": return "Shows relative time (e.g. \"2m ago\") that auto-updates"
        default: return ""
        }
    }

    // MARK: - Theme Presets Gallery

    private var themePresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Theme Presets")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if appState.currentThemePresetName == nil {
                    Text("Custom")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.bgPrimary.opacity(0.4))
                        .clipShape(Capsule())
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(ThemePreset.themePresets) { preset in
                    themePresetCard(preset)
                }
            }
        }
    }

    private func themePresetCard(_ preset: ThemePreset) -> some View {
        let isActive = appState.currentThemePresetName == preset.name
        let previewTheme = SyntaxTheme.named(preset.syntaxTheme)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                appState.applyThemePreset(preset)
            }
        }) {
            VStack(spacing: 6) {
                // Mini mockup area
                VStack(spacing: 0) {
                    // Title bar mockup
                    HStack(spacing: 3) {
                        Circle().fill(Color.red.opacity(0.7)).frame(width: 4, height: 4)
                        Circle().fill(Color.yellow.opacity(0.7)).frame(width: 4, height: 4)
                        Circle().fill(Color.green.opacity(0.7)).frame(width: 4, height: 4)
                        Spacer()
                    }
                    .padding(.horizontal, 5)
                    .padding(.top, 4)
                    .padding(.bottom, 3)

                    // Simulated chat lines
                    VStack(alignment: .leading, spacing: preset.density == "compact" ? 2 : preset.density == "spacious" ? 5 : 3) {
                        HStack(spacing: 3) {
                            Circle().fill(preset.accentColor.opacity(0.6))
                                .frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(AppTheme.textSecondary.opacity(0.3))
                                .frame(width: 36, height: 3)
                            Spacer()
                        }
                        HStack(spacing: 3) {
                            Circle().fill(AppTheme.textMuted.opacity(0.4))
                                .frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(preset.accentColor.opacity(0.25))
                                .frame(width: 28, height: 3)
                            Spacer()
                        }
                        // Code block mockup
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(previewTheme.keyword.opacity(0.7))
                                .frame(width: 12, height: 3)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(previewTheme.string.opacity(0.7))
                                .frame(width: 18, height: 3)
                            Spacer()
                        }
                        .padding(3)
                        .background(previewTheme.background.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                }
                .background(AppTheme.bgPrimary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Label
                HStack(spacing: 3) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 8))
                        .foregroundColor(isActive ? preset.accentColor : AppTheme.textMuted)
                    Text(preset.name)
                        .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? preset.accentColor : AppTheme.textSecondary)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? preset.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? preset.accentColor : Color.white.opacity(0.06), lineWidth: isActive ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) theme preset")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", icon: "paintbrush") {
            VStack(spacing: 14) {
                // Theme Presets
                themePresetsSection

                Divider().background(AppTheme.borderGlass)

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

                // Smart Paste toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Paste")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Detect code, URLs, and JSON when pasting")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                    Toggle("Smart Paste", isOn: $appState.smartPasteEnabled)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .accessibilityLabel("Smart Paste")
                        .accessibilityValue(appState.smartPasteEnabled ? "On" : "Off")
                }

                // Text-to-Speech toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Text-to-Speech")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Show speaker button on assistant messages")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                    Toggle("Text-to-Speech", isOn: Binding(
                        get: { appState.textToSpeechEnabled },
                        set: { newVal in
                            appState.textToSpeechEnabled = newVal
                            if !newVal && appState.isSpeaking {
                                appState.stopSpeaking()
                            }
                        }
                    ))
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .accessibilityLabel("Text-to-Speech")
                        .accessibilityValue(appState.textToSpeechEnabled ? "On" : "Off")
                }

                // Message Timestamps
                VStack(alignment: .leading, spacing: 10) {
                    Text("Message Timestamps")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)

                    Picker("Message Timestamps", selection: $appState.timestampDisplay) {
                        Text("Hidden").tag("hidden")
                        Text("Hover only").tag("hover")
                        Text("Always visible").tag("always")
                        Text("Relative").tag("relative")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(timestampDisplayDescription)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textMuted)
                }

                Divider().background(AppTheme.borderGlass)

                // Chat Font Size
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Chat Font Size")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                        Text("\(Int(appState.chatFontSize)) pt")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    HStack(spacing: 10) {
                        Button(action: { appState.decreaseFontSize() }) {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(AppTheme.accent.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.chatFontSize <= 10)

                        Slider(value: $appState.chatFontSize, in: 10...24, step: 1)
                            .tint(AppTheme.accent)
                            .accessibilityLabel("Chat Font Size")
                            .accessibilityValue("\(Int(appState.chatFontSize)) points")

                        Button(action: { appState.increaseFontSize() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(AppTheme.accent.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.chatFontSize >= 24)

                        Button(action: { appState.resetFontSize() }) {
                            Text("Reset")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.accent.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Live preview
                    Text("Sample message text")
                        .font(.system(size: CGFloat(appState.chatFontSize)))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.bgPrimary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider().background(AppTheme.borderGlass)

                // Display Density
                VStack(alignment: .leading, spacing: 10) {
                    Text("Display Density")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)

                    Picker("Display Density", selection: $appState.displayDensity) {
                        Label("Compact", systemImage: "rectangle.compress.vertical")
                            .tag("compact")
                        Label("Comfortable", systemImage: "rectangle")
                            .tag("comfortable")
                        Label("Spacious", systemImage: "rectangle.expand.vertical")
                            .tag("spacious")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    // Visual preview: 3 mock message lines at selected density
                    VStack(spacing: appState.messageSpacing) {
                        ForEach(["Hey, how can I help?", "Sure, let me look into that.", "Here is what I found."], id: \.self) { line in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(AppTheme.accent.opacity(0.5))
                                    .frame(width: appState.avatarSize * 0.5, height: appState.avatarSize * 0.5)
                                Text(line)
                                    .font(.system(size: appState.displayDensity == "compact" ? 10 : appState.displayDensity == "spacious" ? 13 : 11))
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, appState.messagePadding * 0.7)
                            .padding(.vertical, appState.messagePadding * 0.4)
                            .background(AppTheme.bgPrimary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(8)
                    .background(AppTheme.bgPrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .animation(.easeInOut(duration: 0.2), value: appState.displayDensity)
                }

                Divider().background(AppTheme.borderGlass)

                // Language / Idioma
                VStack(alignment: .leading, spacing: 10) {
                    Text("Language / Idioma")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)

                    Picker("Language", selection: $appState.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: appState.appLanguage) { _ in
                        L10n.current = AppLanguage(rawValue: appState.appLanguage) ?? .system
                    }
                }

                Divider().background(AppTheme.borderGlass)

                // Code Theme
                VStack(alignment: .leading, spacing: 10) {
                    Text("Code Theme")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)

                    Picker("Code Theme", selection: $appState.syntaxTheme) {
                        ForEach(SyntaxTheme.themeNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    // Preview snippet
                    let previewTheme = SyntaxTheme.named(appState.syntaxTheme)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("func ")
                                .foregroundColor(previewTheme.keyword)
                            Text("greet")
                                .foregroundColor(previewTheme.function)
                            Text("(name: ")
                                .foregroundColor(previewTheme.foreground)
                            Text("String")
                                .foregroundColor(previewTheme.type)
                            Text(")")
                                .foregroundColor(previewTheme.foreground)
                        }
                        HStack(spacing: 0) {
                            Text("  ")
                                .foregroundColor(previewTheme.foreground)
                            Text("// say hello")
                                .foregroundColor(previewTheme.comment)
                        }
                        HStack(spacing: 0) {
                            Text("  let ")
                                .foregroundColor(previewTheme.keyword)
                            Text("count ")
                                .foregroundColor(previewTheme.foreground)
                            Text("= ")
                                .foregroundColor(previewTheme.operator)
                            Text("42")
                                .foregroundColor(previewTheme.number)
                        }
                        HStack(spacing: 0) {
                            Text("  print(")
                                .foregroundColor(previewTheme.foreground)
                            Text("\"Hello\"")
                                .foregroundColor(previewTheme.string)
                            Text(")")
                                .foregroundColor(previewTheme.foreground)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(previewTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
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

    // MARK: - Notifications

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior", icon: "bolt.fill") {
            VStack(spacing: 14) {
                // YOLO mode
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOLO Mode")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Skip confirmation dialogs for dangerous actions (delete files, system changes). The agent will execute everything without asking.")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                    Toggle("YOLO Mode", isOn: $appState.yoloMode)
                        .toggleStyle(.switch)
                        .tint(AppTheme.warning)
                        .labelsHidden()
                }

                if appState.yoloMode {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.warning)
                            .font(.system(size: 12))
                        Text("YOLO mode is active — the agent will not ask for confirmation before destructive actions.")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.warning)
                    }
                    .padding(8)
                    .background(AppTheme.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: "Notifications", icon: "bell") {
            VStack(spacing: 14) {
                // Master switch
                HStack {
                    Text("Enable notifications")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Toggle("Enable notifications", isOn: $appState.notificationsEnabled)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .accessibilityLabel("Enable notifications")
                        .accessibilityValue(appState.notificationsEnabled ? "On" : "Off")
                }

                // UX sound effects (send, receive, error)
                HStack {
                    Text("UX sound effects")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Toggle("UX sound effects", isOn: $appState.soundEffectsEnabled)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .accessibilityLabel("UX sound effects")
                        .accessibilityValue(appState.soundEffectsEnabled ? "On" : "Off")
                }

                // Sound on message received
                HStack {
                    Text("Sound on message received")
                        .font(AppTheme.fontBody)
                        .foregroundColor(appState.notificationsEnabled ? AppTheme.textPrimary : AppTheme.textMuted)
                    Spacer()
                    Toggle("Sound on message received", isOn: $appState.notifySoundEnabled)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .disabled(!appState.notificationsEnabled)
                        .accessibilityLabel("Sound on message received")
                        .accessibilityValue(appState.notifySoundEnabled ? "On" : "Off")
                }

                // Notify on task complete
                HStack {
                    Text("Show notification when task completes")
                        .font(AppTheme.fontBody)
                        .foregroundColor(appState.notificationsEnabled ? AppTheme.textPrimary : AppTheme.textMuted)
                    Spacer()
                    Toggle("Notify on task complete", isOn: $appState.notifyOnTaskComplete)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .disabled(!appState.notificationsEnabled)
                        .accessibilityLabel("Show notification when task completes")
                        .accessibilityValue(appState.notifyOnTaskComplete ? "On" : "Off")
                }

                // Notify on agent route
                HStack {
                    Text("Show notification when agent routes")
                        .font(AppTheme.fontBody)
                        .foregroundColor(appState.notificationsEnabled ? AppTheme.textPrimary : AppTheme.textMuted)
                    Spacer()
                    Toggle("Notify on agent route", isOn: $appState.notifyOnAgentRoute)
                        .toggleStyle(.switch)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .disabled(!appState.notificationsEnabled)
                        .accessibilityLabel("Show notification when agent routes")
                        .accessibilityValue(appState.notifyOnAgentRoute ? "On" : "Off")
                }

                Divider().background(AppTheme.borderGlass)

                // Notification sound picker
                HStack {
                    Text("Notification sound")
                        .font(AppTheme.fontBody)
                        .foregroundColor(appState.notificationsEnabled ? AppTheme.textPrimary : AppTheme.textMuted)
                    Spacer()
                    Picker("Notification sound", selection: $appState.notificationSound) {
                        Text("Default").tag("default")
                        Text("Ping").tag("ping")
                        Text("Pop").tag("pop")
                        Text("Glass").tag("glass")
                        Text("None").tag("none")
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.accent)
                    .labelsHidden()
                    .disabled(!appState.notificationsEnabled)
                    .accessibilityLabel("Notification sound")
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

    // MARK: - Backup & Restore

    private var backupRestoreSection: some View {
        SettingsSection(title: "Backup & Restore", icon: "externaldrive.fill") {
            VStack(spacing: 12) {
                // What's included
                VStack(alignment: .leading, spacing: 6) {
                    Text("Included in backup:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    HStack(spacing: 16) {
                        ForEach(["Appearance", "Notifications", "Budgets", "Preferences"], id: \.self) { item in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.success)
                                Text(item)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textMuted)
                            }
                        }
                    }
                }

                Divider().background(AppTheme.borderGlass)

                // Last backup date
                if !appState.lastBackupDate.isEmpty {
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        Text("Last backup: \(appState.lastBackupDate)")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                    }
                }

                // Buttons
                HStack(spacing: 10) {
                    // Export
                    Button(action: {
                        let panel = NSSavePanel()
                        panel.title = "Export Settings"
                        panel.nameFieldStringValue = "osai-settings.json"
                        panel.allowedContentTypes = [.json]
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            let data = appState.exportSettings()
                            try? data.write(to: url)
                            appState.lastBackupDate = AppState.mediumDateTimeFormatter.string(from: Date())
                            appState.showToast("Settings exported successfully", type: .success)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Settings")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Import
                    Button(action: {
                        let panel = NSOpenPanel()
                        panel.title = "Import Settings"
                        panel.allowedContentTypes = [.json]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            if let data = try? Data(contentsOf: url) {
                                appState.importSettings(from: data)
                                appState.showToast("Settings imported successfully", type: .success)
                            } else {
                                appState.showToast("Failed to read settings file", type: .error)
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Settings")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Reset
                    Button(action: {
                        showResetConfirmation = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Settings")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.error)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.error.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("Reset All Settings", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                appState.resetAllSettings()
                appState.showToast("All settings reset to defaults", type: .success)
            }
        } message: {
            Text("This will reset all appearance, notification, budget, and preference settings to their default values. This action cannot be undone.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(title: "About", icon: "info.circle") {
            VStack(spacing: 16) {
                // App identity
                HStack(spacing: 14) {
                    GhostIcon(size: 48, animate: false)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("OSAI")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Version 0.1")
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()
                }

                Divider().background(AppTheme.borderGlass)

                // Build info
                VStack(spacing: 8) {
                    HStack {
                        Text("Swift")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text("6.0")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    HStack {
                        Text("macOS Target")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text("14.0+")
                            .font(.system(size: 11, design: .monospaced))
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
                }

                Divider().background(AppTheme.borderGlass)

                // Links
                HStack(spacing: 12) {
                    aboutLinkButton(label: "GitHub Repository", icon: "link", url: "https://github.com/AdrianTomin/osai")
                    aboutLinkButton(label: "Report a Bug", icon: "ladybug", url: "https://github.com/AdrianTomin/osai/issues/new")
                    aboutLinkButton(label: "Documentation", icon: "book", url: "https://github.com/AdrianTomin/osai#readme")
                    Spacer()
                }

                Divider().background(AppTheme.borderGlass)

                // Credits
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "swift")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accent)
                        Text("Built with SwiftUI")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accent)
                        Text("Powered by AI")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }

                // What's New button
                Button(action: { showChangelog = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("What's New")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showChangelog) {
                    ChangelogView(isPresented: $showChangelog)
                }
            }
        }
    }

    private func aboutLinkButton(label: String, icon: String, url: String) -> some View {
        Button(action: {
            if let linkURL = URL(string: url) {
                NSWorkspace.shared.open(linkURL)
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(AppTheme.accent)
        }
        .buttonStyle(.plain)
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
        case "groq": return "Groq"
        case "mistral": return "Mistral"
        case "meta": return "Meta"
        case "qwen": return "Qwen"
        default: return provider.capitalized
        }
    }

    private func modelDisplayName(_ model: String) -> String {
        // Use shared allModelDefinitions first
        if let def = allModelDefinitions.first(where: { $0.id == model }) {
            return def.displayName
        }
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

// MARK: - Changelog View

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let changes: [String]
}

private let changelogEntries: [ChangelogEntry] = [
    ChangelogEntry(
        version: "0.1",
        date: "March 2026",
        changes: [
            "Initial desktop app release with SwiftUI",
            "Ghost icon branding and glass-card UI theme",
            "Settings panel with API key management",
            "Multi-provider support: Anthropic, OpenAI, Google, OpenRouter, xAI, DeepSeek",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r46",
        date: "March 2026",
        changes: [
            "Gateway background mode with auto-start on login",
            "Claude Code backend for agents",
            "Removed default agent auto-install for cleaner setup",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r44",
        date: "March 2026",
        changes: [
            "Updated default agents: product, organizer, writer, design",
            "Improved news and research agent capabilities",
            "Specialized agent routing with auto-dispatch by intent",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r42",
        date: "March 2026",
        changes: [
            "Major token optimization with dynamic tool loading",
            "Prompt caching for reduced API costs",
            "Lazy memory loading for faster startup",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r40",
        date: "March 2026",
        changes: [
            "Budget and spending controls in settings",
            "Usage statistics with token tracking charts",
            "Notification preferences for alerts and updates",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r38",
        date: "March 2026",
        changes: [
            "Appearance customization with accent color presets",
            "Light and dark mode support with adaptive colors",
            "Backup and restore for configuration data",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r35",
        date: "February 2026",
        changes: [
            "Dashboard view with system status overview",
            "Agent management panel with install/remove",
            "Task cards with status tracking and progress",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r30",
        date: "February 2026",
        changes: [
            "Chat interface with streaming message display",
            "Conversation history and sidebar navigation",
            "Input field with send action and keyboard shortcuts",
        ]
    ),
    ChangelogEntry(
        version: "0.1-r27",
        date: "February 2026",
        changes: [
            "Core architecture: AppState, ConfigService, OSAIService",
            "Gateway connectivity and health check monitoring",
            "Model selection with provider-aware routing",
        ]
    ),
]

struct ChangelogView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.accent)
                    Text("What's New")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().background(AppTheme.borderGlass)

            // Scrollable timeline
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(changelogEntries.enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .top, spacing: 16) {
                            // Timeline column
                            VStack(spacing: 0) {
                                // Dot
                                Circle()
                                    .fill(index == 0 ? AppTheme.accent : AppTheme.textMuted.opacity(0.5))
                                    .frame(width: 12, height: 12)
                                    .shadow(color: index == 0 ? AppTheme.accent.opacity(0.5) : .clear, radius: 4)

                                // Connecting line
                                if index < changelogEntries.count - 1 {
                                    Rectangle()
                                        .fill(AppTheme.borderGlass)
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 12)

                            // Version card
                            GlassCard(hoverEnabled: false) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("v\(entry.version)")
                                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                                            .foregroundColor(index == 0 ? AppTheme.accent : AppTheme.textPrimary)
                                        Spacer()
                                        Text(entry.date)
                                            .font(AppTheme.fontCaption)
                                            .foregroundColor(AppTheme.textMuted)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(entry.changes, id: \.self) { change in
                                            HStack(alignment: .top, spacing: 8) {
                                                Circle()
                                                    .fill(AppTheme.accent.opacity(0.6))
                                                    .frame(width: 5, height: 5)
                                                    .padding(.top, 5)
                                                Text(change)
                                                    .font(AppTheme.fontBody)
                                                    .foregroundColor(AppTheme.textSecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, index < changelogEntries.count - 1 ? 4 : 0)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 520, height: 580)
        .background(AppTheme.bgPrimary)
    }
}
