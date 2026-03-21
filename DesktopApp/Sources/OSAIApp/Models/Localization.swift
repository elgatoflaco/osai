import Foundation

// MARK: - Lightweight i18n System

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case en = "en"
    case es = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    /// Resolve "system" to the actual language
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("es") { return .es }
        return .en
    }
}

/// Localization keys — add new keys here as needed
enum L10nKey: String {
    // Toolbar
    case notifications = "notifications"
    case bookmarks = "bookmarks"
    case selectToShare = "select_to_share"
    case exitShareMode = "exit_share_mode"
    case extractCode = "extract_code"
    case showRawMarkdown = "show_raw_markdown"
    case showRendered = "show_rendered"
    case exportConversation = "export_conversation"
    case saveSnapshot = "save_snapshot"
    case conversationStats = "conversation_stats"
    case conversationInfo = "conversation_info"
    case focusMode = "focus_mode"
    case newChat = "new_chat"
    case contextUsage = "context_usage"

    // Activity Strip
    case stop = "stop"
    case working = "working"
    case tasksCompleted = "tasks_completed"
    case taskFailed = "task_failed"

    // General
    case cancel = "cancel"
    case save = "save"
    case search = "search"
    case settings = "settings"
    case send = "send"
    case retry = "retry"
    case copy = "copy"
    case expand = "expand"
    case collapse = "collapse"
    case showMore = "show_more"
    case showLess = "show_less"

    // Agents
    case agent = "agent"
    case assistant = "assistant"
    case routedTo = "routed_to"
    case chainedTo = "chained_to"

    // Snapshot
    case snapshotName = "snapshot_name"
    case saveSnapshotTitle = "save_snapshot_title"

}

/// The main localization lookup — thread-safe, no globals
struct L10n {
    static var current: AppLanguage = .system

    static func get(_ key: L10nKey) -> String {
        let lang = current.resolved
        return translations[lang]?[key] ?? translations[.en]![key] ?? key.rawValue
    }

    /// Shorthand: L10n[.notifications]
    static subscript(_ key: L10nKey) -> String {
        return Self.get(key)
    }

    // MARK: - Translation Tables

    private static let translations: [AppLanguage: [L10nKey: String]] = [
        .en: [
            // Toolbar
            .notifications: "Notifications",
            .bookmarks: "Bookmarks",
            .selectToShare: "Select messages to share",
            .exitShareMode: "Exit share mode",
            .extractCode: "Extract code blocks",
            .showRawMarkdown: "Show raw markdown",
            .showRendered: "Show rendered markdown",
            .exportConversation: "Export conversation",
            .saveSnapshot: "Save snapshot",
            .conversationStats: "Conversation statistics",
            .conversationInfo: "Conversation info",
            .focusMode: "Focus mode",
            .newChat: "New Chat",
            .contextUsage: "Context window usage",

            // Activity Strip
            .stop: "Stop",
            .working: "Working...",
            .tasksCompleted: "tasks completed",
            .taskFailed: "failed",

            // General
            .cancel: "Cancel",
            .save: "Save",
            .search: "Search",
            .settings: "Settings",
            .send: "Send",
            .retry: "Retry",
            .copy: "Copy",
            .expand: "Expand",
            .collapse: "Collapse",
            .showMore: "Show more",
            .showLess: "Show less",

            // Agents
            .agent: "Agent",
            .assistant: "Assistant",
            .routedTo: "Routed to",
            .chainedTo: "Chained to",

            // Snapshot
            .snapshotName: "Snapshot name",
            .saveSnapshotTitle: "Save Snapshot",

        ],
        .es: [
            // Toolbar
            .notifications: "Notificaciones",
            .bookmarks: "Marcadores",
            .selectToShare: "Seleccionar mensajes para compartir",
            .exitShareMode: "Salir del modo compartir",
            .extractCode: "Extraer bloques de código",
            .showRawMarkdown: "Mostrar markdown sin formato",
            .showRendered: "Mostrar markdown renderizado",
            .exportConversation: "Exportar conversación",
            .saveSnapshot: "Guardar snapshot",
            .conversationStats: "Estadísticas de conversación",
            .conversationInfo: "Info de conversación",
            .focusMode: "Modo concentración",
            .newChat: "Nuevo Chat",
            .contextUsage: "Uso de ventana de contexto",

            // Activity Strip
            .stop: "Parar",
            .working: "Trabajando...",
            .tasksCompleted: "tareas completadas",
            .taskFailed: "fallida",

            // General
            .cancel: "Cancelar",
            .save: "Guardar",
            .search: "Buscar",
            .settings: "Ajustes",
            .send: "Enviar",
            .retry: "Reintentar",
            .copy: "Copiar",
            .expand: "Expandir",
            .collapse: "Colapsar",
            .showMore: "Ver más",
            .showLess: "Ver menos",

            // Agents
            .agent: "Agente",
            .assistant: "Asistente",
            .routedTo: "Dirigido a",
            .chainedTo: "Encadenado a",

            // Snapshot
            .snapshotName: "Nombre del snapshot",
            .saveSnapshotTitle: "Guardar Snapshot",

        ],
    ]
}
