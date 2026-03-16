import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredItem: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            // Ghost branding
            VStack(spacing: 8) {
                GhostIcon(size: appState.sidebarCollapsed ? 32 : 44, isProcessing: appState.isProcessing)

                if !appState.sidebarCollapsed {
                    Text("osai")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Navigation
            VStack(spacing: 4) {
                ForEach(SidebarItem.allCases) { item in
                    SidebarButton(
                        item: item,
                        isSelected: appState.selectedTab == item,
                        isCollapsed: appState.sidebarCollapsed,
                        isHovered: hoveredItem == item,
                        isProcessing: item == .chat && appState.isProcessing,
                        contextPressureHigh: item == .chat && appState.contextPressurePercent > 75
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.selectedTab = item
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            hoveredItem = hovering ? item : nil
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Processing status bar
            if appState.isProcessing {
                ProcessingStatusBar(
                    isCollapsed: appState.sidebarCollapsed,
                    contextPressurePercent: appState.contextPressurePercent
                ) {
                    appState.cancelProcessing()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, appState.sidebarCollapsed ? 8 : 16)
                .padding(.bottom, 8)
            }

            // Context pressure warning (shown when not processing but pressure is high)
            if !appState.isProcessing && appState.contextPressurePercent > 75 {
                ContextPressureBar(
                    isCollapsed: appState.sidebarCollapsed,
                    percent: appState.contextPressurePercent
                )
                .transition(.opacity)
                .padding(.horizontal, appState.sidebarCollapsed ? 8 : 16)
                .padding(.bottom, 8)
            }

            // Separator
            Rectangle()
                .fill(AppTheme.borderGlass)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Notification bell
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    appState.showNotificationPanel.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 24, height: 24)

                        if appState.unreadNotificationCount > 0 {
                            Text("\(min(appState.unreadNotificationCount, 99))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(AppTheme.error)
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }

                    if !appState.sidebarCollapsed {
                        Text("Notifications")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)

                        Spacer()

                        if appState.unreadNotificationCount > 0 {
                            Text("\(appState.unreadNotificationCount)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                }
                .padding(.horizontal, appState.sidebarCollapsed ? 0 : 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifications")
            .accessibilityValue(appState.unreadNotificationCount > 0 ? "\(appState.unreadNotificationCount) unread" : "No unread")
            .help("Notifications")
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .popover(isPresented: $appState.showNotificationPanel, arrowEdge: .trailing) {
                NotificationPanelView()
                    .environmentObject(appState)
            }

            // Gateway status (clickable)
            Button(action: {
                appState.toggleGateway()
            }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.gatewayRunning ? AppTheme.success : AppTheme.error)
                        .frame(width: 8, height: 8)
                        .shadow(color: appState.gatewayRunning ? AppTheme.success.opacity(0.5) : .clear, radius: 4)

                    if !appState.sidebarCollapsed {
                        Text("Gateway")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)

                        Spacer()

                        Text(appState.gatewayRunning ? "ON" : "OFF")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(appState.gatewayRunning ? AppTheme.success : AppTheme.textMuted)
                    }
                }
                .padding(.horizontal, appState.sidebarCollapsed ? 0 : 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gateway")
            .accessibilityValue(appState.gatewayRunning ? "Running" : "Stopped")
            .accessibilityHint("Double tap to toggle gateway")
            .help("Toggle gateway")
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Dark/light mode toggle
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.isDarkMode.toggle()
                    }
                }) {
                    Image(systemName: appState.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.isDarkMode ? "Switch to light mode" : "Switch to dark mode")
                .help(appState.isDarkMode ? "Switch to light mode" : "Switch to dark mode")

                if !appState.sidebarCollapsed {
                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            appState.sidebarCollapsed.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse sidebar")
                    .help("Collapse sidebar")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            // Version label
            if !appState.sidebarCollapsed {
                Text("v0.1")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.bottom, 12)
            } else {
                Text("v0.1")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: appState.sidebarCollapsed ? 64 : appState.sidebarWidth)
        .background(AppTheme.bgSecondary.opacity(0.5))
        .background(.ultraThinMaterial)
        .animation(.easeOut(duration: 0.25), value: appState.isProcessing)
        .animation(.easeOut(duration: 0.25), value: appState.contextPressurePercent > 75)
    }
}

// MARK: - Processing Status Bar

struct ProcessingStatusBar: View {
    let isCollapsed: Bool
    let contextPressurePercent: Int
    let onCancel: () -> Void

    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        if isCollapsed {
            // Compact: just the animated ghost
            VStack(spacing: 4) {
                GhostIcon(size: 18, animate: true, isProcessing: true, tint: AppTheme.accent)
                    .opacity(pulseOpacity)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(width: 16, height: 16)
                        .background(AppTheme.bgCard.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel processing")
                .help("Cancel")
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseOpacity = 1.0
                }
            }
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    GhostIcon(size: 16, animate: true, isProcessing: true, tint: AppTheme.accent)
                        .opacity(pulseOpacity)

                    Text("Processing...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.textMuted)
                            .frame(width: 18, height: 18)
                            .background(AppTheme.bgCard.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel processing")
                    .help("Cancel processing")
                }

                // Context pressure during processing
                if contextPressurePercent > 75 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(contextPressureColor)
                            .frame(width: 5, height: 5)

                        Text("Context: \(contextPressurePercent)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(contextPressureColor)

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.bgCard.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppTheme.accent.opacity(0.15), lineWidth: 1)
                    )
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseOpacity = 1.0
                }
            }
        }
    }

    private var contextPressureColor: Color {
        if contextPressurePercent > 90 {
            return AppTheme.error
        } else {
            return AppTheme.warning
        }
    }
}

