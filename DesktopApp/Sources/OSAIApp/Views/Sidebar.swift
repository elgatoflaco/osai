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
                        hoveredItem = hovering ? item : nil
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Gateway status
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.gatewayRunning ? AppTheme.success : AppTheme.textMuted)
                    .frame(width: 8, height: 8)

                if !appState.sidebarCollapsed {
                    Text(appState.gatewayRunning ? "Gateway active" : "Gateway off")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()
                .background(AppTheme.borderGlass)
                .padding(.horizontal, 16)

            // Bottom controls
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.isDarkMode.toggle()
                    }
                }) {
                    Image(systemName: appState.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                if !appState.sidebarCollapsed {
                    Spacer()
                }

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.sidebarCollapsed.toggle()
                    }
                }) {
                    Image(systemName: appState.sidebarCollapsed ? "sidebar.left" : "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
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
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(width: 24)

                if !isCollapsed {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)

                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppTheme.accent.opacity(0.12) : (isHovered ? AppTheme.bgCard.opacity(0.5) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.2) : .clear, lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
    }
}
