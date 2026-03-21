import SwiftUI

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var taskToDelete: TaskInfo?
    @State private var showDeleteConfirm = false

    // Date grouping helpers
    private enum DateGroup: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case older = "Older"
    }

    private func dateGroup(for task: TaskInfo) -> DateGroup {
        guard let lastRun = task.lastRun else { return .older }
        let calendar = Calendar.current
        if calendar.isDateInToday(lastRun) { return .today }
        if calendar.isDateInYesterday(lastRun) { return .yesterday }
        return .older
    }

    private func groupedTasks() -> [(DateGroup, [TaskInfo])] {
        let tasks = appState.filteredTasks
        var groups: [DateGroup: [TaskInfo]] = [:]
        for task in tasks {
            let group = dateGroup(for: task)
            groups[group, default: []].append(task)
        }
        return DateGroup.allCases.compactMap { group in
            guard let items = groups[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks")
                        .font(AppTheme.fontHeadline)
                        .foregroundColor(AppTheme.textPrimary)

                    let active = appState.tasks.count { $0.enabled }
                    let total = appState.tasks.count
                    Text("\(active) active of \(total) total")
                        .font(AppTheme.fontCaption)
                        .foregroundColor(AppTheme.textMuted)
                }

                Spacer()

                Button(action: { appState.tasks = appState.service.loadTasks() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh tasks")

                Button(action: { showCreateSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Task")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.paddingLg)
            .padding(.vertical, AppTheme.paddingMd)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textMuted)

                TextField("Search tasks...", text: $appState.taskSearchQuery)
                    .textFieldStyle(.plain)
                    .font(AppTheme.fontBody)

                if !appState.taskSearchQuery.isEmpty {
                    Button(action: { appState.taskSearchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.bgPrimary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, AppTheme.paddingLg)
            .padding(.bottom, AppTheme.paddingSm)

            // Filter tabs
            HStack(spacing: 4) {
                ForEach(TaskFilter.allCases) { filter in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { appState.taskFilter = filter } }) {
                        HStack(spacing: 5) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 10))
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(appState.taskFilter == filter ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(appState.taskFilter == filter ? AppTheme.accent : AppTheme.bgPrimary.opacity(0.4))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.paddingLg)
            .padding(.bottom, AppTheme.paddingSm)

            Divider().background(AppTheme.borderGlass)

            if appState.tasks.isEmpty {
                TasksEmptyState(onCreateTapped: { showCreateSheet = true })
            } else if appState.filteredTasks.isEmpty {
                // Empty state for filters/search with no matches
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textMuted)

                    VStack(spacing: 6) {
                        Text("No Matching Tasks")
                            .font(AppTheme.fontHeadline)
                            .foregroundColor(AppTheme.textPrimary)

                        if !appState.taskSearchQuery.isEmpty {
                            Text("No tasks match \"\(appState.taskSearchQuery)\"")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                        } else {
                            Text("No tasks with status \"\(appState.taskFilter.rawValue)\"")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                        }

                        Text("Try adjusting your filter or search query.")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .multilineTextAlignment(.center)

                    Button(action: {
                        appState.taskFilter = .all
                        appState.taskSearchQuery = ""
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Clear Filters")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppTheme.paddingXl)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        let grouped = groupedTasks()
                        ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                            // Section header
                            HStack {
                                Text(group.0.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.textMuted)
                                    .textCase(.uppercase)

                                Spacer()

                                Text("\(group.1.count)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(AppTheme.textMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.bgPrimary.opacity(0.5))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                            ForEach(group.1) { task in
                                TaskCardImproved(
                                    task: task,
                                    onToggle: { appState.toggleTask(task) },
                                    onDelete: {
                                        taskToDelete = task
                                        showDeleteConfirm = true
                                    },
                                    onRetry: {
                                        // Re-enable and refresh the task
                                        if !task.enabled {
                                            appState.toggleTask(task)
                                        }
                                        appState.showToast("Task \"\(task.id)\" queued for retry", type: .info)
                                    }
                                )
                                .contextMenu {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(task.id, forType: .string)
                                        appState.showToast("Task ID copied", type: .success)
                                    } label: {
                                        Label("Copy Task ID", systemImage: "doc.on.doc")
                                    }

                                    Button {
                                        if !task.enabled {
                                            appState.toggleTask(task)
                                        }
                                        appState.showToast("Task \"\(task.id)\" queued for retry", type: .info)
                                    } label: {
                                        Label("Retry Task", systemImage: "arrow.clockwise")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        taskToDelete = task
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete Task", systemImage: "trash")
                                    }
                                }
                                .padding(.bottom, 12)
                            }
                        }
                    }
                    .padding(AppTheme.paddingLg)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateTaskSheet {
                appState.tasks = appState.service.loadTasks()
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirm, presenting: taskToDelete) { task in
            Button("Cancel", role: .cancel) { taskToDelete = nil }
            Button("Delete", role: .destructive) {
                appState.deleteTask(task)
                taskToDelete = nil
            }
        } message: { task in
            Text("Are you sure you want to delete \"\(task.id)\"? This cannot be undone.")
        }
    }
}

// MARK: - Empty State

struct TasksEmptyState: View {
    let onCreateTapped: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.textMuted)

            VStack(spacing: 8) {
                Text("No Tasks Yet")
                    .font(AppTheme.fontHeadline)
                    .foregroundColor(AppTheme.textPrimary)

                Text("Tasks let you schedule automated prompts that run on a timer.\nFor example, get a daily news briefing, monitor a website every hour,\nor generate a weekly report.")
                    .font(AppTheme.fontBody)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(spacing: 10) {
                Button(action: onCreateTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Your First Task")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Text("or use  osai watch  from the command line")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.paddingXl)
    }
}

// MARK: - Improved Task Card

struct TaskCardImproved: View {
    let task: TaskInfo
    let onToggle: () -> Void
    let onDelete: () -> Void
    var onRetry: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var showLog = false
    @State private var logContent = ""
    @State private var elapsedTime: String = ""
    @State private var pulseAnimation = false
    @State private var completionScale: CGFloat = 0.0
    @EnvironmentObject var appState: AppState

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isRunning: Bool { task.enabled }
    private var isCompleted: Bool { !task.enabled && task.runCount > 0 }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                // Main content
                HStack(alignment: .top, spacing: 14) {
                    // Schedule icon
                    ZStack {
                        Circle()
                            .fill(task.enabled ? AppTheme.accent.opacity(0.15) : AppTheme.textMuted.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: task.schedule.icon)
                            .font(.system(size: 18))
                            .foregroundColor(task.enabled ? AppTheme.accent : AppTheme.textMuted)
                    }

                    // Info
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(task.id)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(task.enabled ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .lineLimit(1)

                            if let delivery = task.delivery {
                                HStack(spacing: 3) {
                                    Image(systemName: delivery.icon)
                                        .font(.system(size: 9))
                                    Text(delivery.platform.capitalized)
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(AppTheme.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.bgPrimary.opacity(0.5))
                                .clipShape(Capsule())
                            }

                            // Status badge
                            if isRunning {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(AppTheme.warning)
                                        .frame(width: 6, height: 6)
                                    Text("Running")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(AppTheme.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.warning.opacity(0.1))
                                .clipShape(Capsule())
                                .opacity(pulseAnimation ? 0.6 : 1.0)
                                .animation(
                                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                    value: pulseAnimation
                                )
                                .onAppear { pulseAnimation = true }
                            } else if task.isOverdue {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                    Text("Overdue")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(AppTheme.error)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.error.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }

                        if !task.description.isEmpty {
                            Text(task.description)
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(2)
                        } else if !task.command.isEmpty {
                            Text(task.command)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted)
                                .lineLimit(1)
                        }

                        // Progress bar for active/running tasks
                        if isRunning {
                            IndeterminateProgressBar()
                                .frame(maxWidth: 180, maxHeight: 4)
                        }

                        // Completion checkmark for completed tasks
                        if isCompleted {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.success)
                                    .scaleEffect(completionScale)
                                Text("Completed")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppTheme.success)
                            }
                            .onAppear {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    completionScale = 1.0
                                }
                            }
                        }

                        // Schedule + stats row
                        HStack(spacing: 16) {
                            // Schedule
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 10))
                                Text(task.schedule.displayLabel)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(AppTheme.accent.opacity(0.8))

                            // Run count
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text("\(task.runCount) run\(task.runCount == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(AppTheme.textMuted)

                            // Last run
                            if let lastRun = task.lastRun {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10))
                                    Text(relativeTime(lastRun))
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(AppTheme.textMuted)
                            }

                            // Duration since last run (elapsed timer)
                            if task.enabled, !elapsedTime.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 10))
                                    Text(elapsedTime)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .foregroundColor(AppTheme.accent.opacity(0.7))
                            }
                        }
                    }

                    Spacer()

                    // Toggle + actions
                    VStack(alignment: .trailing, spacing: 10) {
                        Toggle("Enable task", isOn: Binding(
                            get: { task.enabled },
                            set: { _ in onToggle() }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(AppTheme.accent)
                        .labelsHidden()
                        .accessibilityLabel("Enable task \(task.id)")
                        .accessibilityValue(task.enabled ? "On" : "Off")

                        HStack(spacing: 6) {
                            Button(action: {
                                logContent = appState.service.loadTaskLog(task.id)
                                showLog = true
                            }) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textMuted)
                                    .frame(width: 26, height: 26)
                                    .background(AppTheme.bgPrimary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View log for \(task.id)")
                            .help("View Log")

                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.error.opacity(0.8))
                                    .frame(width: 26, height: 26)
                                    .background(AppTheme.error.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete task \(task.id)")
                            .help("Delete Task")
                        }
                    }
                }
                .padding(AppTheme.paddingMd)
            }
        }
        .opacity(task.enabled ? 1.0 : 0.7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task: \(task.id)")
        .accessibilityValue("\(task.enabled ? "Enabled" : "Disabled"), \(task.schedule.displayLabel), \(task.runCount) runs")
        .sheet(isPresented: $showLog) {
            TaskLogSheet(taskId: task.id, content: logContent)
        }
        .onAppear { updateElapsedTime() }
        .onReceive(timer) { _ in updateElapsedTime() }
    }

    private func updateElapsedTime() {
        guard task.enabled, let lastRun = task.lastRun else {
            elapsedTime = ""
            return
        }
        let interval = Date().timeIntervalSince(lastRun)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            elapsedTime = String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            elapsedTime = String(format: "%dm %02ds", minutes, seconds)
        } else {
            elapsedTime = String(format: "%ds", seconds)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Task Log Sheet

struct TaskLogSheet: View {
    let taskId: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(AppTheme.accent)
                Text("Log: \(taskId)")
                    .font(AppTheme.fontHeadline)
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().background(AppTheme.borderGlass)

            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.textMuted)
                    Text("No log output yet")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textSecondary)
                    Text("This task has not produced any log output.")
                        .font(AppTheme.fontCaption)
                        .foregroundColor(AppTheme.textMuted)
                    Spacer()
                }
            } else {
                ScrollView {
                    Text(content)
                        .font(AppTheme.fontMono)
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(width: 700, height: 500)
        .background(AppTheme.bgSecondary)
    }
}

