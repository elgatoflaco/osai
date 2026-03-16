import SwiftUI

// MARK: - Calendar Browser View

/// A compact calendar widget for browsing conversations by date.
/// Designed to fit in the chat sidebar as an alternative to the list view.
struct CalendarBrowserView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedDate: Date?
    @State private var displayedMonth: Date = Date()

    private let calendar = Calendar.current
    private let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let dayAbbreviations = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private var conversationsByDay: [DateComponents: [Conversation]] {
        Dictionary(grouping: appState.conversations.filter { !$0.isArchived }) { conv in
            calendar.dateComponents([.year, .month, .day], from: conv.createdAt)
        }
    }

    private var displayedYear: Int {
        calendar.component(.year, from: displayedMonth)
    }

    private var displayedMonthValue: Int {
        calendar.component(.month, from: displayedMonth)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    /// All day dates to render in the calendar grid (including leading/trailing days from adjacent months).
    private var calendarDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        // weekday is 1-based (Sunday=1), we need 0-based offset
        let leadingEmpty = firstWeekday - calendar.firstWeekday
        let adjustedLeading = leadingEmpty < 0 ? leadingEmpty + 7 : leadingEmpty

        var days: [CalendarDay] = []

        // Leading days from previous month
        if adjustedLeading > 0 {
            let prevMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
            let prevMonthRange = calendar.range(of: .day, in: .month, for: prevMonth)!
            let prevMonthLastDay = prevMonthRange.upperBound - 1
            for i in 0..<adjustedLeading {
                let day = prevMonthLastDay - adjustedLeading + 1 + i
                if let date = calendar.date(from: DateComponents(year: calendar.component(.year, from: prevMonth),
                                                                  month: calendar.component(.month, from: prevMonth),
                                                                  day: day)) {
                    days.append(CalendarDay(date: date, dayNumber: day, isCurrentMonth: false))
                }
            }
        }

        // Days of current month
        for day in monthRange {
            if let date = calendar.date(from: DateComponents(year: displayedYear,
                                                              month: displayedMonthValue,
                                                              day: day)) {
                days.append(CalendarDay(date: date, dayNumber: day, isCurrentMonth: true))
            }
        }

        // Trailing days to fill the last row
        let remainder = days.count % 7
        if remainder > 0 {
            let trailingCount = 7 - remainder
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
            for day in 1...trailingCount {
                if let date = calendar.date(from: DateComponents(year: calendar.component(.year, from: nextMonth),
                                                                  month: calendar.component(.month, from: nextMonth),
                                                                  day: day)) {
                    days.append(CalendarDay(date: date, dayNumber: day, isCurrentMonth: false))
                }
            }
        }

        return days
    }

    private func conversationCount(for date: Date) -> Int {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return conversationsByDay[comps]?.count ?? 0
    }

    private func conversationsForDate(_ date: Date) -> [Conversation] {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return (conversationsByDay[comps] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let sel = selectedDate else { return false }
        return calendar.isDate(sel, inSameDayAs: date)
    }

    /// Color intensity for conversation dot based on count.
    private func dotOpacity(count: Int) -> Double {
        if count == 0 { return 0 }
        if count == 1 { return 0.4 }
        if count <= 3 { return 0.65 }
        return 1.0
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarGrid
            if let date = selectedDate {
                dayDetail(for: date)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: 6) {
            // Month navigation header
            HStack {
                Button(action: { navigateMonth(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                Button(action: { navigateMonth(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Day-of-week header
            LazyVGrid(columns: dayColumns, spacing: 0) {
                ForEach(dayAbbreviations, id: \.self) { abbr in
                    Text(abbr)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(width: 28, height: 16)
                }
            }

            // Day cells
            LazyVGrid(columns: dayColumns, spacing: 2) {
                ForEach(calendarDays) { day in
                    dayCell(day)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.borderGlass, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let count = conversationCount(for: day.date)
        let today = isToday(day.date)
        let selected = isSelected(day.date)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                if selected {
                    selectedDate = nil
                } else {
                    selectedDate = day.date
                }
            }
        }) {
            VStack(spacing: 1) {
                Text("\(day.dayNumber)")
                    .font(.system(size: 11))
                    .foregroundColor(
                        selected ? .white :
                        !day.isCurrentMonth ? AppTheme.textMuted.opacity(0.4) :
                        today ? AppTheme.accent :
                        AppTheme.textPrimary
                    )

                // Conversation dot indicator
                Circle()
                    .fill(AppTheme.accent.opacity(dotOpacity(count: count)))
                    .frame(width: 4, height: 4)
                    .opacity(count > 0 ? 1 : 0)
            }
            .frame(width: 28, height: 28)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.accent)
                    } else if today {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppTheme.accent, lineWidth: 1)
                    } else {
                        Color.clear
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day Detail

    private func dayDetail(for date: Date) -> some View {
        let convs = conversationsForDate(date)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let dateLabel = formatter.string(from: date)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dateLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(convs.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(AppTheme.accent.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)

            if convs.isEmpty {
                HStack {
                    Spacer()
                    Text("No conversations")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(convs) { conv in
                            calendarConversationRow(conv)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private func calendarConversationRow(_ conv: Conversation) -> some View {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timeStr = timeFormatter.string(from: conv.createdAt)

        return Button(action: {
            appState.openConversation(conv)
        }) {
            HStack(spacing: 6) {
                Text(timeStr)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
                    .frame(width: 52, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(conv.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("\(conv.messages.count) msg")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)

                        if let agent = conv.agentName {
                            Text(agent)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(AppTheme.accent)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(appState.activeConversation?.id == conv.id
                          ? AppTheme.accent.opacity(0.12)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func navigateMonth(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
                displayedMonth = newMonth
                selectedDate = nil
            }
        }
    }
}

// MARK: - Calendar Day Model

struct CalendarDay: Identifiable {
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)-\(isCurrentMonth)"
    }
}
