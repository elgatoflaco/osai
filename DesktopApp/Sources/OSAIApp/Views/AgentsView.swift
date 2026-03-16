import SwiftUI
import AppKit

struct AgentsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var agentToEdit: AgentInfo?
    @State private var showImportPreview = false
    @State private var importPreviewContent = ""
    @State private var importPreviewURL: URL?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.paddingLg) {
                // Header
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.accent)
                            Text("Agents")
                                .font(AppTheme.fontTitle)
                                .foregroundColor(AppTheme.textPrimary)
                            Text("\(appState.agents.count)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text("~/.desktop-agent/agents/")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(AppTheme.textMuted)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        // Import Agent button
                        Button(action: { openImportPanel() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppTheme.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Import agent from file")

                        // Export All button
                        if !appState.agents.isEmpty {
                            Button(action: { exportAllAgents() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export All")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(AppTheme.bgPrimary.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.borderGlass, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Export all agents to folder")
                        }

                        // New Agent button
                        Button(action: { showCreateSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("New Agent")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Create new agent")
                    }
                }
                .padding(.bottom, 4)

                if appState.agents.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer(minLength: 60)
                        Image(systemName: "person.3")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No agents configured")
                            .font(AppTheme.fontHeadline)
                            .foregroundColor(AppTheme.textSecondary)
                        Text("Create an agent to get started. Each agent is a markdown file\nwith a model, triggers, and system prompt.")
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textMuted)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            Button(action: { showCreateSheet = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("Create your first agent")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.accent)
                            }
                            .buttonStyle(.plain)

                            Button(action: { openImportPanel() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Import from file")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 60)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Agent cards grid
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.agents) { agent in
                            AgentCard(agent: agent, onChat: {
                                startChatWith(agent)
                            }, onEdit: {
                                agentToEdit = agent
                            }, onDelete: {
                                appState.deleteAgent(agent)
                            }, onExport: {
                                exportSingleAgent(agent)
                            }, onCopyToClipboard: {
                                copyAgentToClipboard(agent)
                            }, onTestAgent: {
                                testAgent(agent)
                            },
                            status: appState.agentStatus(for: agent.name),
                            usageCount: appState.agentUsageCounts[agent.name] ?? 0,
                            lastUsedLabel: appState.agentLastUsedLabel(for: agent.name))
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppTheme.paddingXl)
            .padding(.top, AppTheme.paddingLg)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAgentSheet(appState: appState)
        }
        .sheet(item: $agentToEdit) { agent in
            EditAgentSheet(appState: appState, agent: agent)
        }
        .sheet(isPresented: $showImportPreview) {
            ImportAgentPreviewSheet(
                appState: appState,
                content: importPreviewContent,
                sourceURL: importPreviewURL
            )
        }
    }

    private func testAgent(_ agent: AgentInfo) {
        appState.recordAgentUsage(agentName: agent.name)
        let conv = Conversation(
            id: UUID().uuidString,
            title: "Test: \(agent.name)",
            messages: [],
            createdAt: Date(),
            agentName: agent.name
        )
        appState.activeConversation = conv
        appState.conversations.insert(conv, at: 0)
        appState.selectedTab = .chat
        appState.sendMessage("Hello! This is a quick test message to verify you are working correctly. Please respond with a brief confirmation and describe your role.")
    }

    private func startChatWith(_ agent: AgentInfo) {
        appState.recordAgentUsage(agentName: agent.name)
        let conv = Conversation(
            id: UUID().uuidString,
            title: "Chat with \(agent.name)",
            messages: [],
            createdAt: Date(),
            agentName: agent.name
        )
        appState.activeConversation = conv
        appState.conversations.insert(conv, at: 0)
        appState.selectedTab = .chat
    }

    // MARK: - Import

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Agent Definition"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            appState.showToast("Failed to read file", type: .error)
            return
        }

        let validation = appState.validateAgentFile(content: content)
        guard validation.valid else {
            appState.showToast(validation.error ?? "Invalid agent file", type: .error)
            return
        }

        importPreviewContent = content
        importPreviewURL = url
        showImportPreview = true
    }

    // MARK: - Export Single Agent

    private func exportSingleAgent(_ agent: AgentInfo) {
        let content = appState.exportAgent(name: agent.name)
        guard !content.isEmpty else {
            appState.showToast("Agent file not found", type: .error)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Agent"
        panel.nameFieldStringValue = "\(agent.name).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            appState.showToast("Agent \"\(agent.name)\" exported", type: .success)
        } catch {
            appState.showToast("Export failed: \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Copy to Clipboard

    private func copyAgentToClipboard(_ agent: AgentInfo) {
        let content = appState.exportAgent(name: agent.name)
        guard !content.isEmpty else {
            appState.showToast("Agent file not found", type: .error)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        appState.showToast("Agent \"\(agent.name)\" copied to clipboard", type: .success)
    }

    // MARK: - Export All Agents

    private func exportAllAgents() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        var exportedCount = 0
        for agent in appState.agents {
            let content = appState.exportAgent(name: agent.name)
            guard !content.isEmpty else { continue }
            let fileURL = folderURL.appendingPathComponent("\(agent.name).md")
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                exportedCount += 1
            } catch {
                // Continue exporting others
            }
        }

        if exportedCount > 0 {
            appState.showToast("Exported \(exportedCount) agent\(exportedCount == 1 ? "" : "s")", type: .success)
            NSWorkspace.shared.open(folderURL)
        } else {
            appState.showToast("No agents exported", type: .error)
        }
    }
}

