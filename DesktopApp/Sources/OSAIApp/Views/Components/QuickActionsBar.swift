import SwiftUI

struct ChatQuickActionsBar: View {
    let actions: [ChatQuickAction]
    @Binding var isCollapsed: Bool
    let onAction: (ChatQuickAction) -> Void

    @State private var hoveredActionId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Chevron toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Show quick actions" : "Hide quick actions")

                if isCollapsed {
                    Text("Quick Actions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.leading, 2)
                }

                if !isCollapsed {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(actions) { action in
                                quickActionPill(action)
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 8)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isCollapsed ? 4 : 6)
            .background(AppTheme.bgGlass)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(AppTheme.borderGlass),
                alignment: .bottom
            )
        }
    }

    @ViewBuilder
    private func quickActionPill(_ action: ChatQuickAction) -> some View {
        let isHovered = hoveredActionId == action.id

        Button(action: { onAction(action) }) {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 9))
                Text(action.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isHovered ? AppTheme.accent : AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(isHovered ? AppTheme.accent.opacity(0.12) : AppTheme.bgCard.opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(isHovered ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredActionId = hovering ? action.id : nil
            }
        }
        .help(action.prompt)
    }
}
