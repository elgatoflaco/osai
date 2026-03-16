import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveredItem: SidebarItem?

    /// Returns the badge count for a given sidebar item.
    private func badgeCount(for item: SidebarItem) -> Int {
        switch item {
        case .chat: return appState.unreadConversationIds.count
        case .tasks: return appState.activeTaskCount
        case .agents: return appState.availableAgentCount
        case .home, .settings: return 0
        }
    }

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("OSAI")
            .accessibilityAddTraits(.isHeader)

            // Navigation
            VStack(spacing: 4) {
                ForEach(SidebarItem.allCases) { item in
                    SidebarButton(
                        item: item,
                        isSelected: appState.selectedTab == item,
                        isCollapsed: appState.sidebarCollapsed,
                        isHovered: hoveredItem == item,
                        isProcessing: item == .chat && appState.isProcessing,
                        contextPressureHigh: item == .chat && appState.contextPressurePercent > 75,
                        badgeCount: badgeCount(for: item)
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
            .accessibilityLabel("Navigation")

            // Mini Calendar Widget
            if !appState.sidebarCollapsed {
                MiniCalendarWidget()
                    .environmentObject(appState)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            } else {
                // Collapsed: just the toggle button
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        appState.showSidebarCalendar.toggle()
                    }
                }) {
                    Image(systemName: appState.showSidebarCalendar ? "calendar.circle.fill" : "calendar.circle")
                        .font(.system(size: 17))
                        .foregroundColor(appState.calendarFilterDate != nil ? AppTheme.accent : AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Toggle calendar")
                .padding(.top, 8)
            }

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
            .accessibilityHint("Double tap to \(appState.showNotificationPanel ? "close" : "open") notification panel")
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
                    .accessibilityHint("Double tap to collapse the sidebar")
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
                    .accessibilityLabel("OSAI version 0.1")
            } else {
                Text("v0.1")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.bottom, 12)
                    .accessibilityLabel("OSAI version 0.1")
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
                    .accessibilityHidden(true)

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
                .accessibilityHint("Double tap to stop the current task")
                .help("Cancel")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Processing in progress")
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
                    .accessibilityHint("Double tap to stop the current task")
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Processing in progress\(contextPressurePercent > 75 ? ", context pressure at \(contextPressurePercent) percent" : "")")
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
    var badgeCount: Int = 0
    let action: () -> Void

    @State private var ringRotation: Double = 0
    @State private var dotPulse: Bool = false
    @State private var badgeVisible: Bool = false

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

                    // Badge count overlay
                    if badgeCount > 0 && !isProcessing {
                        Text("\(min(badgeCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(AppTheme.error)
                            .clipShape(Circle())
                            .offset(x: 5, y: -5)
                            .scaleEffect(badgeVisible ? 1.0 : 0.01)
                            .opacity(badgeVisible ? 1.0 : 0.0)
                            .onAppear {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    badgeVisible = true
                                }
                            }
                            .onDisappear {
                                badgeVisible = false
                            }
                            .onChange(of: badgeCount) { _ in
                                badgeVisible = false
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    badgeVisible = true
                                }
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
        .accessibilityLabel("\(item.rawValue) tab\(badgeCount > 0 ? ", \(badgeCount) items" : "")")
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityHint(isProcessing ? "Processing" : (contextPressureHigh ? "Context pressure high" : "Double tap to navigate"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(isCollapsed ? item.rawValue : "")
    }
}

// MARK: - Mini Calendar Widget

struct MiniCalendarWidget: View {
    @EnvironmentObject var appState: AppState
    @State private var displayedMonth: Date = Date()

    private let calendar = Calendar.current
    private let dayOfWeekSymbols = ["S", "M", "T", "W", "T", "F", "S"]

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var daysInMonth: [DayCell] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start) // 1=Sun
        let leadingBlanks = firstWeekday - 1

        var cells: [DayCell] = []
        // Leading blank cells
        for i in 0..<leadingBlanks {
            cells.append(DayCell(id: -i - 1, day: 0, isBlank: true))
        }
        // Day cells
        for day in monthRange {
            cells.append(DayCell(id: day, day: day, isBlank: false))
        }
        return cells
    }

    private var conversationDays: Set<Int> {
        appState.conversationDatesForMonth(displayedMonth)
    }

    private var conversationColorsByDay: [Int: Set<String>] {
        appState.conversationColorsForMonth(displayedMonth)
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var todayDay: Int? {
        guard isCurrentMonth else { return nil }
        return calendar.component(.day, from: Date())
    }

    private var selectedDay: Int? {
        guard let filterDate = appState.calendarFilterDate,
              calendar.isDate(filterDate, equalTo: displayedMonth, toGranularity: .month) else { return nil }
        return calendar.component(.day, from: filterDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toggle header
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    appState.showSidebarCalendar.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: appState.showSidebarCalendar ? "calendar.circle.fill" : "calendar.circle")
                        .font(.system(size: 13))
                        .foregroundColor(appState.calendarFilterDate != nil ? AppTheme.accent : AppTheme.textSecondary)

                    Text("Calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)

                    Spacer()

                    Image(systemName: appState.showSidebarCalendar ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle calendar")
            .accessibilityValue(appState.showSidebarCalendar ? "expanded" : "collapsed")

            if appState.showSidebarCalendar {
                VStack(spacing: 6) {
                    // Month navigation
                    HStack {
                        Button(action: { navigateMonth(by: -1) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Previous month")

                        Spacer()

                        Text(monthYearString)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)

                        Spacer()

                        if !isCurrentMonth {
                            Button(action: { jumpToToday() }) {
                                Text("Today")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Jump to today")
                        }

                        Button(action: { navigateMonth(by: 1) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Next month")
                    }
                    .padding(.horizontal, 4)

                    // Day of week headers
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                        ForEach(dayOfWeekSymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(AppTheme.textMuted)
                                .frame(height: 16)
                        }
                    }

                    // Day grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                        ForEach(daysInMonth) { cell in
                            if cell.isBlank {
                                Color.clear
                                    .frame(height: 24)
                            } else {
                                CalendarDayButton(
                                    day: cell.day,
                                    isToday: todayDay == cell.day,
                                    isSelected: selectedDay == cell.day,
                                    hasConversations: conversationDays.contains(cell.day),
                                    colorLabels: Array(conversationColorsByDay[cell.day] ?? []).prefix(3).map { $0 }
                                ) {
                                    selectDay(cell.day)
                                }
                            }
                        }
                    }

                    // Active filter indicator
                    if appState.calendarFilterDate != nil {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                appState.clearCalendarFilter()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("Clear filter")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(AppTheme.accent)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear calendar filter")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.bgCard.opacity(0.3))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func navigateMonth(by value: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            if let newDate = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newDate
            }
        }
    }

    private func jumpToToday() {
        withAnimation(.easeOut(duration: 0.2)) {
            displayedMonth = Date()
        }
    }

    private func selectDay(_ day: Int) {
        var components = calendar.dateComponents([.year, .month], from: displayedMonth)
        components.day = day
        guard let date = calendar.date(from: components) else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            if let current = appState.calendarFilterDate,
               calendar.isDate(current, inSameDayAs: date) {
                // Tapping the same day again clears the filter
                appState.clearCalendarFilter()
            } else {
                appState.calendarFilterDate = date
            }
        }
    }
}

// MARK: - Calendar Day Button

private struct CalendarDayButton: View {
    let day: Int
    let isToday: Bool
    let isSelected: Bool
    let hasConversations: Bool
    var colorLabels: [String] = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.system(size: 10, weight: isToday ? .bold : (isSelected ? .semibold : .regular)))
                    .foregroundColor(dayTextColor)

                // Conversation indicator dots (color labels take priority)
                if !colorLabels.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(colorLabels, id: \.self) { label in
                            Circle()
                                .fill(AppState.colorForLabel(label) ?? AppTheme.accent)
                                .frame(width: 3, height: 3)
                        }
                    }
                    .frame(height: 4)
                } else {
                    Circle()
                        .fill(hasConversations ? AppTheme.accent : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(dayBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day \(day)\(isToday ? ", today" : "")\(hasConversations ? ", has conversations" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayTextColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return AppTheme.accent
        } else {
            return AppTheme.textSecondary
        }
    }

    private var dayBackground: Color {
        if isSelected {
            return AppTheme.accent
        } else if isToday {
            return AppTheme.accent.opacity(0.1)
        } else {
            return .clear
        }
    }
}

// MARK: - Day Cell Model

private struct DayCell: Identifiable {
    let id: Int
    let day: Int
    let isBlank: Bool
}