// MARK: - Agent Card

struct AgentCard: View {
    let agent: AgentInfo
    let onChat: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onCopyToClipboard: () -> Void
    let onTestAgent: () -> Void
    let status: AgentStatus
    let usageCount: Int
    let lastUsedLabel: String?
    @State private var isHovered = false
    @State private var showConfirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: icon + name + status dot + actions
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    GhostIcon(size: 36, animate: false, tint: agentColor(agent.name))

                    // Status dot indicator
                    Circle()
                        .fill(status.dotColor)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.bgCard, lineWidth: 2)
                        )
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(agent.name.capitalized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)

                        // Usage count badge
                        if usageCount > 0 {
                            Text("\(usageCount)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(agentColor(agent.name))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(agentColor(agent.name).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 4) {
                        Text(agent.backendLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)

                        if let lastUsedLabel = lastUsedLabel {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                            Text(lastUsedLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(status == .recentlyUsed ? AppTheme.success : AppTheme.textMuted)
                        }
                    }
                }

                Spacer()

                // Context menu for more actions
                Menu {
                    Button(action: onEdit) {
                        Label("Edit Agent", systemImage: "pencil")
                    }
                    Button(action: {
                        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(agent.name).md"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }) {
                        Label("Open File", systemImage: "doc.text")
                    }
                    Divider()
                    Button(action: onExport) {
                        Label("Export Agent", systemImage: "square.and.arrow.up")
                    }
                    Button(action: onCopyToClipboard) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive, action: { showConfirmDelete = true }) {
                        Label("Delete Agent", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textMuted)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            // Description
            if !agent.description.isEmpty {
                Text(agent.description)
                    .font(AppTheme.fontBody)
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Model pill
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.accent)
                Text(agent.model)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Trigger keywords
            if !agent.triggers.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(agent.triggers, id: \.self) { trigger in
                        Text(trigger)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(agentColor(agent.name))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(agentColor(agent.name).opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(agentColor(agent.name).opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }
            }

            Spacer(minLength: 0)

            // Action buttons row
            HStack(spacing: 8) {
                // Test Agent button
                Button(action: onTestAgent) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("Test")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(agentColor(agent.name))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(agentColor(agent.name).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(agentColor(agent.name).opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                // Chat button
                Button(action: onChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 11))
                        Text("Chat with \(agent.name.capitalized)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(agentColor(agent.name))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(isHovered ? agentColor(agent.name).opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.3 : 0.2), radius: isHovered ? 20 : 12, x: 0, y: isHovered ? 10 : 6)
        .offset(y: isHovered ? -2 : 0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent: \(agent.name.capitalized)")
        .accessibilityValue("Model: \(agent.model), Status: \(status.label)\(agent.description.isEmpty ? "" : ", \(agent.description)")")
        .alert("Delete Agent", isPresented: $showConfirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete \"\(agent.name)\"? This will remove the agent file.")
        }
    }
}

// MARK: - Import Agent Preview Sheet

struct ImportAgentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    let content: String
    let sourceURL: URL?

    @State private var parsedName: String = ""
    @State private var parsedDescription: String = ""
    @State private var parsedModel: String = ""
    @State private var parsedTriggers: [String] = []
    @State private var parsedPrompt: String = ""
    @State private var nameConflict = false
    @State private var renameTo: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Agent")
                        .font(AppTheme.fontHeadline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Preview before importing")
                        .font(.system(size: 12, weight: .medium))
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
                VStack(alignment: .leading, spacing: 16) {
                    // Agent identity card
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Agent Details", systemImage: "person.text.rectangle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.accent)

                            InfoRow(label: "Name", value: parsedName, icon: "person.fill")
                            InfoRow(label: "Model", value: parsedModel.isEmpty ? "(not specified)" : parsedModel, icon: "cpu")

                            if !parsedDescription.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Description")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                    Text(parsedDescription)
                                        .font(AppTheme.fontBody)
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                        }
                    }

                    // Name conflict warning
                    if nameConflict {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(AppTheme.warning)
                                    Text("Name Conflict")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.warning)
                                }

                                Text("An agent named \"\(parsedName)\" already exists. You can overwrite it or choose a new name.")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textSecondary)

                                FormField(label: "Rename to") {
                                    TextField("new-agent-name", text: $renameTo)
                                        .textFieldStyle(.plain)
                                        .font(AppTheme.fontBody)
                                        .padding(10)
                                        .background(AppTheme.bgPrimary.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    // Triggers
                    if !parsedTriggers.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Triggers", systemImage: "tag")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)

                                FlowLayout(spacing: 6) {
                                    ForEach(parsedTriggers, id: \.self) { trigger in
                                        Text(trigger)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(AppTheme.accent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(AppTheme.accent.opacity(0.12))
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(AppTheme.accent.opacity(0.25), lineWidth: 0.5)
                                            )
                                    }
                                }
                            }
                        }
                    }

                    // Full prompt preview
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("System Prompt", systemImage: "text.bubble")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.accent)

                            ScrollView {
                                Text(parsedPrompt.isEmpty ? "(no system prompt)" : parsedPrompt)
                                    .font(AppTheme.fontMono)
                                    .foregroundColor(parsedPrompt.isEmpty ? AppTheme.textMuted : AppTheme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 200)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(20)
            }

            Divider().background(AppTheme.borderGlass)

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundColor(AppTheme.textSecondary)
                    .buttonStyle(.plain)

                Spacer()

                if nameConflict {
                    Button(action: importOverwrite) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Overwrite")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.warning)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(AppTheme.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppTheme.warning.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if !renameTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: importRenamed) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import as \"\(renameTo.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(action: importAgent) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Agent")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: 620)
        .background(AppTheme.bgSecondary)
        .onAppear {
            parseContent()
        }
    }

    private func parseContent() {
        let lines = content.components(separatedBy: "\n")
        var frontmatterCount = 0
        var inTriggers = false
        var inBody = false
        var promptLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                frontmatterCount += 1
                if frontmatterCount >= 2 { inBody = true }
                inTriggers = false
                continue
            }
            if inBody {
                promptLines.append(line)
                continue
            }
            if trimmed.hasPrefix("name:") {
                parsedName = trimmed.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
                inTriggers = false
            } else if trimmed.hasPrefix("description:") {
                parsedDescription = trimmed.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespaces)
                inTriggers = false
            } else if trimmed.hasPrefix("model:") {
                parsedModel = trimmed.replacingOccurrences(of: "model:", with: "").trimmingCharacters(in: .whitespaces)
                inTriggers = false
            } else if trimmed.hasPrefix("triggers:") {
                inTriggers = true
            } else if inTriggers && trimmed.hasPrefix("- ") {
                parsedTriggers.append(String(trimmed.dropFirst(2)))
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("-") {
                inTriggers = false
            }
        }

        parsedPrompt = promptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        nameConflict = appState.agents.contains(where: { $0.name == parsedName })
        renameTo = nameConflict ? "\(parsedName)-imported" : ""
    }

    private func importAgent() {
        appState.importAgentContent(content)
        dismiss()
    }

    private func importOverwrite() {
        appState.importAgentContent(content)
        dismiss()
    }

    private func importRenamed() {
        let newName = renameTo.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
        guard !newName.isEmpty else {
            appState.showToast("Please enter a valid name", type: .error)
            return
        }
        appState.importAgentContent(content, overrideName: newName)
        dismiss()
    }
}