// MARK: - Create Task Sheet

struct CreateTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var taskId = ""
    @State private var description = ""
    @State private var command = ""
    @State private var scheduleType = "interval"
    @State private var interval = "30m"
    @State private var cron = ""
    @State private var dailyTime = "09:00"
    @State private var onceDate = ""
    @State private var onceTime = "14:00"
    @State private var platform = ""
    @State private var validationError: String?

    var onCreated: () -> Void = {}

    private var isValid: Bool {
        !taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var schedulePreview: String {
        switch scheduleType {
        case "interval": return "Every \(interval.isEmpty ? "?" : interval)"
        case "daily": return "Daily at \(dailyTime.isEmpty ? "?" : dailyTime)"
        case "once":
            let dateStr = onceDate.isEmpty ? "?" : onceDate
            let timeStr = onceTime.isEmpty ? "?" : onceTime
            return "Once at \(dateStr) \(timeStr)"
        case "cron": return cron.isEmpty ? "Cron: ?" : "Cron: \(cron)"
        default: return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Task")
                        .font(AppTheme.fontHeadline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Schedule an automated prompt to run on a timer")
                        .font(AppTheme.fontCaption)
                        .foregroundColor(AppTheme.textMuted)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider().background(AppTheme.borderGlass)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Task identity
                    FormField(label: "Task ID") {
                        TextField("daily-report", text: $taskId)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontMono)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    FormField(label: "Description (optional)") {
                        TextField("What does this task do?", text: $description)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontBody)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    FormField(label: "Command / Prompt") {
                        TextField("osai 'check my emails and summarize'", text: $command)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontMono)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Schedule section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Schedule")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)

                        Picker("", selection: $scheduleType) {
                            Text("Interval").tag("interval")
                            Text("Daily").tag("daily")
                            Text("Once").tag("once")
                            Text("Cron").tag("cron")
                        }
                        .pickerStyle(.segmented)

                        if scheduleType == "interval" {
                            FormField(label: "Run every (e.g. 30s, 5m, 1h, 2h)") {
                                TextField("30m", text: $interval)
                                    .textFieldStyle(.plain)
                                    .font(AppTheme.fontMono)
                                    .padding(10)
                                    .background(AppTheme.bgPrimary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        } else if scheduleType == "daily" {
                            FormField(label: "Time (HH:MM)") {
                                TextField("09:00", text: $dailyTime)
                                    .textFieldStyle(.plain)
                                    .font(AppTheme.fontMono)
                                    .padding(10)
                                    .background(AppTheme.bgPrimary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        } else if scheduleType == "once" {
                            HStack(spacing: 12) {
                                FormField(label: "Date (YYYY-MM-DD)") {
                                    TextField("2026-03-16", text: $onceDate)
                                        .textFieldStyle(.plain)
                                        .font(AppTheme.fontMono)
                                        .padding(10)
                                        .background(AppTheme.bgPrimary.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                FormField(label: "Time (HH:MM)") {
                                    TextField("14:00", text: $onceTime)
                                        .textFieldStyle(.plain)
                                        .font(AppTheme.fontMono)
                                        .padding(10)
                                        .background(AppTheme.bgPrimary.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        } else if scheduleType == "cron" {
                            FormField(label: "Cron Expression") {
                                TextField("0 9 * * *", text: $cron)
                                    .textFieldStyle(.plain)
                                    .font(AppTheme.fontMono)
                                    .padding(10)
                                    .background(AppTheme.bgPrimary.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        // Schedule preview
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 10))
                            Text(schedulePreview)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(AppTheme.accent.opacity(0.8))
                        .padding(.top, 2)
                    }

                    FormField(label: "Deliver to (optional)") {
                        Picker("", selection: $platform) {
                            Text("None").tag("")
                            Text("Discord").tag("discord")
                            Text("WhatsApp").tag("whatsapp")
                            Text("Watch").tag("watch")
                        }
                        .pickerStyle(.menu)
                        .tint(AppTheme.accent)
                    }

                    if let error = validationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.error)
                    }
                }
                .padding(20)
            }

            Divider().background(AppTheme.borderGlass)

            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundColor(AppTheme.textSecondary)
                    .buttonStyle(.plain)

                Spacer()

                Button(action: createTask) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Task")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(isValid ? AppTheme.accent : AppTheme.textMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 540, height: 620)
        .background(AppTheme.bgSecondary)
    }

    private func createTask() {
        let cleanId = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "-")

        guard !cleanId.isEmpty, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationError = "Task ID and command are required."
            return
        }

        var json: [String: Any] = [
            "id": cleanId,
            "description": description,
            "command": command,
            "enabled": true,
            "runCount": 0
        ]

        var schedule: [String: Any] = ["type": scheduleType]
        switch scheduleType {
        case "interval": schedule["interval"] = interval
        case "cron": schedule["cron"] = cron
        case "daily": schedule["at"] = dailyTime
        case "once":
            let datetime = "\(onceDate) \(onceTime)"
            schedule["at"] = datetime.trimmingCharacters(in: .whitespaces)
        default: break
        }
        json["schedule"] = schedule

        if !platform.isEmpty {
            json["delivery"] = ["platform": platform] as [String: Any]
        }

        let tasksDir = NSHomeDirectory() + "/.desktop-agent/tasks"
        try? FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
        let path = "\(tasksDir)/\(cleanId).json"

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }

        onCreated()
        dismiss()
    }
}

// MARK: - Indeterminate Progress Bar

struct IndeterminateProgressBar: View {
    @State private var offset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * 0.35
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.accent.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.0), AppTheme.accent, AppTheme.accent.opacity(0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: barWidth)
                        .offset(x: offset * (geo.size.width / 2 + barWidth / 2))
                    , alignment: .leading
                )
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.4)
                .repeatForever(autoreverses: true)
            ) {
                offset = 1.0
            }
        }
    }
}
