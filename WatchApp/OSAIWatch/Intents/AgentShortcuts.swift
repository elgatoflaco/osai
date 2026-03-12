import AppIntents

struct AgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAgentIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Hey \(.applicationName)",
                "Talk to \(.applicationName)",
                "\(.applicationName) help me with something"
            ],
            shortTitle: "Ask OSAI",
            systemImageName: "bubble.left.fill"
        )

        AppShortcut(
            intent: CheckStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "Check \(.applicationName) status",
                "How is \(.applicationName) doing",
                "What is \(.applicationName) doing",
                "Is \(.applicationName) busy"
            ],
            shortTitle: "OSAI Status",
            systemImageName: "chart.bar.fill"
        )

        AppShortcut(
            intent: RunCommandIntent(),
            phrases: [
                "Run \(.applicationName) command",
                "\(.applicationName) run command",
                "Execute \(.applicationName) command",
                "\(.applicationName) do something"
            ],
            shortTitle: "Run Command",
            systemImageName: "terminal.fill"
        )

        AppShortcut(
            intent: HealthSummaryIntent(),
            phrases: [
                "\(.applicationName) health summary",
                "Send health to \(.applicationName)",
                "Health report for \(.applicationName)",
                "\(.applicationName) analyze my health",
                "How's my health \(.applicationName)"
            ],
            shortTitle: "Health Summary",
            systemImageName: "heart.text.square.fill"
        )

        AppShortcut(
            intent: QuickNoteIntent(),
            phrases: [
                "\(.applicationName) note",
                "Send note to \(.applicationName)",
                "Quick note \(.applicationName)",
                "\(.applicationName) remember this"
            ],
            shortTitle: "Quick Note",
            systemImageName: "note.text"
        )

        AppShortcut(
            intent: HealthQueryIntent(),
            phrases: [
                "\(.applicationName) health check",
                "Ask \(.applicationName) about my health",
                "\(.applicationName) how am I doing",
                "\(.applicationName) check my heart rate",
                "\(.applicationName) how did I sleep"
            ],
            shortTitle: "Health Query",
            systemImageName: "heart.fill"
        )

        AppShortcut(
            intent: LocationQueryIntent(),
            phrases: [
                "\(.applicationName) where am I",
                "\(.applicationName) what's nearby",
                "Ask \(.applicationName) about this area",
                "\(.applicationName) location info",
                "\(.applicationName) what's around me"
            ],
            shortTitle: "Location Query",
            systemImageName: "location.fill"
        )

        AppShortcut(
            intent: QuickTaskIntent(),
            phrases: [
                "\(.applicationName) new task",
                "Create task with \(.applicationName)",
                "\(.applicationName) add task",
                "\(.applicationName) do this for me"
            ],
            shortTitle: "Create Task",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: DailyBriefingIntent(),
            phrases: [
                "\(.applicationName) daily briefing",
                "\(.applicationName) morning briefing",
                "Good morning \(.applicationName)",
                "\(.applicationName) catch me up",
                "\(.applicationName) what's happening today"
            ],
            shortTitle: "Daily Briefing",
            systemImageName: "sun.max.fill"
        )

        AppShortcut(
            intent: SmartReminderIntent(),
            phrases: [
                "\(.applicationName) remind me",
                "Set reminder with \(.applicationName)",
                "\(.applicationName) don't let me forget",
                "\(.applicationName) reminder"
            ],
            shortTitle: "Smart Reminder",
            systemImageName: "bell.badge.fill"
        )
    }
}
