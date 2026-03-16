import SwiftUI

/// Compact task card used on the Dashboard overview (horizontal scroll).
/// For the full task list, see TaskCardImproved in TasksView.swift.
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
                    Image(systemName: delivery.icon)
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

                Text("\(task.runCount) run\(task.runCount == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
            }

            if let lastRun = task.lastRun {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text(relativeTime(lastRun))
                        .font(.system(size: 9))
                }
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

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
