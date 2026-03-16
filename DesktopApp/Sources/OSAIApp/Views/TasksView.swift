import SwiftUI

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTask: TaskInfo?
    @State private var logContent = ""
    @State private var showLog = false

    var activeTasks: [TaskInfo] { appState.tasks.filter { $0.enabled } }
    var disabledTasks: [TaskInfo] { appState.tasks.filter { !$0.enabled } }

    @State private var showCreateSheet = false

    var body: some View {
        HStack(spacing: 0) {
            // Task list
            VStack(spacing: 0) {
                HStack {
                    Text("Tasks")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    Text("(\(appState.tasks.count))")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textMuted)

                    Spacer()

                    Button(action: { showCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Create Task")

                    Button(action: { appState.tasks = appState.service.loadTasks() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(AppTheme.borderGlass)

                if appState.tasks.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "clock")
                            .font(.system(size: 28))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No tasks")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                        Text("Use 'osai watch' to create tasks")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            if !activeTasks.isEmpty {
                                HStack {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(AppTheme.success)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 8)

                                ForEach(activeTasks) { task in
                                    TaskListRow(
                                        task: task,
                                        isSelected: selectedTask?.id == task.id
                                    ) {
                                        selectedTask = task
                                    }
                                }
                            }

                            if !disabledTasks.isEmpty {
                                HStack {
                                    Text("DISABLED")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(AppTheme.textMuted)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 12)

                                ForEach(disabledTasks) { task in
                                    TaskListRow(
                                        task: task,
                                        isSelected: selectedTask?.id == task.id
                                    ) {
                                        selectedTask = task
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(width: 240)
            .background(AppTheme.bgSecondary.opacity(0.3))

            Divider().background(AppTheme.borderGlass)

            // Detail panel
            if let task = selectedTask {
                TaskDetailPanel(
                    task: task,
                    onViewLog: {
                        logContent = appState.service.loadTaskLog(task.id)
                        showLog = true
                    },
                    onToggle: {
                        appState.toggleTask(task)
                        // Re-select updated task
                        selectedTask = appState.tasks.first { $0.id == task.id }
                    },
                    onDelete: {
                        appState.deleteTask(task)
                        selectedTask = nil
                    }
                )
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.textMuted)
                    Text("Select a task to view details")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showLog) {
            TaskLogSheet(taskId: selectedTask?.id ?? "", content: logContent)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateTaskSheet {
                appState.tasks = appState.service.loadTasks()
            }
        }
    }
}

// MARK: - Task List Row

struct TaskListRow: View {
    let task: TaskInfo
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(task.enabled ? AppTheme.success : AppTheme.textMuted)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.id)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .lineLimit(1)
                    Text(task.schedule.displayLabel)
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textMuted)
                }

                Spacer()

                if let delivery = task.delivery {
                    Image(systemName: delivery.icon)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppTheme.accent.opacity(0.12) : (isHovered ? AppTheme.bgCard.opacity(0.4) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Task Detail Panel

struct TaskDetailPanel: View {
    let task: TaskInfo
    let onViewLog: () -> Void
    var onToggle: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.paddingLg) {
                // Header
                HStack(spacing: 14) {
                    Image(systemName: task.schedule.icon)
                        .font(.system(size: 28))
                        .foregroundColor(task.enabled ? AppTheme.accent : AppTheme.textMuted)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(task.id)
                                .font(AppTheme.fontTitle)
                                .foregroundColor(AppTheme.textPrimary)

                            Text(task.enabled ? "Active" : "Disabled")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(task.enabled ? AppTheme.success : AppTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((task.enabled ? AppTheme.success : AppTheme.textMuted).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        if !task.description.isEmpty {
                            Text(task.description)
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }

                    Spacer()
                }

                // Action buttons
                HStack(spacing: 10) {
                    ActionButton(label: task.enabled ? "Disable" : "Enable",
                                 icon: task.enabled ? "pause.circle" : "play.circle",
                                 color: task.enabled ? AppTheme.warning : AppTheme.success,
                                 action: onToggle)
                    ActionButton(label: "View Log", icon: "doc.text", color: AppTheme.accent, action: onViewLog)
                    ActionButton(label: "Open Config", icon: "folder", color: AppTheme.textSecondary) {
                        let path = NSHomeDirectory() + "/.desktop-agent/tasks/"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    Spacer()

                    Button(action: onDelete) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.error)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppTheme.error.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 14) {
                    TaskStatCard(label: "Runs", value: "\(task.runCount)", icon: "arrow.clockwise")
                    TaskStatCard(label: "Schedule", value: task.schedule.displayLabel, icon: task.schedule.icon)
                    TaskStatCard(label: "Status", value: task.statusLabel, icon: task.enabled ? "checkmark.circle" : "xmark.circle")
                }

                // Command
                if !task.command.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.accent)
                                Text("Command")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                            }

                            Text(task.command)
                                .font(AppTheme.fontMono)
                                .foregroundColor(AppTheme.textSecondary)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.bgPrimary.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Schedule details
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accent)
                            Text("Schedule")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                        }

                        InfoRow(label: "Type", value: task.schedule.type.capitalized, icon: "clock")
                        if let at = task.schedule.at {
                            InfoRow(label: "At", value: at, icon: "clock.arrow.circlepath")
                        }
                        if let cron = task.schedule.cron {
                            InfoRow(label: "Cron", value: cron, icon: "calendar.badge.clock")
                        }
                        if let interval = task.schedule.interval {
                            InfoRow(label: "Interval", value: interval, icon: "arrow.clockwise")
                        }
                    }
                }

                // Delivery
                if let delivery = task.delivery {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.accent)
                                Text("Delivery")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                            }

                            InfoRow(label: "Platform", value: delivery.platform.capitalized, icon: delivery.icon)
                            if let chatId = delivery.chatId {
                                InfoRow(label: "Chat ID", value: chatId, icon: "number")
                            }
                        }
                    }
                }

                // Last run
                if let lastRun = task.lastRun {
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                        Text("Last run: \(lastRun.formatted())")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(AppTheme.paddingXl)
        }
    }
}

