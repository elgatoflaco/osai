import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var focusMode = false

    private func contextPressureColor(_ percent: Int) -> Color {
        if percent < 50 { return AppTheme.success }
        if percent < 75 { return AppTheme.warning }
        return AppTheme.error
    }

    var body: some View {
        HStack(spacing: 0) {
            // Conversation list sidebar
            if !focusMode {
            VStack(spacing: 0) {
                HStack {
                    Text("Chats")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Button(action: { appState.startNewChat() }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(AppTheme.borderGlass)

                if appState.conversations.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No conversations yet")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(appState.conversations) { conv in
                                ConversationRow(
                                    conv: conv,
                                    isActive: appState.activeConversation?.id == conv.id,
                                    onSelect: { appState.openConversation(conv) },
                                    onDelete: { appState.deleteConversation(conv) }
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(width: 220)
            .background(AppTheme.bgSecondary.opacity(0.3))

            Divider().background(AppTheme.borderGlass)
            } // end focusMode

            // Main chat area
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    if let conv = appState.activeConversation {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conv.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let agent = conv.agentName {
                                    GhostIcon(size: 12, animate: false, tint: agentColor(agent))
                                    Text(agent)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                Text("\(conv.messages.count) messages")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textMuted)
                            }
                        }
                    } else {
                        GhostIcon(size: 20, animate: false)
                        Text("New Conversation")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }

                    Spacer()

                    if appState.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Processing...")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }

                    if appState.contextPressurePercent > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(contextPressureColor(appState.contextPressurePercent))
                                .frame(width: 6, height: 6)
                            Text("\(appState.contextPressurePercent)%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .help("Context window usage")
                    }

                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { focusMode.toggle() } }) {
                        Image(systemName: focusMode ? "sidebar.leading" : "rectangle.leadinghalf.filled")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle focus mode")

                    Button(action: { appState.startNewChat() }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("New Chat (Cmd+N)")
                }
                .padding(.horizontal, AppTheme.paddingLg)
                .padding(.vertical, 12)
                .background(AppTheme.bgSecondary.opacity(0.2))

                Divider().background(AppTheme.borderGlass)

                // Messages
                if let conv = appState.activeConversation, !conv.messages.isEmpty || appState.isProcessing {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 14) {
                                ForEach(conv.messages) { msg in
                                    MessageBubble(
                                        message: msg,
                                        onCancel: msg.isStreaming ? { appState.cancelProcessing() } : nil
                                    )
                                    .id(msg.id)
                                }
                            }
                            .padding(AppTheme.paddingLg)
                        }
                        .onChange(of: appState.activeConversation?.messages.count) { _, _ in
                            scrollToBottom(proxy)
                        }
                        .onChange(of: appState.activeConversation?.messages.last?.content) { _, _ in
                            scrollToBottom(proxy)
                        }
                        .onChange(of: appState.activeConversation?.messages.last?.activities.count) { _, _ in
                            scrollToBottom(proxy)
                        }
                    }
                } else {
                    // Empty state
                    VStack(spacing: 20) {
                        Spacer()
                        GhostIcon(size: 80)
                        Text("Start a conversation")
                            .font(AppTheme.fontHeadline)
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Ask anything — osai will route to the best agent automatically.")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)

                        // Quick suggestions
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 8) {
                            QuickSuggestion(text: "Check my emails", icon: "envelope") {
                                messageText = "Check my emails"
                            }
                            QuickSuggestion(text: "What's on my calendar?", icon: "calendar") {
                                messageText = "What's on my calendar?"
                            }
                            QuickSuggestion(text: "Noticias de hoy", icon: "newspaper") {
                                messageText = "Dame un briefing de las noticias de hoy"
                            }
                            QuickSuggestion(text: "Help me code", icon: "terminal") {
                                messageText = "Help me code"
                            }
                            QuickSuggestion(text: "Organiza mis tareas", icon: "checklist") {
                                messageText = "Organiza mis tareas pendientes"
                            }
                            QuickSuggestion(text: "Redacta un email", icon: "pencil.line") {
                                messageText = "Redacta un email profesional"
                            }
                        }
                        .frame(maxWidth: 450)
                        .padding(.top, 8)

                        Spacer()
                    }
                    .padding(AppTheme.paddingXl)
                }

                // Input bar
                VStack(spacing: 0) {
                    Divider().background(AppTheme.borderGlass)

                    ChatInputBar(text: $messageText, isDisabled: appState.isProcessing) {
                        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        appState.sendMessage(messageText)
                        messageText = ""
                    }
                    .padding(AppTheme.paddingMd)
                }
                .background(AppTheme.bgSecondary.opacity(0.2))
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastId = appState.activeConversation?.messages.last?.id {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conv: Conversation
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var showDelete = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conv.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let agent = conv.agentName {
                            Text(agent)
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.accent)
                        }
                        Text(timeLabel(conv.createdAt))
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                }

                Spacer()

                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.error.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? AppTheme.accent.opacity(0.12) : (isHovered ? AppTheme.bgCard.opacity(0.4) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? AppTheme.accent.opacity(0.2) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func timeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let f = DateFormatter()
            f.dateFormat = "dd MMM"
            return f.string(from: date)
        }
    }
}

// MARK: - Quick Suggestion

struct QuickSuggestion: View {
    let text: String
    var icon: String = "sparkles"
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isHovered ? AppTheme.accent : AppTheme.textMuted)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovered ? AppTheme.accent.opacity(0.06) : AppTheme.bgCard.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
