import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredItem: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            // Ghost branding
            VStack(spacing: 8) {
                GhostIcon(size: appState.sidebarCollapsed ? 32 : 44)

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
                        isHovered: hoveredItem == item
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

            // Separator
            Rectangle()
                .fill(AppTheme.borderGlass)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

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
        .frame(width: appState.sidebarCollapsed ? 64 : 200)
        .background(AppTheme.bgSecondary.opacity(0.5))
        .background(.ultraThinMaterial)
    }
}

struct SidebarButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let isCollapsed: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Accent left border indicator for active tab
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? AppTheme.accent : .clear)
                    .frame(width: 3, height: 20)
                    .padding(.trailing, isCollapsed ? 0 : 8)

                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppTheme.accent : (isHovered ? AppTheme.textPrimary : AppTheme.textSecondary))
                    .frame(width: 28, height: 28)

                if !isCollapsed {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? AppTheme.textPrimary : (isHovered ? AppTheme.textPrimary : AppTheme.textSecondary))
                        .padding(.leading, 6)

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
        .help(isCollapsed ? item.rawValue : "")
    }
}
