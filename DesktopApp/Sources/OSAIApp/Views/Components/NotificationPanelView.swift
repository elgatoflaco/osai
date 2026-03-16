import SwiftUI

struct NotificationPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notifications")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                if !appState.notifications.isEmpty {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.markAllRead()
                        }
                    }) {
                        Text("Mark all read")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.clearNotifications()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all notifications")
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(AppTheme.borderGlass)
                .frame(height: 1)

            // Notification list
            if appState.notifications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.textMuted)
                    Text("No notifications")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.notifications) { notification in
                            NotificationRow(notification: notification)
                                .onTapGesture {
                                    if let idx = appState.notifications.firstIndex(where: { $0.id == notification.id }) {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            appState.notifications[idx].isRead = true
                                        }
                                    }
                                }

                            if notification.id != appState.notifications.last?.id {
                                Rectangle()
                                    .fill(AppTheme.borderGlass.opacity(0.5))
                                    .frame(height: 1)
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 340, height: 420)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.borderGlass, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 10)
    }
}

struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Type icon
            Image(systemName: notification.type.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(notification.type.color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.title)
                        .font(.system(size: 12, weight: notification.isRead ? .medium : .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(notification.relativeTime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                }

                Text(notification.message)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(notification.isRead ? Color.clear : notification.type.color.opacity(0.04))
        .contentShape(Rectangle())
    }
}