struct TaskStatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.accent)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.borderGlass, lineWidth: 0.5)
        )
    }
}

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

            ScrollView {
                Text(content)
                    .font(AppTheme.fontMono)
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
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
    @State private var interval = "5m"
    @State private var cron = ""
    @State private var at = ""
    @State private var platform = ""

    var onCreated: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create Task")
                    .font(AppTheme.fontHeadline)
                    .foregroundColor(AppTheme.textPrimary)
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
                    FormField(label: "Task ID") {
                        TextField("daily-report", text: $taskId)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontBody)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    FormField(label: "Description") {
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

                    FormField(label: "Schedule Type") {
                        Picker("", selection: $scheduleType) {
                            Text("Interval").tag("interval")
                            Text("Daily").tag("daily")
                            Text("Cron").tag("cron")
                            Text("Once").tag("once")
                        }
                        .pickerStyle(.segmented)
                    }

                    if scheduleType == "interval" {
                        FormField(label: "Interval (e.g. 30s, 5m, 1h)") {
                            TextField("5m", text: $interval)
                                .textFieldStyle(.plain)
                                .font(AppTheme.fontMono)
                                .padding(10)
                                .background(AppTheme.bgPrimary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    } else if scheduleType == "daily" || scheduleType == "once" {
                        FormField(label: "At (time or datetime)") {
                            TextField("09:00", text: $at)
                                .textFieldStyle(.plain)
                                .font(AppTheme.fontMono)
                                .padding(10)
                                .background(AppTheme.bgPrimary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
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
                }
                .padding(20)
            }

            Divider().background(AppTheme.borderGlass)

            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundColor(AppTheme.textSecondary)
                    .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    saveTask()
                    onCreated()
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Task")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(taskId.isEmpty || command.isEmpty ? AppTheme.textMuted : AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(taskId.isEmpty || command.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520, height: 580)
        .background(AppTheme.bgSecondary)
    }

    private func saveTask() {
        var json: [String: Any] = [
            "id": taskId,
            "description": description,
            "command": command,
            "enabled": true,
            "runCount": 0
        ]

        var schedule: [String: Any] = ["type": scheduleType]
        switch scheduleType {
        case "interval": schedule["interval"] = interval
        case "cron": schedule["cron"] = cron
        case "daily", "once": schedule["at"] = at
        default: break
        }
        json["schedule"] = schedule

        if !platform.isEmpty {
            json["delivery"] = ["platform": platform] as [String: Any]
        }

        let tasksDir = NSHomeDirectory() + "/.desktop-agent/tasks"
        try? FileManager.default.createDirectory(atPath: tasksDir, withIntermediateDirectories: true)
        let path = "\(tasksDir)/\(taskId).json"

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