// MARK: - Context Pressure Bar (when not processing)

struct ContextPressureBar: View {
    let isCollapsed: Bool
    let percent: Int

    var body: some View {
        if isCollapsed {
            Circle()
                .fill(pressureColor)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Context pressure \(percent) percent")
                .help("Context: \(percent)%")
        } else {
            HStack(spacing: 4) {
                Circle()
                    .fill(pressureColor)
                    .frame(width: 5, height: 5)

                Text("Context: \(percent)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(pressureColor)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Context pressure \(percent) percent")
        }
    }

    private var pressureColor: Color {
        if percent > 90 {
            return AppTheme.error
        } else {
            return AppTheme.warning
        }
    }
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let isCollapsed: Bool
    let isHovered: Bool
    var isProcessing: Bool = false
    var contextPressureHigh: Bool = false
    let action: () -> Void

    @State private var ringRotation: Double = 0
    @State private var dotPulse: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Accent left border indicator for active tab
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? AppTheme.accent : .clear)
                    .frame(width: 3, height: 20)
                    .padding(.trailing, isCollapsed ? 0 : 8)

                // Icon with optional processing/context indicators
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? AppTheme.accent : (isHovered ? AppTheme.textPrimary : AppTheme.textSecondary))
                        .frame(width: 28, height: 28)

                    // Processing ring indicator
                    if isProcessing {
                        Circle()
                            .trim(from: 0, to: 0.65)
                            .stroke(AppTheme.accent.opacity(0.7), lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                            .rotationEffect(.degrees(ringRotation))
                            .offset(x: 2, y: -2)
                            .onAppear {
                                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                    ringRotation = 360
                                }
                            }
                            .onDisappear {
                                ringRotation = 0
                            }
                    }

                    // Context pressure dot (only when not processing, to avoid clutter)
                    if !isProcessing && contextPressureHigh {
                        Circle()
                            .fill(AppTheme.warning)
                            .frame(width: 6, height: 6)
                            .opacity(dotPulse ? 1.0 : 0.5)
                            .offset(x: 2, y: -2)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                    dotPulse = true
                                }
                            }
                            .onDisappear {
                                dotPulse = false
                            }
                    }
                }

                if !isCollapsed {
                    if isProcessing {
                        Text("Chat...")
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? AppTheme.textPrimary : (isHovered ? AppTheme.textPrimary : AppTheme.textSecondary))
                            .padding(.leading, 6)
                    } else {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? AppTheme.textPrimary : (isHovered ? AppTheme.textPrimary : AppTheme.textSecondary))
                            .padding(.leading, 6)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.accent.opacity(0.08) : (isHovered ? AppTheme.bgCard.opacity(0.6) : .clear))
            )
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.rawValue) tab")
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityHint(isProcessing ? "Processing" : (contextPressureHigh ? "Context pressure high" : "Double tap to navigate"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isCollapsed ? item.rawValue : "")
    }
}
