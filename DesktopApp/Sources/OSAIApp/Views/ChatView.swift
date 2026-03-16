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
        let sorted = appState.sortedConversations
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

    /// Hide conversation list when window is narrow or focus mode is toggled
    private var effectiveFocusMode: Bool {
        focusMode || appState.sidebarHidden
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

                if filteredConversations.isEmpty && contentSearchResults.isEmpty {
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
                                        HStack(spacing: 6) {
                                            if isSelecting {
                                                Image(systemName: selectedConversationIds.contains(conv.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(selectedConversationIds.contains(conv.id) ? AppTheme.accent : AppTheme.textMuted)
                                                    .onTapGesture { toggleSelection(conv.id) }
                                            }
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
                                                onCancelRename: { renamingConversationId = nil }
                                            )
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    deleteConfirmConversation = conv
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
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
                                        HStack(spacing: 6) {
                                            if isSelecting {
                                                Image(systemName: selectedConversationIds.contains(conv.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(selectedConversationIds.contains(conv.id) ? AppTheme.accent : AppTheme.textMuted)
                                                    .onTapGesture { toggleSelection(conv.id) }
                                            }
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
                                                onCancelRename: { renamingConversationId = nil }
                                            )
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    deleteConfirmConversation = conv
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
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
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
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
                        Button(action: { appState.presentExportSheet(for: conv) }) {
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
                                            onRetry: msg.id == lastAssistantId && !msg.isStreaming ? { appState.retryLastMessage() } : nil,
                                            onReaction: msg.role == .assistant ? { reaction in appState.setReaction(messageId: msg.id, reaction: reaction) } : nil
                                        )
                                        .id(msg.id)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                    }
                                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: conv.messages.count)

                                    // Streaming status bar with elapsed timer
                                    if let lastMsg = conv.messages.last, lastMsg.isStreaming, !lastMsg.content.isEmpty || !lastMsg.activities.isEmpty {
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
                                .accessibilityLabel("Scroll to bottom")
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
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

                    ChatInputBar(text: $messageText, attachedFiles: $attachedFiles, isDisabled: appState.isProcessing, onUpArrowInEmptyInput: {
                        if let lastContent = appState.lastUserMessageContent() {
                            messageText = lastContent
                        }
                    }) {
                        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
        .onChange(of: messageText) { _, newValue in
            if !newValue.isEmpty {
                appState.suggestedReplies = []
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
        .sheet(isPresented: $appState.showExportSheet) {
            if let conv = appState.exportConversationTarget {
                ExportOptionsView(conversation: conv)
                    .environmentObject(appState)
            }
        }
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
    @State private var isHovered = false

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
                        if isRenaming {
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
                        } else {
                            Text(conv.title)
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
                                .lineLimit(1)
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