// MARK: - Components

struct ActionButton: View {
    let label: String
    let icon: String
    var color: Color = AppTheme.accent
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(isHovered ? 0.15 : 0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var icon: String = "info.circle"

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textMuted)
                .frame(width: 16)
            Text(label)
                .font(AppTheme.fontBody)
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(AppTheme.fontMono)
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Shared Model Options

private let agentModelOptions = [
    "anthropic/claude-sonnet-4-20250514",
    "anthropic/claude-haiku-4-5-20251001",
    "google/gemini-2.5-flash",
    "openrouter/x-ai/grok-3-mini",
    "claude-code",
]

// MARK: - Create Agent Sheet

struct CreateAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState

    @State private var step = 1
    @State private var name = ""
    @State private var description = ""
    @State private var model = "anthropic/claude-sonnet-4-20250514"
    @State private var triggers = ""
    @State private var systemPrompt = ""

    private var slug: String {
        name.lowercased()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
    }

    private var triggerList: [String] {
        triggers.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canAdvance: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Agent")
                        .font(AppTheme.fontHeadline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Step \(step) of 2 — \(step == 1 ? "Basics" : "Behavior")")
                        .font(.system(size: 12, weight: .medium))
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

            // Step indicator bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.bgPrimary.opacity(0.3))
                        .frame(height: 3)
                    Rectangle()
                        .fill(AppTheme.accent)
                        .frame(width: geo.size.width * (CGFloat(step) / 2.0), height: 3)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .frame(height: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == 1 {
                        AgentFormIdentity(name: $name, description: $description, slug: slug, nameEditable: true)
                        AgentFormModel(model: $model)
                    } else {
                        AgentFormSystemPrompt(systemPrompt: $systemPrompt)
                        AgentFormTriggers(triggers: $triggers, triggerList: triggerList)
                    }
                }
                .padding(20)
            }

            Divider().background(AppTheme.borderGlass)

            // Footer
            HStack {
                if step == 1 {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                        .buttonStyle(.plain)
                } else {
                    Button(action: { withAnimation { step = 1 } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if step == 1 {
                    Button(action: { withAnimation { step = 2 } }) {
                        HStack(spacing: 6) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canAdvance ? AppTheme.accent : AppTheme.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdvance)
                } else {
                    Button(action: saveAndDismiss) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Create Agent")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canAdvance ? AppTheme.accent : AppTheme.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdvance)
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: 620)
        .background(AppTheme.bgSecondary)
    }

    // MARK: - Save

    private func saveAndDismiss() {
        let finalSlug = slug.isEmpty ? "agent" : slug
        let backend = model == "claude-code" ? "claude-code" : "api"

        var content = "---\n"
        content += "name: \(finalSlug)\n"
        content += "description: \(description)\n"
        content += "model: \(model)\n"
        if backend != "api" {
            content += "backend: \(backend)\n"
        }
        if !triggerList.isEmpty {
            content += "triggers:\n"
            for t in triggerList {
                content += "  - \(t)\n"
            }
        }
        content += "---\n"
        if !systemPrompt.isEmpty {
            content += systemPrompt + "\n"
        }

        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(finalSlug).md"
        try? FileManager.default.createDirectory(
            atPath: NSHomeDirectory() + "/.desktop-agent/agents",
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)

        appState.agents = appState.service.loadAgents()
        appState.showToast("Agent \"\(finalSlug)\" created", type: .success)
        dismiss()
    }
}

// MARK: - Edit Agent Sheet

struct EditAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: AppState
    let agent: AgentInfo

    @State private var step = 1
    @State private var description: String = ""
    @State private var model: String = ""
    @State private var triggers: String = ""
    @State private var systemPrompt: String = ""

    private var triggerList: [String] {
        triggers.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Agent")
                        .font(AppTheme.fontHeadline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Step \(step) of 2 — \(step == 1 ? "Basics" : "Behavior")")
                        .font(.system(size: 12, weight: .medium))
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

            // Step indicator bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.bgPrimary.opacity(0.3))
                        .frame(height: 3)
                    Rectangle()
                        .fill(AppTheme.accent)
                        .frame(width: geo.size.width * (CGFloat(step) / 2.0), height: 3)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .frame(height: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == 1 {
                        AgentFormIdentity(
                            name: .constant(agent.name),
                            description: $description,
                            slug: agent.name,
                            nameEditable: false
                        )
                        AgentFormModel(model: $model)
                    } else {
                        AgentFormSystemPrompt(systemPrompt: $systemPrompt)
                        AgentFormTriggers(triggers: $triggers, triggerList: triggerList)
                    }
                }
                .padding(20)
            }

            Divider().background(AppTheme.borderGlass)

            // Footer
            HStack {
                if step == 1 {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                        .buttonStyle(.plain)
                } else {
                    Button(action: { withAnimation { step = 1 } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if step == 1 {
                    Button(action: { withAnimation { step = 2 } }) {
                        HStack(spacing: 6) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: saveAndDismiss) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Changes")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: 620)
        .background(AppTheme.bgSecondary)
        .onAppear {
            description = agent.description
            model = agent.model
            systemPrompt = agent.systemPrompt
            triggers = agent.triggers.joined(separator: ", ")
        }
    }

    private func saveAndDismiss() {
        appState.saveAgent(agent, description: description, model: model, systemPrompt: systemPrompt, triggers: triggerList)
        dismiss()
    }
}

// MARK: - Reusable Agent Form Components

struct AgentFormIdentity: View {
    @Binding var name: String
    @Binding var description: String
    let slug: String
    let nameEditable: Bool

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Identity", systemImage: "person.text.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accent)

                FormField(label: "Name") {
                    if nameEditable {
                        TextField("My Agent", text: $name)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontBody)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        HStack {
                            Text(name)
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Text("read-only")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .padding(10)
                        .background(AppTheme.bgPrimary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                if !slug.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text("~/.desktop-agent/agents/\(slug).md")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(AppTheme.textMuted)
                }

                FormField(label: "Description") {
                    TextField("What does this agent do?", text: $description)
                        .textFieldStyle(.plain)
                        .font(AppTheme.fontBody)
                        .padding(10)
                        .background(AppTheme.bgPrimary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct AgentFormModel: View {
    @Binding var model: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Model", systemImage: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accent)

                Picker("", selection: $model) {
                    ForEach(agentModelOptions, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.accent)

                if model == "claude-code" {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11))
                        Text("Delegates to local Claude Code CLI for code tasks")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(AppTheme.textMuted)
                }
            }
        }
    }
}

struct AgentFormSystemPrompt: View {
    @Binding var systemPrompt: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("System Prompt", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accent)

                TextEditor(text: $systemPrompt)
                    .font(AppTheme.fontMono)
                    .foregroundColor(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 120, maxHeight: 180)
                    .background(AppTheme.bgPrimary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("Instructions that define how the agent behaves and responds.")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)
            }
        }
    }
}

struct AgentFormTriggers: View {
    @Binding var triggers: String
    let triggerList: [String]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Trigger Keywords", systemImage: "tag")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accent)

                TextField("code, debug, implement, fix", text: $triggers)
                    .textFieldStyle(.plain)
                    .font(AppTheme.fontBody)
                    .padding(10)
                    .background(AppTheme.bgPrimary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if !triggerList.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(triggerList, id: \.self) { trigger in
                            Text(trigger)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppTheme.accent.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(AppTheme.accent.opacity(0.25), lineWidth: 0.5)
                                )
                        }
                    }
                }

                Text("Messages containing these keywords will auto-route to this agent.")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)
            }
        }
    }
}

// MARK: - Form Field

struct FormField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            content
        }
    }
}
