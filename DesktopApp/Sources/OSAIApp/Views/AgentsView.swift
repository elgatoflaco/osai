import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateSheet = false

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
                        Button(action: { showCreateSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Create your first agent")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 60)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Agent cards grid
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.agents) { agent in
                            AgentCard(agent: agent, onChat: {
                                startChatWith(agent)
                            }, onDelete: {
                                appState.deleteAgent(agent)
                            })
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppTheme.paddingXl)
            .padding(.top, AppTheme.paddingLg)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAgentSheet {
                appState.agents = appState.service.loadAgents()
            }
        }
    }

    private func startChatWith(_ agent: AgentInfo) {
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
}

// MARK: - Agent Card

struct AgentCard: View {
    let agent: AgentInfo
    let onChat: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var showConfirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: icon + name + actions
            HStack(spacing: 12) {
                GhostIcon(size: 36, animate: false, tint: agentColor(agent.name))

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name.capitalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(agent.backendLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                }

                Spacer()

                // Context menu for more actions
                Menu {
                    Button(action: {
                        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(agent.name).md"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }) {
                        Label("Open File", systemImage: "doc.text")
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
        .alert("Delete Agent", isPresented: $showConfirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete \"\(agent.name)\"? This will remove the agent file.")
        }
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

// MARK: - Create Agent Sheet

struct CreateAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var model = "anthropic/claude-sonnet-4-20250514"
    @State private var backend = "api"
    @State private var triggers = ""
    @State private var systemPrompt = ""
    var onCreated: () -> Void = {}

    private let modelOptions = [
        "anthropic/claude-sonnet-4-20250514",
        "anthropic/claude-haiku-4-5-20251001",
        "google/gemini-2.5-flash",
        "google/gemini-2.5-pro",
        "openai/gpt-4.1",
        "openai/o4-mini",
        "xai/grok-3",
        "deepseek/deepseek-chat",
        "claude-code",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Agent")
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
                    FormField(label: "Name") {
                        TextField("agent-name", text: $name)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontBody)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    FormField(label: "Description") {
                        TextField("What does this agent do?", text: $description)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontBody)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    FormField(label: "Model") {
                        Picker("", selection: $model) {
                            ForEach(modelOptions, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppTheme.accent)
                    }

                    FormField(label: "Backend") {
                        Picker("", selection: $backend) {
                            Text("API").tag("api")
                            Text("Claude Code (local)").tag("claude-code")
                        }
                        .pickerStyle(.segmented)
                    }

                    FormField(label: "Triggers (comma separated)") {
                        TextField("code, debug, implement, fix", text: $triggers)
                            .textFieldStyle(.plain)
                            .font(AppTheme.fontBody)
                            .padding(10)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    FormField(label: "System Prompt") {
                        TextEditor(text: $systemPrompt)
                            .font(AppTheme.fontMono)
                            .foregroundColor(AppTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 80)
                            .background(AppTheme.bgPrimary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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

                Button(action: {
                    saveAgent()
                    onCreated()
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Agent")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(name.isEmpty ? AppTheme.textMuted : AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520, height: 600)
        .background(AppTheme.bgSecondary)
    }

    private func saveAgent() {
        let triggerList = triggers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var content = "---\n"
        content += "name: \(name)\n"
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

        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(name).md"
        try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/.desktop-agent/agents", withIntermediateDirectories: true)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

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
