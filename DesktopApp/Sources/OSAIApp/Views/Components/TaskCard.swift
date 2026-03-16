import SwiftUI

struct TaskCard: View {
    let task: TaskInfo
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(task.enabled ? AppTheme.success : AppTheme.textMuted)
                    .frame(width: 8, height: 8)

                Text(task.id)
                    .font(AppTheme.fontCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                if let delivery = task.delivery {
                    Image(systemName: platformIcon(delivery.platform))
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            Text(task.description.isEmpty ? task.command : task.description)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(2)

            HStack {
                Label(task.schedule.displayLabel, systemImage: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textMuted)

                Spacer()

                Text("\(task.runCount)x")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isHovered ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 20 : 12, x: 0, y: isHovered ? 8 : 4)
        .offset(y: isHovered ? -2 : 0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func platformIcon(_ platform: String) -> String {
        switch platform.lowercased() {
        case "discord": return "message.badge.circle"
        case "whatsapp": return "phone.circle"
        case "watch": return "applewatch"
        default: return "arrow.up.circle"
        }
    }
}
