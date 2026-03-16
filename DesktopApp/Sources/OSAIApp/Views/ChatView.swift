import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var focusMode = false
    @State private var searchText = ""
    @State private var editingTitle: String? = nil
    @State private var attachedFiles: [URL] = []
    @State private var isDragOver = false
    @State private var isAtBottom = true
    @State private var searchInConversation = ""
    @State private var showConversationSearch = false
    @State private var currentMatchIndex = 0

    // MARK: - Date grouping

    private enum DateGroup: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case earlier = "Earlier"
    }

    private func dateGroup(for date: Date) -> DateGroup {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        if date >= weekAgo { return .thisWeek }
        return .earlier
    }

    private var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.conversations }
        return appState.conversations.filter { conv in
            conv.title.localizedCaseInsensitiveContains(query) ||
            (conv.agentName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var pinnedConversations: [Conversation] {
        filteredConversations.filter { $0.isPinned }
    }

    private var unpinnedConversations: [Conversation] {
        filteredConversations.filter { !$0.isPinned }
    }

    private var groupedConversations: [(DateGroup, [Conversation])] {
        let grouped = Dictionary(grouping: unpinnedConversations) { dateGroup(for: $0.createdAt) }
        return DateGroup.allCases.compactMap { group in
            guard let convs = grouped[group], !convs.isEmpty else { return nil }
            return (group, convs)
        }
    }

    private var conversationMatches: [String] {
        guard !searchInConversation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let conv = appState.activeConversation else { return [] }
        let query = searchInConversation.lowercased()
        return conv.messages
            .filter { $0.content.lowercased().contains(query) }
            .map { $0.id }
    }

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

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                    TextField("Search chats...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textPrimary)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.bgCard.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if filteredConversations.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.textMuted)
                        Text(searchText.isEmpty ? "No conversations yet" : "No matches")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2, pinnedViews: .sectionHeaders) {
                            if !pinnedConversations.isEmpty {
                                Section {
                                    ForEach(pinnedConversations) { conv in
                                        ConversationRow(
                                            conv: conv,
                                            isActive: appState.activeConversation?.id == conv.id,
                                            onSelect: { appState.openConversation(conv) },
                                            onDelete: { appState.deleteConversation(conv) },
                                            onExport: { appState.exportAndSave(conv) },
                                            onTogglePin: { appState.togglePin(conv) }
                                        )
                                    }
                                } header: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(AppTheme.accent)
                                        Text("Pinned")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(AppTheme.textMuted)
                                            .textCase(.uppercase)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                                    .background(AppTheme.bgSecondary.opacity(0.3))
                                }
                            }
                            ForEach(groupedConversations, id: \.0) { group, convs in
                                Section {
                                    ForEach(convs) { conv in
                                        ConversationRow(
                                            conv: conv,
                                            isActive: appState.activeConversation?.id == conv.id,
                                            onSelect: { appState.openConversation(conv) },
                                            onDelete: { appState.deleteConversation(conv) },
                                            onExport: { appState.exportAndSave(conv) },
                                            onTogglePin: { appState.togglePin(conv) }
                                        )
                                    }
                                } header: {
                                    HStack {
                                        Text(group.rawValue)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(AppTheme.textMuted)
                                            .textCase(.uppercase)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                                    .background(AppTheme.bgSecondary.opacity(0.3))
                                }
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
                            if let editing = editingTitle {
                                TextField("Conversation title", text: Binding(
                                    get: { editing },
                                    set: { editingTitle = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(AppTheme.bgCard.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .onSubmit {
                                    if let title = editingTitle {
                                        appState.renameConversation(conv, to: title)
                                    }
                                    editingTitle = nil
                                }
                                .onExitCommand {
                                    editingTitle = nil
                                }
                            } else {
                                Text(conv.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(1)
                                    .onTapGesture(count: 2) {
                                        editingTitle = conv.title
                                    }
                            }
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
                                if conv.totalTokens > 0 {
                                    Text("·")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textMuted)
                                    Text(abbreviatedTokens(conv.totalTokens))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textMuted)
                                    if conv.estimatedCost >= 0.01 {
                                        Text("~$\(String(format: "%.2f", conv.estimatedCost))")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textMuted)
                                    }
                                }
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

                    if let conv = appState.activeConversation, !conv.messages.isEmpty {
                        Button(action: { appState.exportAndSave(conv) }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Export conversation")
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

                // Conversation search bar
                if showConversationSearch {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)

                        TextField("Find in conversation...", text: $searchInConversation)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textPrimary)
                            .onSubmit {
                                if !conversationMatches.isEmpty {
                                    currentMatchIndex = (currentMatchIndex + 1) % conversationMatches.count
                                }
                            }

                        if !searchInConversation.isEmpty {
                            Text(conversationMatches.isEmpty ? "0 of 0" : "\(currentMatchIndex + 1) of \(conversationMatches.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted)

                            Button(action: {
                                if !conversationMatches.isEmpty {
                                    currentMatchIndex = (currentMatchIndex - 1 + conversationMatches.count) % conversationMatches.count
                                }
                            }) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(conversationMatches.isEmpty ? AppTheme.textMuted.opacity(0.4) : AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(conversationMatches.isEmpty)

                            Button(action: {
                                if !conversationMatches.isEmpty {
                                    currentMatchIndex = (currentMatchIndex + 1) % conversationMatches.count
                                }
                            }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(conversationMatches.isEmpty ? AppTheme.textMuted.opacity(0.4) : AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(conversationMatches.isEmpty)
                        }

                        Button(action: {
                            showConversationSearch = false
                            searchInConversation = ""
                            currentMatchIndex = 0
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.bgCard.opacity(0.6))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(AppTheme.borderGlass),
                        alignment: .bottom
                    )
                }

                // Messages
                if let conv = appState.activeConversation, !conv.messages.isEmpty || appState.isProcessing {
                    let lastAssistantId = conv.messages.last(where: { $0.role == .assistant })?.id
                    ScrollViewReader { proxy in
                        ZStack(alignment: .bottomTrailing) {
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 14) {
                                    ForEach(conv.messages) { msg in
                                        MessageBubble(
                                            message: msg,
                                            isLastAssistantMessage: msg.id == lastAssistantId,
                                            onCancel: msg.isStreaming ? { appState.cancelProcessing() } : nil,
                                            onRetry: msg.id == lastAssistantId && !msg.isStreaming ? { appState.retryLastMessage() } : nil
                                        )
                                        .id(msg.id)
                                    }

                                    // Invisible anchor at the very bottom
                                    Color.clear.frame(height: 1).id("scroll_bottom_anchor")
                                }
                                .padding(AppTheme.paddingLg)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ScrollOffsetPreferenceKey.self,
                                            value: geo.frame(in: .named("chatScroll")).maxY
                                        )
                                    }
                                )
                            }
                            .coordinateSpace(name: "chatScroll")
                            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                                isAtBottom = maxY < 1000 || appState.isProcessing
                            }
                            .onChange(of: appState.activeConversation?.messages.count) { _, _ in
                                scrollToBottom(proxy)
                                isAtBottom = true
                            }
                            .onChange(of: appState.activeConversation?.messages.last?.content) { _, _ in
                                if isAtBottom {
                                    scrollToBottom(proxy)
                                }
                            }
                            .onChange(of: appState.activeConversation?.messages.last?.activities.count) { _, _ in
                                if isAtBottom {
                                    scrollToBottom(proxy)
                                }
                            }

                            .onChange(of: searchInConversation) { _, _ in
                                currentMatchIndex = 0
                                let matches = conversationMatches
                                if let firstId = matches.first {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo(firstId, anchor: .center)
                                    }
                                }
                            }
                            .onChange(of: currentMatchIndex) { _, newIndex in
                                let matches = conversationMatches
                                if newIndex < matches.count {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo(matches[newIndex], anchor: .center)
                                    }
                                }
                            }

                            // Scroll-to-bottom floating button
                            if !isAtBottom {
                                Button(action: {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("scroll_bottom_anchor", anchor: .bottom)
                                    }
                                    isAtBottom = true
                                }) {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(AppTheme.accent.opacity(0.8))
                                        .background(Circle().fill(AppTheme.bgCard).padding(4))
                                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                                .transition(.opacity.combined(with: .scale))
                            }
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

                    // Attachment pills
                    if !attachedFiles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(attachedFiles, id: \.absoluteString) { url in
                                    HStack(spacing: 4) {
                                        Image(systemName: fileIcon(for: url))
                                            .font(.system(size: 10))
                                            .foregroundColor(AppTheme.accent)
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        Button(action: { attachedFiles.removeAll { $0 == url } }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(AppTheme.textMuted)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.bgCard.opacity(0.8))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(AppTheme.borderGlass, lineWidth: 1))
                                }
                            }
                            .padding(.horizontal, AppTheme.paddingMd)
                            .padding(.top, 8)
                        }
                    }

                    ChatInputBar(text: $messageText, attachedFiles: $attachedFiles, isDisabled: appState.isProcessing) {
                        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let files = attachedFiles
                        appState.sendMessage(messageText, attachments: files)
                        messageText = ""
                        attachedFiles = []
                    }
                    .padding(AppTheme.paddingMd)
                }
                .background(AppTheme.bgSecondary.opacity(0.2))
            }
            .overlay(
                Group {
                    if isDragOver {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .background(AppTheme.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "arrow.down.doc")
                                        .font(.system(size: 28))
                                        .foregroundColor(AppTheme.accent)
                                    Text("Drop files to attach")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppTheme.accent)
                                }
                            )
                            .padding(4)
                    }
                }
            )
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                        if let data = data as? Data,
                           let urlString = String(data: data, encoding: .utf8),
                           let url = URL(string: urlString) {
                            DispatchQueue.main.async {
                                if !attachedFiles.contains(url) {
                                    attachedFiles.append(url)
                                }
                            }
                        }
                    }
                }
                return true
            }
        }
        .background(
            Button("") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showConversationSearch.toggle()
                }
                if !showConversationSearch {
                    searchInConversation = ""
                    currentMatchIndex = 0
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        )
    }

    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let textExts: Set<String> = ["swift", "py", "js", "ts", "md", "txt", "json", "yaml", "yml", "html", "css", "sh", "rb", "go", "rs", "c", "cpp", "h", "java", "kt", "toml", "xml", "csv", "log", "sql"]
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]
        if textExts.contains(ext) { return "doc.text" }
        if imageExts.contains(ext) { return "photo" }
        return "doc"
    }

    private func abbreviatedTokens(_ count: Int) -> String {
        if count < 1000 {
            return "\(count) tokens"
        } else {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk tokens", k)
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
    var onExport: (() -> Void)? = nil
    var onTogglePin: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var showDelete = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if conv.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundColor(AppTheme.accent.opacity(0.7))
                        }
                        Text(conv.title)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
                            .lineLimit(1)
                    }

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
                } else if conv.messages.count > 0 {
                    Text("\(conv.messages.count)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.bgCard.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? AppTheme.accent.opacity(0.12) :
                          conv.isPinned ? AppTheme.accent.opacity(0.05) :
                          (isHovered ? AppTheme.bgCard.opacity(0.4) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? AppTheme.accent.opacity(0.2) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: { onTogglePin?() }) {
                Label(conv.isPinned ? "Unpin" : "Pin", systemImage: conv.isPinned ? "pin.slash" : "pin")
            }
            Button(action: { onExport?() }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(conv.messages.isEmpty)
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
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

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
