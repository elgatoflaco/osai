import SwiftUI
import UniformTypeIdentifiers
import AppKit

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
    @State private var showClearAllAlert = false
    @State private var isSelecting = false
    @State private var selectedConversationIds: Set<String> = []
    @State private var scrollToMessageId: String? = nil
    @State private var searchIncludesMessages = false
    @State private var renamingConversationId: String? = nil
    @State private var renamingText: String = ""
    @State private var deleteConfirmConversation: Conversation? = nil
    @State private var newTagText: String = ""
    @State private var showNewTagPopover: String? = nil
    @State private var scrollProgress: CGFloat = 0
    @State private var autoScrollPaused: Bool = false
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var showBookmarksPanel: Bool = false
    @State private var shareMode: Bool = false
    @State private var selectedShareMessageIds: Set<String> = []
    @State private var showCodeBlocksSheet: Bool = false
    @State private var showCalendarBrowser: Bool = false
    @State private var calendarSelectedDate: Date? = nil
    @State private var searchFilters = AppState.SearchFilters()
    @State private var showSearchFilters: Bool = false



    private var filteredConversations: [Conversation] {
        var sorted = appState.sortedConversations
        if let tag = appState.filterTag {
            sorted = sorted.filter { $0.tags.contains(tag) }
        }

        // When filters are active, use searchMessages to find matching conversations
        if !searchFilters.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let filterResults = appState.searchMessages(query: query, filters: searchFilters)
            let matchingConvIds = Set(filterResults.map { $0.0.id })
            let filtered = sorted.filter { matchingConvIds.contains($0.id) }
            // If there's also a text query, merge with title matches
            if !query.isEmpty {
                let titleMatches = sorted.filter { conv in
                    matchingConvIds.contains(conv.id) ||
                    conv.title.localizedCaseInsensitiveContains(query) ||
                    (conv.agentName?.localizedCaseInsensitiveContains(query) ?? false)
                }
                return titleMatches
            }
            return filtered
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }

        // Title/agent matches
        let titleMatches = sorted.filter { conv in
            conv.title.localizedCaseInsensitiveContains(query) ||
            (conv.agentName?.localizedCaseInsensitiveContains(query) ?? false)
        }

        // When searching messages or no title matches found, include content matches
        if searchIncludesMessages || titleMatches.isEmpty {
            let contentResults = appState.searchAllConversations(query: query)
            let titleIds = Set(titleMatches.map { $0.id })
            let extraConvs = contentResults
                .filter { !titleIds.contains($0.conversation.id) }
                .map { $0.conversation }
            return titleMatches + extraConvs
        }

        return titleMatches
    }

    /// Content search results grouped by conversation, only when actively searching messages
    private var contentSearchResults: [AppState.ConversationSearchResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // When filters are active, build results from searchMessages
        if !searchFilters.isEmpty {
            let filterResults = appState.searchMessages(query: query, filters: searchFilters)
            let grouped = Dictionary(grouping: filterResults) { $0.0.id }
            return grouped.compactMap { (_, pairs) in
                guard let conv = pairs.first?.0 else { return nil }
                let msgs = pairs.map { $0.1 }
                return AppState.ConversationSearchResult(conversation: conv, matches: msgs)
            }
        }

        guard !query.isEmpty else { return [] }

        let titleMatches = appState.conversations.filter { conv in
            conv.title.localizedCaseInsensitiveContains(query) ||
            (conv.agentName?.localizedCaseInsensitiveContains(query) ?? false)
        }

        // Auto-enable message search when no title matches
        if searchIncludesMessages || titleMatches.isEmpty {
            return appState.searchAllConversations(query: query)
        }
        return []
    }

    private var sidebarGroups: [(String, [Conversation])] {
        appState.groupedConversations(from: filteredConversations)
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

    /// Hide conversation list when window is narrow or focus mode is toggled
    private var effectiveFocusMode: Bool {
        focusMode || appState.sidebarHidden
    }

    // MARK: - Quick Actions Bar

    @ViewBuilder
    private var quickActionsBarView: some View {
        if let conv = appState.activeConversation, !conv.messages.isEmpty {
            ChatQuickActionsBar(
                actions: appState.quickActions,
                isCollapsed: $appState.quickActionsCollapsed,
                onAction: { action in
                    appState.sendMessage(action.prompt)
                }
            )
        }
    }

    // MARK: - Conversation Starter View

    @ViewBuilder
    private var conversationStarterView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                GhostIcon(size: 72)

                VStack(spacing: 8) {
                    Text("What can I help with?")
                        .font(AppTheme.fontTitle)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Pick a template to get started, or type anything below.")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    StarterTemplateCard(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "Write code",
                        subtitle: "Help me write, debug, or refactor code"
                    ) {
                        messageText = "Help me write code: "
                        appState.shouldFocusInput = true
                    }
                    StarterTemplateCard(
                        icon: "magnifyingglass",
                        title: "Research",
                        subtitle: "Investigate topics, compare alternatives"
                    ) {
                        messageText = "Research this topic for me: "
                        appState.shouldFocusInput = true
                    }
                    StarterTemplateCard(
                        icon: "gearshape.2",
                        title: "Automate",
                        subtitle: "Create workflows, schedule tasks, automate Mac"
                    ) {
                        messageText = "Help me automate: "
                        appState.shouldFocusInput = true
                    }
                    StarterTemplateCard(
                        icon: "doc.text",
                        title: "Create content",
                        subtitle: "Write emails, documents, presentations"
                    ) {
                        messageText = "Help me write: "
                        appState.shouldFocusInput = true
                    }
                    StarterTemplateCard(
                        icon: "chart.bar",
                        title: "Analyze data",
                        subtitle: "Process files, extract insights, visualize"
                    ) {
                        messageText = "Analyze this data: "
                        appState.shouldFocusInput = true
                    }
                    StarterTemplateCard(
                        icon: "questionmark.bubble",
                        title: "Quick question",
                        subtitle: "Ask anything, get instant answers"
                    ) {
                        messageText = ""
                        appState.shouldFocusInput = true
                    }
                }
                .frame(maxWidth: 520)
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.paddingXl)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Conversation list sidebar (hidden in focus mode or narrow windows)
            if !effectiveFocusMode {
                conversationListSidebar
            }

            // Main chat area
            VStack(spacing: 0) {
                // Reading progress bar (focus mode only)
                if focusMode {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(AppTheme.accent.opacity(0.5))
                            .frame(width: max(0, scrollProgress) * geo.size.width, height: 2)
                            .animation(.easeOut(duration: 0.15), value: scrollProgress)
                    }
                    .frame(height: 2)
                    .background(AppTheme.bgSecondary.opacity(0.3))
                    .transition(.opacity)
                }

                // Header
                HStack(spacing: 12) {
                    if focusMode {
                        // Minimal zen header: ghost icon + title only
                        GhostIcon(size: 18, animate: false)
                        if let conv = appState.activeConversation {
                            Text(conv.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                        } else {
                            Text("New Conversation")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                    } else if let conv = appState.activeConversation {
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
                                conversationModelLabel(conv)
                                Text("\(conv.messages.count) messages")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textMuted)
                                if conv.totalTokens > 0 {
                                    Text("\u{00B7}")
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
                            branchedFromLabel(conv)
                        }
                    } else {
                        GhostIcon(size: 20, animate: false)
                        Text("New Conversation")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }

                    Spacer()

                    if appState.isProcessing && !focusMode {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Processing...")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }

                    if appState.contextPressurePercent > 0 && !focusMode {
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

                    if !focusMode {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showBookmarksPanel.toggle() } }) {
                            Image(systemName: appState.bookmarkedMessages.isEmpty ? "bookmark" : "bookmark.fill")
                                .font(.system(size: 14))
                                .foregroundColor(showBookmarksPanel ? AppTheme.accent : AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Bookmarks")
                    }

                    if !focusMode, let conv = appState.activeConversation, !conv.messages.isEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                shareMode.toggle()
                                if !shareMode { selectedShareMessageIds.removeAll() }
                            }
                        }) {
                            Image(systemName: shareMode ? "xmark.circle.fill" : "checkmark.message")
                                .font(.system(size: 14))
                                .foregroundColor(shareMode ? AppTheme.accent : AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(shareMode ? "Exit share mode" : "Select messages to share")

                        Button(action: { showCodeBlocksSheet = true }) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Extract code blocks")

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.showRawMarkdown.toggle()
                            }
                        }) {
                            Image(systemName: appState.showRawMarkdown ? "doc.richtext" : "doc.plaintext")
                                .font(.system(size: 14))
                                .foregroundColor(appState.showRawMarkdown ? AppTheme.accent : AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(appState.showRawMarkdown ? "Show rendered markdown (\u{2318}\u{21E7}R)" : "Show raw markdown (\u{2318}\u{21E7}R)")

                        Button(action: { appState.presentExportSheet(for: conv) }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Export conversation")
                    }

                    if !focusMode, let _ = appState.activeConversation {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.showConversationInfo.toggle()
                            }
                        }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(appState.showConversationInfo ? AppTheme.accent : AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Conversation info")
                    }

                    Button(action: { withAnimation(.easeInOut(duration: 0.25)) {
                        focusMode.toggle()
                        if !focusMode { autoScrollPaused = false }
                    } }) {
                        Image(systemName: focusMode ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundColor(focusMode ? AppTheme.accent : AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle focus mode (\u{2318}\u{21E7}F)")

                    if !focusMode {
                        Button(action: { appState.startNewChat() }) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("New Chat (Cmd+N)")
                    }
                }
                .padding(.horizontal, AppTheme.paddingLg)
                .padding(.vertical, focusMode ? 8 : 12)
                .background(AppTheme.bgSecondary.opacity(0.2))

                Divider().background(AppTheme.borderGlass)

                // Bookmarks panel
                if showBookmarksPanel {
                    bookmarksPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Conversation info panel
                if appState.showConversationInfo, let conv = appState.activeConversation {
                    conversationInfoPanel(conv)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

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

                // Quick actions bar (hidden in focus mode)
                if !focusMode {
                    quickActionsBarView
                }

                // Messages
                if let conv = appState.activeConversation, !conv.messages.isEmpty || appState.isProcessing {
                    let lastAssistantId = conv.messages.last(where: { $0.role == .assistant })?.id
                    ScrollViewReader { proxy in
                        ZStack(alignment: .bottomTrailing) {
                            ScrollView(.vertical, showsIndicators: !focusMode) {
                                LazyVStack(spacing: focusMode ? 22 : 14) {
                                    ForEach(Array(conv.messages.enumerated()), id: \.element.id) { index, msg in
                                        // In focus mode, skip tool-only messages (no text content)
                                        if !focusMode || msg.toolName == nil || !msg.content.isEmpty {
                                            let info = messageGroupInfo(for: index, in: conv.messages)

                                            // Date separator
                                            if info.showDateSeparator, let label = info.dateSeparatorLabel {
                                                dateSeparatorView(label: label)
                                            }

                                            // Time gap indicator
                                            if info.showTimeGap, let label = info.timeGapLabel {
                                                timeGapIndicatorView(label: label)
                                            }

                                            messageBubbleView(
                                                msg: msg,
                                                conv: conv,
                                                lastAssistantId: lastAssistantId,
                                                showAvatar: info.showAvatar,
                                                showTimestamp: info.showTimestamp
                                            )
                                            .padding(.top, info.reducedSpacing ? -10 : 0)
                                        }
                                    }
                                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: conv.messages.count)

                                    // Streaming status bar with elapsed timer (hidden in focus mode)
                                    if !focusMode, let lastMsg = conv.messages.last, lastMsg.isStreaming, !lastMsg.content.isEmpty || !lastMsg.activities.isEmpty {
                                        StreamingStatusBar(
                                            activities: lastMsg.activities,
                                            startTime: appState.streamingStartTime
                                        )
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                        .animation(.easeInOut(duration: 0.25), value: lastMsg.activities.count)
                                    }

                                    // Invisible anchor at the very bottom
                                    Color.clear.frame(height: 1).id("scroll_bottom_anchor")
                                }
                                .frame(maxWidth: focusMode ? 700 : .infinity)
                                .frame(maxWidth: .infinity)
                                .padding(AppTheme.paddingLg)
                                .background(
                                    GeometryReader { geo in
                                        let frame = geo.frame(in: .named("chatScroll"))
                                        Color.clear
                                            .preference(
                                                key: ScrollOffsetPreferenceKey.self,
                                                value: frame.maxY
                                            )
                                            .preference(
                                                key: ScrollContentHeightKey.self,
                                                value: frame.height
                                            )
                                            .preference(
                                                key: ScrollOriginYKey.self,
                                                value: frame.minY
                                            )
                                    }
                                )
                            }
                            .coordinateSpace(name: "chatScroll")
                            .background(
                                GeometryReader { geo in
                                    Color.clear.onAppear {
                                        scrollViewHeight = geo.size.height
                                    }
                                    .onChange(of: geo.size.height) { _, h in
                                        scrollViewHeight = h
                                    }
                                }
                            )
                            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                                isAtBottom = maxY < 1000 || appState.isProcessing
                            }
                            .onPreferenceChange(ScrollContentHeightKey.self) { h in
                                scrollContentHeight = h
                            }
                            .onPreferenceChange(ScrollOriginYKey.self) { originY in
                                // Calculate scroll progress for focus mode progress bar
                                if scrollContentHeight > scrollViewHeight && scrollContentHeight > 0 {
                                    let scrolled = -originY
                                    let maxScroll = scrollContentHeight - scrollViewHeight
                                    scrollProgress = min(1, max(0, scrolled / maxScroll))
                                } else {
                                    scrollProgress = 1
                                }
                            }
                            .onChange(of: appState.activeConversation?.messages.count) { _, _ in
                                if !autoScrollPaused {
                                    scrollToBottom(proxy)
                                    isAtBottom = true
                                }
                            }
                            .onChange(of: appState.activeConversation?.messages.last?.content) { _, _ in
                                if isAtBottom && !autoScrollPaused {
                                    scrollToBottom(proxy)
                                }
                            }
                            .onChange(of: appState.activeConversation?.messages.last?.activities.count) { _, _ in
                                if isAtBottom && !autoScrollPaused {
                                    scrollToBottom(proxy)
                                }
                            }
                            .onChange(of: isAtBottom) { _, newValue in
                                // In focus mode, detect user scrolling up to pause auto-scroll
                                if focusMode && !newValue && !autoScrollPaused && appState.isProcessing {
                                    autoScrollPaused = true
                                }
                            }
                            .onChange(of: appState.isProcessing) { _, processing in
                                // Reset auto-scroll pause when processing completes
                                if !processing {
                                    autoScrollPaused = false
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
                            .onChange(of: scrollToMessageId) { _, targetId in
                                if let targetId = targetId {
                                    // Small delay to let the conversation load
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            proxy.scrollTo(targetId, anchor: .center)
                                        }
                                        self.scrollToMessageId = nil
                                    }
                                }
                            }

                            // Scroll-to-bottom / Resume auto-scroll button
                            if !isAtBottom || autoScrollPaused {
                                Button(action: {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("scroll_bottom_anchor", anchor: .bottom)
                                    }
                                    isAtBottom = true
                                    autoScrollPaused = false
                                }) {
                                    if focusMode && autoScrollPaused {
                                        // Resume auto-scroll pill
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.down")
                                                .font(.system(size: 11, weight: .medium))
                                            Text("Resume auto-scroll")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(AppTheme.accent.opacity(0.85))
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                                    } else {
                                        Image(systemName: "chevron.down.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(AppTheme.accent.opacity(0.8))
                                            .background(Circle().fill(AppTheme.bgCard).padding(4))
                                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(autoScrollPaused ? "Resume auto-scroll" : "Scroll to bottom")
                                .padding(.trailing, focusMode ? 0 : 16)
                                .padding(.bottom, 16)
                                .frame(maxWidth: focusMode ? .infinity : nil, alignment: .center)
                                .transition(.opacity.combined(with: .scale))
                            }
                        }
                    }
                } else {
                    conversationStarterView
                }

                // Quick reply suggestions
                if !appState.isProcessing && !appState.suggestedReplies.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(appState.suggestedReplies, id: \.self) { suggestion in
                                Button(action: {
                                    messageText = suggestion
                                    appState.sendMessage(suggestion)
                                    messageText = ""
                                }) {
                                    Text(suggestion)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.clear)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppTheme.paddingLg)
                        .padding(.vertical, 8)
                    }
                    .transition(.opacity.animation(.easeIn(duration: 0.3)))
                }

                // Share mode bottom bar
                if shareMode && !selectedShareMessageIds.isEmpty {
                    shareBottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Input bar
                VStack(spacing: 0) {
                    Divider().background(AppTheme.borderGlass)

                    // Attachment pills with image thumbnails
                    if !attachedFiles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(attachedFiles, id: \.absoluteString) { url in
                                    AttachmentPill(url: url) {
                                        attachedFiles.removeAll { $0 == url }
                                    }
                                }
                            }
                            .padding(.horizontal, AppTheme.paddingMd)
                            .padding(.top, 8)
                        }
                    }

                    ChatInputBar(text: $messageText, attachedFiles: $attachedFiles, isDisabled: appState.isProcessing, isDragOver: isDragOver, onUpArrowInEmptyInput: {
                        if let text = appState.navigateInputHistory(direction: -1, currentText: messageText) {
                            messageText = text
                        }
                    }, onDownArrowHistory: {
                        if let text = appState.navigateInputHistory(direction: 1, currentText: messageText) {
                            messageText = text
                        }
                    }, onPasteImages: { urls in
                        for url in urls {
                            if !attachedFiles.contains(url) {
                                attachedFiles.append(url)
                            }
                        }
                        appState.showToast("\(urls.count) image\(urls.count == 1 ? "" : "s") pasted", type: .success)
                    }) {
                        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        appState.addToInputHistory(messageText)
                        let files = attachedFiles
                        appState.sendMessage(messageText, attachments: files)
                        messageText = ""
                        attachedFiles = []
                        // Re-focus the input after sending
                        appState.shouldFocusInput = true
                    }
                    .padding(AppTheme.paddingMd)
                }
                .background(AppTheme.bgSecondary.opacity(0.2))
            }
            .overlay(
                ZStack {
                    if isDragOver {
                        // Semi-transparent glass background
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.accent.opacity(0.06))

                        // Dashed border
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [10, 6]))
                            .padding(4)

                        // Center icon and text
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(AppTheme.accent)
                                .symbolEffect(.pulse, options: .repeating)
                            Text("Drop files to attach")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                            Text("Images, documents, code files...")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isDragOver)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                let totalProviders = providers.count
                var addedCount = 0
                let group = DispatchGroup()
                for provider in providers {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                        if let data = data as? Data,
                           let urlString = String(data: data, encoding: .utf8),
                           let url = URL(string: urlString) {
                            DispatchQueue.main.async {
                                if !attachedFiles.contains(url) {
                                    attachedFiles.append(url)
                                    addedCount += 1
                                }
                            }
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    let count = max(addedCount, totalProviders)
                    appState.showToast("\(count) file\(count == 1 ? "" : "s") attached", type: .success)
                }
                return true
            }
        }
        .onChange(of: messageText) { _, newValue in
            if !newValue.isEmpty {
                appState.suggestedReplies = []
            }
        }
        .background(
            Group {
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

                // Cmd+Shift+F: Toggle focus/zen mode
                Button("") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        focusMode.toggle()
                        if !focusMode { autoScrollPaused = false }
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .hidden()

                // Cmd+Shift+R: Toggle raw markdown globally
                Button("") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        appState.showRawMarkdown.toggle()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .hidden()

                // Cmd+Down: Next conversation in sidebar list
                Button("") { appState.selectNextConversation() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .hidden()

                // Cmd+Up: Previous conversation in sidebar list
                Button("") { appState.selectPreviousConversation() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .hidden()

                // Ctrl+1 through Ctrl+9: Jump to conversation by position
                Button("") { appState.selectConversationByIndex(0) }
                    .keyboardShortcut("1", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(1) }
                    .keyboardShortcut("2", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(2) }
                    .keyboardShortcut("3", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(3) }
                    .keyboardShortcut("4", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(4) }
                    .keyboardShortcut("5", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(5) }
                    .keyboardShortcut("6", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(6) }
                    .keyboardShortcut("7", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(7) }
                    .keyboardShortcut("8", modifiers: .control)
                    .hidden()
                Button("") { appState.selectConversationByIndex(8) }
                    .keyboardShortcut("9", modifiers: .control)
                    .hidden()

                // Cmd+Plus: Increase chat font size
                Button("") { appState.increaseFontSize() }
                    .keyboardShortcut("+", modifiers: .command)
                    .hidden()

                // Cmd+Minus: Decrease chat font size
                Button("") { appState.decreaseFontSize() }
                    .keyboardShortcut("-", modifiers: .command)
                    .hidden()

                // Cmd+0: Reset chat font size
                Button("") { appState.resetFontSize() }
                    .keyboardShortcut("0", modifiers: .command)
                    .hidden()
            }
        )
        .sheet(isPresented: $appState.showExportSheet) {
            if let conv = appState.exportConversationTarget {
                ExportOptionsView(conversation: conv)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showCodeBlocksSheet) {
            if let conv = appState.activeConversation {
                CodeBlocksSheet(blocks: appState.extractCodeBlocks(from: conv), conversationTitle: conv.title)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Conversation Row Builder

    @ViewBuilder
    private func conversationRowView(for conv: Conversation) -> some View {
        ConversationRow(
            conv: conv,
            isActive: appState.activeConversation?.id == conv.id,
            isRenaming: renamingConversationId == conv.id,
            renamingText: renamingConversationId == conv.id ? $renamingText : .constant(""),
            onSelect: { isSelecting ? toggleSelection(conv.id) : appState.openConversation(conv) },
            onDelete: { deleteConfirmConversation = conv },
            onExport: { appState.presentExportSheet(for: conv) },
            onTogglePin: { appState.togglePin(conv) },
            onRename: {
                renamingText = conv.title
                renamingConversationId = conv.id
            },
            onCommitRename: {
                appState.renameConversation(conv, to: renamingText)
                renamingConversationId = nil
            },
            onCancelRename: { renamingConversationId = nil },
            allTags: appState.allTags,
            onArchive: {
                if conv.isArchived {
                    appState.unarchiveConversation(id: conv.id)
                } else {
                    appState.archiveConversation(id: conv.id)
                }
            },
            onAddTag: { tag in appState.addTag(to: conv.id, tag: tag) },
            onRemoveTag: { tag in appState.removeTag(from: conv.id, tag: tag) },
            onNewTag: {
                newTagText = ""
                showNewTagPopover = conv.id
            },
            titleSuggestions: renamingConversationId == conv.id ? appState.titleSuggestions(for: conv) : [],
            parentTitle: appState.parentConversationTitle(for: conv)
        )
    }

    // MARK: - New Tag Sheet

    @ViewBuilder
    private var newTagSheet: some View {
        VStack(spacing: 12) {
            Text("New Tag")
                .font(.system(size: 14, weight: .semibold))
            TextField("Tag name", text: $newTagText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { commitNewTag() }
            HStack(spacing: 12) {
                Button("Cancel") { showNewTagPopover = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { commitNewTag() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private func commitNewTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let convId = showNewTagPopover, !tag.isEmpty {
            appState.addTag(to: convId, tag: tag)
        }
        showNewTagPopover = nil
    }

    // MARK: - Tag Helpers

    private static let tagColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .teal]

    private func tagColor(for tag: String) -> Color {
        let allTags = appState.allTags
        if let idx = allTags.firstIndex(of: tag) {
            return Self.tagColors[idx % Self.tagColors.count]
        }
        return .gray
    }

    @ViewBuilder
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                tagFilterPill(label: "All", tag: nil)
                ForEach(appState.allTags, id: \.self) { tag in
                    tagFilterPill(label: tag, tag: tag)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tagFilterPill(label: String, tag: String?) -> some View {
        let isActive = appState.filterTag == tag
        Button {
            appState.filterTag = tag
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? (tag.map { tagColor(for: $0) } ?? AppTheme.accent) : AppTheme.bgCard.opacity(0.6))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ id: String) {
        if selectedConversationIds.contains(id) {
            selectedConversationIds.remove(id)
        } else {
            selectedConversationIds.insert(id)
        }
    }

    private func exportAllConversations() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var count = 0
        for conv in appState.conversations {
            let markdown = appState.exportConversation(conv)
            let safeName = conv.title
                .replacingOccurrences(of: "[^a-zA-Z0-9_ -]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = String(safeName.prefix(60)) + ".md"
            let fileURL = folder.appendingPathComponent(fileName)
            do {
                try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
                count += 1
            } catch {
                // Skip failed exports
            }
        }
        appState.showToast("Exported \(count) conversation\(count == 1 ? "" : "s")", type: .success)
    }

    private func fileIcon(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let textExts: Set<String> = ["swift", "py", "js", "ts", "md", "txt", "json", "yaml", "yml", "html", "css", "sh", "rb", "go", "rs", "c", "cpp", "h", "java", "kt", "toml", "xml", "csv", "log", "sql"]
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]
        if textExts.contains(ext) { return "doc.text" }
        if imageExts.contains(ext) { return "photo" }
        return "doc"
    }

    @ViewBuilder
    private func conversationModelLabel(_ conv: Conversation) -> some View {
        if let modelId = conv.modelId,
           let modelDef = appState.modelDefinition(for: modelId) {
            Image(systemName: modelDef.icon)
                .font(.system(size: 9))
                .foregroundColor(AppTheme.accent.opacity(0.7))
            Text(modelDef.shortName)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
            Text("\u{00B7}")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textMuted)
        }
    }

    private func abbreviatedTokens(_ count: Int) -> String {
        if count < 1000 {
            return "\(count) tokens"
        } else {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk tokens", k)
        }
    }

    @ViewBuilder
    private func messageBubbleView(msg: ChatMessage, conv: Conversation, lastAssistantId: String?, showAvatar: Bool = true, showTimestamp: Bool = true) -> some View {
        let isLastAssistant = msg.id == lastAssistantId
        let canRetry = isLastAssistant && !msg.isStreaming
        let isUser = msg.role == .user
        let editClosure: ((String) -> Void)? = isUser && !appState.isProcessing ? { newContent in
            appState.editAndResendMessage(messageId: msg.id, newContent: newContent)
        } : nil
        MessageBubble(
            message: msg,
            isLastAssistantMessage: isLastAssistant,
            zenMode: focusMode,
            onCancel: msg.isStreaming ? { appState.cancelProcessing() } : nil,
            onRetry: canRetry ? { appState.retryLastMessage() } : nil,
            onReaction: msg.role == .assistant ? { reaction in appState.setReaction(messageId: msg.id, reaction: reaction) } : nil,
            onBranch: (msg.role == .user || msg.role == .assistant) && !msg.isStreaming ? {
                let idx = conv.messages.firstIndex(where: { $0.id == msg.id }) ?? 0
                appState.branchConversation(from: conv.id, atMessageIndex: idx)
            } : nil,
            onEdit: editClosure,
            onBookmark: { appState.toggleBookmark(messageId: msg.id) },
            shareMode: shareMode,
            isSelectedForShare: selectedShareMessageIds.contains(msg.id),
            onToggleShareSelection: {
                if selectedShareMessageIds.contains(msg.id) {
                    selectedShareMessageIds.remove(msg.id)
                } else {
                    selectedShareMessageIds.insert(msg.id)
                }
            },
            showAvatar: showAvatar,
            showTimestamp: showTimestamp
        )
        .id(msg.id)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Message Grouping Helpers

    /// Determines the grouping context for a message at the given index
    private struct MessageGroupInfo {
        let showDateSeparator: Bool
        let dateSeparatorLabel: String?
        let showTimeGap: Bool
        let timeGapLabel: String?
        let showAvatar: Bool
        let showTimestamp: Bool
        let reducedSpacing: Bool
    }

    private func messageGroupInfo(for index: Int, in messages: [ChatMessage]) -> MessageGroupInfo {
        let msg = messages[index]
        let cal = Calendar.current
        let prev: ChatMessage? = index > 0 ? messages[index - 1] : nil
        let next: ChatMessage? = index < messages.count - 1 ? messages[index + 1] : nil

        // Date separator: show when day changes from previous message
        var showDateSeparator = false
        var dateSeparatorLabel: String? = nil
        if let prev = prev {
            if !cal.isDate(prev.timestamp, inSameDayAs: msg.timestamp) {
                showDateSeparator = true
                dateSeparatorLabel = dateSeparatorText(for: msg.timestamp)
            }
        } else {
            // First message always gets a date separator
            showDateSeparator = true
            dateSeparatorLabel = dateSeparatorText(for: msg.timestamp)
        }

        // Time gap: show when gap > 30 min between consecutive messages (same day)
        var showTimeGap = false
        var timeGapLabel: String? = nil
        if let prev = prev, !showDateSeparator {
            let gap = msg.timestamp.timeIntervalSince(prev.timestamp)
            if gap > 30 * 60 {
                showTimeGap = true
                timeGapLabel = timeGapText(seconds: gap)
            }
        }

        // Grouping: consecutive messages from the same role within 2 minutes
        let sameRoleAsPrev = prev != nil && prev!.role == msg.role
        let closeInTimeToPrev = prev != nil && msg.timestamp.timeIntervalSince(prev!.timestamp) < 120
        let isGroupedWithPrev = sameRoleAsPrev && closeInTimeToPrev && !showDateSeparator && !showTimeGap

        let sameRoleAsNext = next != nil && next!.role == msg.role
        let closeInTimeToNext = next != nil && next!.timestamp.timeIntervalSince(msg.timestamp) < 120
        let nextHasDateSep = next != nil && !cal.isDate(msg.timestamp, inSameDayAs: next!.timestamp)
        let nextHasTimeGap = next != nil && next!.timestamp.timeIntervalSince(msg.timestamp) > 30 * 60
        let isGroupedWithNext = sameRoleAsNext && closeInTimeToNext && !nextHasDateSep && !nextHasTimeGap

        let showAvatar = !isGroupedWithPrev
        let showTimestamp = !isGroupedWithNext
        let reducedSpacing = isGroupedWithPrev

        return MessageGroupInfo(
            showDateSeparator: showDateSeparator,
            dateSeparatorLabel: dateSeparatorLabel,
            showTimeGap: showTimeGap,
            timeGapLabel: timeGapLabel,
            showAvatar: showAvatar,
            showTimestamp: showTimestamp,
            reducedSpacing: reducedSpacing
        )
    }

    private func dateSeparatorText(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            // Show weekday + full date, e.g. "Monday, March 10"
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }

    private func timeGapText(seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min gap"
        } else {
            let hours = minutes / 60
            if hours == 1 {
                return "1 hour later"
            } else {
                return "\(hours) hours later"
            }
        }
    }

    // MARK: - Date Separator View

    @ViewBuilder
    private func dateSeparatorView(label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(AppTheme.textMuted.opacity(0.2))
                .frame(height: 0.5)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(AppTheme.textMuted.opacity(0.08))
                .clipShape(Capsule())
            Rectangle()
                .fill(AppTheme.textMuted.opacity(0.2))
                .frame(height: 0.5)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Time Gap Indicator View

    @ViewBuilder
    private func timeGapIndicatorView(label: String) -> some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textMuted.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 2)
    }


    // MARK: - Share Bottom Bar

    @ViewBuilder
    private var shareBottomBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedShareMessageIds.count) message\(selectedShareMessageIds.count == 1 ? "" : "s") selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedShareMessageIds.removeAll()
                    shareMode = false
                }
            }) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.bgCard.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.borderGlass, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button(action: shareSelectedMessages) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                    Text("Share")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.paddingLg)
        .padding(.vertical, 10)
        .background(AppTheme.bgSecondary.opacity(0.6))
        .overlay(alignment: .top) {
            Divider().background(AppTheme.borderGlass)
        }
    }

    private func shareSelectedMessages() {
        guard let conv = appState.activeConversation else { return }
        // Collect messages in conversation order
        let selected = conv.messages.filter { selectedShareMessageIds.contains($0.id) }
        guard !selected.isEmpty else { return }

        let formatted = appState.formatMessagesForSharing(messages: selected)

        guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [formatted])
        let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
    }

    // MARK: - Conversation Info Panel

    @ViewBuilder
    private func conversationInfoPanel(_ conv: Conversation) -> some View {
        let summary = conv.summary ?? appState.generateSummary(for: conv)
        let userCount = conv.messages.filter { $0.role == .user }.count
        let assistantCount = conv.messages.filter { $0.role == .assistant }.count

        // Collect unique tools
        let toolNames: [String] = {
            var names: [String] = []
            for msg in conv.messages {
                for activity in msg.activities where activity.type == .toolCall {
                    if !names.contains(activity.label) { names.append(activity.label) }
                }
                if let tool = msg.toolName, !names.contains(tool) { names.append(tool) }
            }
            return names
        }()

        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.accent)
                Text("Conversation Info")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.showConversationInfo = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Summary text
            Text(summary)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(AppTheme.borderGlass)

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                infoStatCell(icon: "bubble.left.and.bubble.right", label: "Messages", value: "\(conv.messages.count)")
                infoStatCell(icon: "person", label: "User", value: "\(userCount)")
                infoStatCell(icon: "cpu", label: "Assistant", value: "\(assistantCount)")
            }

            // Details
            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "calendar", label: "Created", value: {
                    let f = DateFormatter()
                    f.dateStyle = .medium
                    f.timeStyle = .short
                    return f.string(from: conv.createdAt)
                }())

                infoRow(icon: "clock", label: "Last updated", value: {
                    let f = DateFormatter()
                    f.dateStyle = .medium
                    f.timeStyle = .short
                    return f.string(from: conv.lastUpdated)
                }())

                if conv.totalInputTokens > 0 || conv.totalOutputTokens > 0 {
                    infoRow(icon: "number", label: "Tokens", value: "\(abbreviatedTokens(conv.totalInputTokens)) in / \(abbreviatedTokens(conv.totalOutputTokens)) out")
                }

                if conv.estimatedCost >= 0.01 {
                    infoRow(icon: "dollarsign.circle", label: "Est. cost", value: String(format: "$%.2f", conv.estimatedCost))
                }

                if let agent = conv.agentName {
                    infoRow(icon: "person.crop.circle", label: "Agent", value: agent)
                }

                if let model = conv.modelId {
                    let displayName = allModelDefinitions.first(where: { $0.id == model })?.shortName ?? model
                    infoRow(icon: "cpu", label: "Model", value: displayName)
                }

                if !conv.tags.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                            .frame(width: 14)
                        Text("Tags:")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                        ForEach(conv.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(AppTheme.accent.opacity(0.7))
                                .clipShape(Capsule())
                        }
                    }
                }

                if !toolNames.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                                .frame(width: 14)
                            Text("Tools used:")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        HStack(spacing: 4) {
                            ForEach(toolNames, id: \.self) { tool in
                                Text(tool)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.bgCard.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.bgSecondary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.borderGlass, lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.paddingLg)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func infoStatCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.accent.opacity(0.8))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(AppTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(AppTheme.bgCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textMuted)
                .frame(width: 14)
            Text(label + ":")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textMuted)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Bookmarks Panel

    @ViewBuilder
    private var bookmarksPanel: some View {
        let grouped = Dictionary(grouping: appState.bookmarkedMessages, by: { $0.conversation.id })
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
                Text("Bookmarks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                if !appState.bookmarkedMessages.isEmpty {
                    Button(action: {
                        appState.clearAllBookmarks()
                    }) {
                        Text("Clear all")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.error.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showBookmarksPanel = false } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(AppTheme.borderGlass)

            if appState.bookmarkedMessages.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.textMuted.opacity(0.5))
                        Text("No bookmarked messages")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(grouped.keys.sorted()), id: \.self) { convId in
                            if let items = grouped[convId], let conv = items.first?.conversation {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(conv.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)

                                    ForEach(items, id: \.message.id) { item in
                                        Button(action: {
                                            appState.openConversation(item.conversation)
                                            scrollToMessageId = item.message.id
                                            withAnimation(.easeInOut(duration: 0.2)) { showBookmarksPanel = false }
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "bookmark.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(AppTheme.accent.opacity(0.6))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(String(item.message.content.prefix(80)))
                                                        .font(.system(size: 12))
                                                        .foregroundColor(AppTheme.textPrimary)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.leading)
                                                    Text(bookmarkTimeString(item.message.timestamp))
                                                        .font(.system(size: 10))
                                                        .foregroundColor(AppTheme.textMuted)
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Divider().background(AppTheme.borderGlass).padding(.horizontal, 10)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .background(AppTheme.bgSecondary.opacity(0.4))
    }

    private func bookmarkTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Search Filter Chips

    private var searchFilterChipsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Standard filter chips
            HStack(spacing: 4) {
                SearchFilterChip(label: "has:code", isActive: searchFilters.hasCode) {
                    searchFilters.hasCode.toggle()
                }
                SearchFilterChip(label: "has:bookmark", isActive: searchFilters.hasBookmark) {
                    searchFilters.hasBookmark.toggle()
                }
                SearchFilterChip(label: "from:user", isActive: searchFilters.role == .user) {
                    searchFilters.role = searchFilters.role == .user ? nil : .user
                }
                SearchFilterChip(label: "from:assistant", isActive: searchFilters.role == .assistant) {
                    searchFilters.role = searchFilters.role == .assistant ? nil : .assistant
                }
            }

            // Model filter as a menu chip
            Menu {
                Button("Any model") { searchFilters.modelId = nil }
                Divider()
                ForEach(appState.availableModels, id: \.id) { model in
                    Button(action: { searchFilters.modelId = model.id }) {
                        HStack {
                            Text(model.shortName)
                            if searchFilters.modelId == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .font(.system(size: 8))
                    Text(searchFilters.modelId.flatMap { id in
                        appState.availableModels.first(where: { $0.id == id })?.shortName
                    }.map { "model:\($0)" } ?? "model:any")
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
                .foregroundColor(searchFilters.modelId != nil ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    searchFilters.modelId != nil
                        ? AnyShapeStyle(AppTheme.accent)
                        : AnyShapeStyle(AppTheme.bgCard.opacity(0.6))
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            searchFilters.modelId != nil ? AppTheme.accent : AppTheme.borderGlass,
                            lineWidth: 1
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: - Conversation List Sidebar

    @ViewBuilder
    private var conversationListSidebar: some View {
        VStack(spacing: 0) {
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
                    .accessibilityLabel("New chat")

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCalendarBrowser.toggle()
                            if !showCalendarBrowser { calendarSelectedDate = nil }
                        }
                    }) {
                        Image(systemName: showCalendarBrowser ? "list.bullet" : "calendar")
                            .font(.system(size: 13))
                            .foregroundColor(showCalendarBrowser ? AppTheme.accent : AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showCalendarBrowser ? "Show list view" : "Show calendar view")

                    Menu {
                        Button(action: {
                            isSelecting.toggle()
                            if !isSelecting { selectedConversationIds.removeAll() }
                        }) {
                            Label(isSelecting ? "Cancel Selection" : "Select Chats...", systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button(action: { showClearAllAlert = true }) {
                            Label("Clear All Chats", systemImage: "trash")
                        }
                        .disabled(appState.conversations.isEmpty)
                        Button(action: {
                            let unpinned = appState.conversations.filter { !$0.isPinned }
                            guard !unpinned.isEmpty else { return }
                            appState.deleteMultipleConversations(unpinned)
                        }) {
                            Label("Delete Unpinned", systemImage: "pin.slash")
                        }
                        .disabled(appState.conversations.filter({ !$0.isPinned }).isEmpty)
                        Divider()
                        Button(action: { appState.autoArchiveOldConversations(olderThan: 7) }) {
                            Label("Archive Old (>7 days)", systemImage: "archivebox")
                        }
                        .disabled(appState.conversations.filter({ !$0.isArchived }).isEmpty)
                        Divider()
                        Button(action: { exportAllConversations() }) {
                            Label("Export All", systemImage: "square.and.arrow.up")
                        }
                        .disabled(appState.conversations.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .alert("Clear All Chats", isPresented: $showClearAllAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete All", role: .destructive) {
                        appState.clearAllConversations()
                    }
                } message: {
                    Text("This will delete \(appState.conversations.count) conversation\(appState.conversations.count == 1 ? "" : "s"). This cannot be undone.")
                }

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
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.bgCard.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Filter chips toggle button
                HStack(spacing: 4) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSearchFilters.toggle() } }) {
                        HStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 9))
                            Text("Filters")
                                .font(.system(size: 10))
                            if searchFilters.activeCount > 0 {
                                Text("\(searchFilters.activeCount)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(AppTheme.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(searchFilters.activeCount > 0 ? AppTheme.accent : AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if !searchFilters.isEmpty {
                        Button(action: { searchFilters = AppState.SearchFilters() }) {
                            Text("Clear filters")
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

                // Search filter chips
                if showSearchFilters {
                    searchFilterChipsView
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Sort order selector
                HStack(spacing: 4) {
                    Menu {
                        ForEach(ConversationSortOrder.allCases) { order in
                            Button(action: { appState.conversationSortOrder = order }) {
                                Label {
                                    Text(order.rawValue)
                                } icon: {
                                    Image(systemName: order.icon)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 9))
                            Text(appState.conversationSortOrder.rawValue)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppTheme.textMuted)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

                // "Search in messages" toggle when there's a query
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 4) {
                        Toggle(isOn: $searchIncludesMessages) {
                            Text("Search in messages")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                        if !contentSearchResults.isEmpty {
                            let totalMatches = contentSearchResults.reduce(0) { $0 + $1.matches.count }
                            Text("\(totalMatches) match\(totalMatches == 1 ? "" : "es")")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppTheme.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                // Tag filter
                if !appState.allTags.isEmpty {
                    tagFilterBar
                }

                if showCalendarBrowser {
                    CalendarBrowserView(selectedDate: $calendarSelectedDate)
                        .environmentObject(appState)
                } else if filteredConversations.isEmpty && contentSearchResults.isEmpty {
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
                            ForEach(sidebarGroups, id: \.0) { group, convs in
                                Section {
                                    ForEach(convs) { conv in
                                        HStack(spacing: 6) {
                                            if isSelecting {
                                                Image(systemName: selectedConversationIds.contains(conv.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(selectedConversationIds.contains(conv.id) ? AppTheme.accent : AppTheme.textMuted)
                                                    .onTapGesture { toggleSelection(conv.id) }
                                            }
                                            conversationRowView(for: conv)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    deleteConfirmConversation = conv
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                                Button {
                                                    appState.archiveConversation(id: conv.id)
                                                } label: {
                                                    Label("Archive", systemImage: "archivebox")
                                                }
                                                .tint(.gray)
                                            }
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button {
                                                    appState.togglePin(conv)
                                                } label: {
                                                    Label(conv.isPinned ? "Unpin" : "Pin", systemImage: conv.isPinned ? "pin.slash" : "pin")
                                                }
                                                .tint(.yellow)
                                            }
                                        }
                                    }
                                } header: {
                                    HStack(spacing: 4) {
                                        if group == "Pinned" {
                                            Image(systemName: "pin.fill")
                                                .font(.system(size: 8))
                                                .foregroundColor(AppTheme.accent)
                                        }
                                        Text(group)
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

                            // Content search results
                            if !contentSearchResults.isEmpty {
                                Section {
                                    ForEach(contentSearchResults) { result in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Text(result.conversation.title)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text("\(result.matches.count)")
                                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                                    .foregroundColor(AppTheme.accent)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(AppTheme.accent.opacity(0.15))
                                                    .clipShape(Capsule())
                                            }

                                            ForEach(result.matches.prefix(3)) { msg in
                                                Button(action: {
                                                    scrollToMessageId = msg.id
                                                    appState.openConversation(result.conversation)
                                                }) {
                                                    HStack(spacing: 6) {
                                                        Image(systemName: msg.role == .user ? "person.fill" : "sparkle")
                                                            .font(.system(size: 8))
                                                            .foregroundColor(AppTheme.textMuted)
                                                            .frame(width: 12)
                                                        HighlightedText(
                                                            text: messagePreview(msg.content, query: searchText),
                                                            highlight: searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                                        )
                                                        .lineLimit(2)
                                                    }
                                                    .padding(.vertical, 3)
                                                    .padding(.horizontal, 6)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .background(AppTheme.bgCard.opacity(0.3))
                                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            if result.matches.count > 3 {
                                                Button(action: {
                                                    if let firstMatch = result.matches.first {
                                                        scrollToMessageId = firstMatch.id
                                                    }
                                                    appState.openConversation(result.conversation)
                                                }) {
                                                    Text("+\(result.matches.count - 3) more match\(result.matches.count - 3 == 1 ? "" : "es")")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(AppTheme.accent)
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.leading, 18)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(AppTheme.bgCard.opacity(0.2))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                                        )
                                    }
                                } header: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "text.magnifyingglass")
                                            .font(.system(size: 8))
                                            .foregroundColor(AppTheme.accent)
                                        Text("Message Matches")
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
                            // Archived conversations section
                            if appState.showArchived && !appState.archivedConversations.isEmpty {
                                Section {
                                    ForEach(appState.archivedConversations) { conv in
                                        conversationRowView(for: conv)
                                            .opacity(0.6)
                                            .overlay(
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: "archivebox.fill")
                                                        .font(.system(size: 8))
                                                        .foregroundColor(AppTheme.textMuted)
                                                        .padding(4)
                                                }
                                                .padding(.trailing, 6)
                                                .padding(.top, 6),
                                                alignment: .topTrailing
                                            )
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    deleteConfirmConversation = conv
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button {
                                                    appState.unarchiveConversation(id: conv.id)
                                                } label: {
                                                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                                                }
                                                .tint(.blue)
                                            }
                                    }
                                } header: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "archivebox.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(AppTheme.textMuted)
                                        Text("Archived")
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

                    // Show Archived toggle and Archive All Read button
                    VStack(spacing: 6) {
                        Divider().background(AppTheme.borderGlass)

                        Button(action: { appState.showArchived.toggle() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox")
                                    .font(.system(size: 11))
                                Text(appState.showArchived ? "Hide Archived" : "Show Archived")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                if !appState.archivedConversations.isEmpty {
                                    Text("\(appState.archivedConversations.count)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(AppTheme.textMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.bgCard.opacity(0.6))
                                        .clipShape(Capsule())
                                }
                            }
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { appState.autoArchiveOldConversations(olderThan: 7) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.badge.checkmark")
                                    .font(.system(size: 11))
                                Text("Archive All Read (>7 days)")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                            }
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                }
                // Floating selection action bar
                if isSelecting && !selectedConversationIds.isEmpty {
                    HStack(spacing: 10) {
                        Button(action: {
                            let toDelete = appState.conversations.filter { selectedConversationIds.contains($0.id) }
                            appState.deleteMultipleConversations(toDelete)
                            selectedConversationIds.removeAll()
                            isSelecting = false
                        }) {
                            Text("Delete Selected (\(selectedConversationIds.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.error)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            selectedConversationIds.removeAll()
                            isSelecting = false
                        }) {
                            Text("Cancel")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.bgCard.opacity(0.8))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(AppTheme.borderGlass, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.bgSecondary.opacity(0.9))
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(AppTheme.borderGlass),
                        alignment: .top
                    )
                }
            }
            .frame(width: 220)
            .background(AppTheme.bgSecondary.opacity(0.3))
            .alert("Delete Conversation", isPresented: Binding(
                get: { deleteConfirmConversation != nil },
                set: { if !$0 { deleteConfirmConversation = nil } }
            )) {
                Button("Cancel", role: .cancel) { deleteConfirmConversation = nil }
                Button("Delete", role: .destructive) {
                    if let conv = deleteConfirmConversation {
                        appState.deleteConversation(conv)
                    }
                    deleteConfirmConversation = nil
                }
            } message: {
                Text("Are you sure you want to delete \"\(deleteConfirmConversation?.title ?? "")\"? This cannot be undone.")
            }

            Divider().background(AppTheme.borderGlass)
        
        Divider().background(AppTheme.borderGlass)
        }
        .sheet(isPresented: Binding(
            get: { showNewTagPopover != nil },
            set: { if !$0 { showNewTagPopover = nil } }
        )) {
            newTagSheet
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let lastId = appState.activeConversation?.messages.last?.id {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func branchedFromLabel(_ conv: Conversation) -> some View {
        if let parentId = conv.branchedFromId,
           let parentConv = appState.conversations.first(where: { $0.id == parentId }) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.accent.opacity(0.7))
                Text("Branched from:")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textMuted)
                Button(action: { appState.openConversation(parentConv) }) {
                    Text(parentConv.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Extract a short preview of the message content centered around the first match
    private func messagePreview(_ content: String, query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(content.prefix(80)) }

        let lower = content.lowercased()
        let queryLower = trimmed.lowercased()

        guard let range = lower.range(of: queryLower) else {
            return String(content.prefix(80))
        }

        let matchStart = content.distance(from: content.startIndex, to: range.lowerBound)
        let contextRadius = 40
        let start = max(0, matchStart - contextRadius)
        let startIdx = content.index(content.startIndex, offsetBy: start)
        let endOffset = min(content.count, matchStart + trimmed.count + contextRadius)
        let endIdx = content.index(content.startIndex, offsetBy: endOffset)

        var preview = String(content[startIdx..<endIdx])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if start > 0 { preview = "..." + preview }
        if endOffset < content.count { preview = preview + "..." }
        return preview
    }
}

// MARK: - Highlighted Text

/// Renders text with matching substrings highlighted in accent color and bold
struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        if highlight.isEmpty {
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textSecondary)
        } else {
            highlightedTextView()
        }
    }

    private func highlightedTextView() -> Text {
        let lower = text.lowercased()
        let queryLower = highlight.lowercased()
        var result = Text("")
        var currentIndex = lower.startIndex

        while let range = lower.range(of: queryLower, range: currentIndex..<lower.endIndex) {
            // Text before match
            if currentIndex < range.lowerBound {
                let beforeStr = String(text[currentIndex..<range.lowerBound])
                result = result + Text(beforeStr)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textSecondary)
            }

            // Matched text
            let matchStr = String(text[range])
            result = result + Text(matchStr)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.accent)

            currentIndex = range.upperBound
        }

        // Remaining text after last match
        if currentIndex < lower.endIndex {
            let remainingStr = String(text[currentIndex..<text.endIndex])
            result = result + Text(remainingStr)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textSecondary)
        }

        return result
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conv: Conversation
    let isActive: Bool
    var isRenaming: Bool = false
    var renamingText: Binding<String> = .constant("")
    let onSelect: () -> Void
    let onDelete: () -> Void
    var onExport: (() -> Void)? = nil
    var onTogglePin: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onCommitRename: (() -> Void)? = nil
    var onCancelRename: (() -> Void)? = nil
    var allTags: [String] = []
    var onArchive: (() -> Void)? = nil
    var onAddTag: ((String) -> Void)? = nil
    var onRemoveTag: ((String) -> Void)? = nil
    var onNewTag: (() -> Void)? = nil
    var titleSuggestions: [String] = []
    var parentTitle: String? = nil
    @State private var isHovered = false

    private static let tagColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .teal]

    private func tagColor(for tag: String) -> Color {
        if let idx = allTags.firstIndex(of: tag) {
            return Self.tagColors[idx % Self.tagColors.count]
        }
        return .gray
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                if conv.branchedFromId != nil {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.accent.opacity(0.5))
                        .frame(width: 12)
                        .help(parentTitle.map { "Branched from: \($0)" } ?? "Branched conversation")
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if conv.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundColor(AppTheme.accent.opacity(0.7))
                        }
                        if isRenaming {
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Title", text: renamingText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(AppTheme.bgCard.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .onSubmit { onCommitRename?() }
                                    .onExitCommand { onCancelRename?() }
                                if !titleSuggestions.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "lightbulb.min")
                                            .font(.system(size: 8))
                                            .foregroundColor(AppTheme.textMuted)
                                        ForEach(titleSuggestions, id: \.self) { suggestion in
                                            Button {
                                                renamingText.wrappedValue = suggestion
                                            } label: {
                                                Text(suggestion)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(AppTheme.accent)
                                                    .lineLimit(1)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(AppTheme.accent.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text(conv.title)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .lineLimit(1)
                                .onTapGesture(count: 2) { onRename?() }
                        }
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

                    // Summary preview line
                    if let summary = conv.summary {
                        Text(summary)
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if !conv.tags.isEmpty {
                        tagPillsView
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conv.isPinned ? "Pinned: " : "")\(conv.title)")
        .accessibilityValue("\(conv.messages.count) messages\(conv.agentName.map { ", agent: \($0)" } ?? "")")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: { onRename?() }) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: { onTogglePin?() }) {
                Label(conv.isPinned ? "Unpin" : "Pin", systemImage: conv.isPinned ? "pin.slash" : "pin")
            }
            Button(action: { onArchive?() }) {
                Label(conv.isArchived ? "Unarchive" : "Archive", systemImage: conv.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            Button(action: { onExport?() }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(conv.messages.isEmpty)
            Divider()
            tagContextMenu
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var tagPillsView: some View {
        HStack(spacing: 3) {
            ForEach(Array(conv.tags.prefix(3)), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(tagColor(for: tag).opacity(0.8))
                    .clipShape(Capsule())
            }
            if conv.tags.count > 3 {
                Text("+\(conv.tags.count - 3) more")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var tagContextMenu: some View {
        Menu("Add Tag") {
            ForEach(allTags, id: \.self) { tag in
                Button {
                    if conv.tags.contains(tag) {
                        onRemoveTag?(tag)
                    } else {
                        onAddTag?(tag)
                    }
                } label: {
                    if conv.tags.contains(tag) {
                        Label(tag, systemImage: "checkmark")
                    } else {
                        Text(tag)
                    }
                }
            }
            Divider()
            Button {
                onNewTag?()
            } label: {
                Label("New Tag...", systemImage: "plus")
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

private struct ScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollOriginYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Starter Template Card

struct StarterTemplateCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isHovered ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(width: 32, height: 32)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isHovered ? AppTheme.textPrimary : AppTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.ultraThinMaterial)
            .background(isHovered ? AppTheme.accent.opacity(0.05) : AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                    .stroke(isHovered ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.15), radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 6 : 4)
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
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
        .accessibilityLabel(text)
        .accessibilityHint("Double tap to use this suggestion")
        .onHover { isHovered = $0 }
    }
}

// MARK: - Attachment Pill

private let attachmentImageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"]

struct AttachmentPill: View {
    let url: URL
    let onRemove: () -> Void
    @State private var thumbnail: NSImage?

    private var isImage: Bool {
        attachmentImageExts.contains(url.pathExtension.lowercased())
    }

    private var fileSize: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return nil }
        return formattedSize(size)
    }

    private func formattedSize(_ bytes: UInt64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.0f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if isImage, let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: fileIconName)
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let size = fileSize {
                    Text(size)
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textMuted)
                }
            }
            .frame(maxWidth: 120, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.bgCard.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.borderGlass, lineWidth: 1))
        .onAppear { loadThumbnail() }
    }

    private var fileIconName: String {
        let ext = url.pathExtension.lowercased()
        let textExts: Set<String> = ["swift", "py", "js", "ts", "md", "txt", "json", "yaml", "yml", "html", "css", "sh", "rb", "go", "rs", "c", "cpp", "h", "java", "kt", "toml", "xml", "csv", "log", "sql"]
        if textExts.contains(ext) { return "doc.text" }
        if attachmentImageExts.contains(ext) { return "photo" }
        return "doc"
    }

    private func loadThumbnail() {
        guard isImage else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let img = NSImage(contentsOf: url) {
                // Create a scaled-down thumbnail
                let thumbSize = NSSize(width: 80, height: 80)
                let thumb = NSImage(size: thumbSize)
                thumb.lockFocus()
                img.draw(in: NSRect(origin: .zero, size: thumbSize),
                         from: NSRect(origin: .zero, size: img.size),
                         operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                DispatchQueue.main.async {
                    thumbnail = thumb
                }
            }
        }
    }
}

// MARK: - Code Blocks Sheet

struct CodeBlocksSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let blocks: [CodeBlock]
    let conversationTitle: String

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "curlybraces")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.accent)
                Text("Code Blocks")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("(\(blocks.count))")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textMuted)
                Spacer()
                if !blocks.isEmpty {
                    Button("Copy All") { copyAllBlocks() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button("Save All") { saveAllBlocks() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider().background(AppTheme.borderGlass)

            if blocks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.textMuted)
                    Text("No code blocks found")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                    Text("Code blocks in assistant messages will appear here.")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textMuted)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(blocks) { block in
                            codeBlockRow(block)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .frame(maxWidth: 700, maxHeight: 600)
        .background(AppTheme.bgPrimary)
    }

    @ViewBuilder
    private func codeBlockRow(_ block: CodeBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(block.language)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(languageColor(block.language))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("\(block.lineCount) lines")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)

                Text("msg #\(block.messageIndex + 1)")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)

                Spacer()

                Button(action: { copyBlock(block) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppTheme.bgCard.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Button(action: { saveBlock(block) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("Save")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppTheme.bgCard.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(block.preview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppTheme.bgSecondary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(AppTheme.bgCard.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.borderGlass, lineWidth: 1))
    }

    private func languageColor(_ lang: String) -> Color {
        switch lang.lowercased() {
        case "swift": return .orange
        case "python", "py": return .blue
        case "javascript", "js": return .yellow.opacity(0.8)
        case "typescript", "ts": return .blue.opacity(0.7)
        case "rust", "rs": return .orange.opacity(0.7)
        case "go", "golang": return .cyan
        case "ruby", "rb": return .red.opacity(0.7)
        case "bash", "sh", "shell", "zsh": return .green.opacity(0.7)
        case "html": return .red.opacity(0.6)
        case "css": return .purple.opacity(0.7)
        case "json": return .gray
        case "yaml", "yml": return .pink.opacity(0.7)
        default: return AppTheme.accent.opacity(0.7)
        }
    }

    private func copyBlock(_ block: CodeBlock) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.code, forType: .string)
        appState.showToast("Code copied", type: .success)
    }

    private func saveBlock(_ block: CodeBlock) {
        let panel = NSSavePanel()
        panel.title = "Save Code Block"
        panel.nameFieldStringValue = "code_block_\(block.messageIndex + 1)\(block.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try block.code.write(to: url, atomically: true, encoding: .utf8)
            appState.showToast("Code block saved", type: .success)
        } catch {
            appState.showToast("Save failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func copyAllBlocks() {
        let separator = "\n\n// ────────────────────────────────────────\n\n"
        let combined = blocks.map { block in
            "// \(block.language) (message #\(block.messageIndex + 1))\n\(block.code)"
        }.joined(separator: separator)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        appState.showToast("All code blocks copied", type: .success)
    }

    private func saveAllBlocks() {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder for Code Blocks"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        guard panel.runModal() == .OK, let baseURL = panel.url else { return }

        let safeName = conversationTitle
            .replacingOccurrences(of: "[^a-zA-Z0-9_ -]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = String(safeName.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
        let folderURL = baseURL.appendingPathComponent(folderName.isEmpty ? "code_blocks" : folderName)

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for (i, block) in blocks.enumerated() {
                let fileName = "block_\(i + 1)_\(block.language)\(block.fileExtension)"
                let fileURL = folderURL.appendingPathComponent(fileName)
                try block.code.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            appState.showToast("Saved \(blocks.count) code blocks", type: .success)
        } catch {
            appState.showToast("Save failed: \(error.localizedDescription)", type: .error)
        }
    }
}

// MARK: - Search Filter Chip

struct SearchFilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isActive ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(AppTheme.bgCard.opacity(0.6))
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isActive ? AppTheme.accent : AppTheme.borderGlass,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
