import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedAgent: AgentInfo?
    @State private var showCreateSheet = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        HStack(spacing: 0) {
            // Agent list
            VStack(spacing: 0) {
                HStack {
                    Text("Agents")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)

                    Text("(\(appState.agents.count))")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textMuted)

                    Spacer()

                    Button(action: { showCreateSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Create Agent")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(AppTheme.borderGlass)

                if appState.agents.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "person.3")
                            .font(.system(size: 28))
                            .foregroundColor(AppTheme.textMuted)
                        Text("No agents")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                        Button("Create one") { showCreateSheet = true }
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accent)
                            .buttonStyle(.plain)
                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(appState.agents) { agent in
                                AgentListRow(
                                    agent: agent,
                                    isSelected: selectedAgent?.id == agent.id
                                ) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedAgent = agent
                                        testResult = nil
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(width: 240)
            .background(AppTheme.bgSecondary.opacity(0.3))

            Divider().background(AppTheme.borderGlass)

            // Detail panel
            if let agent = selectedAgent {
                AgentDetailPanel(
                    agent: agent,
                    testResult: $testResult,
                    isTesting: $isTesting,
                    onTest: { testAgent(agent) },
                    onDelete: {
                        appState.deleteAgent(agent)
                        selectedAgent = nil
                    },
                    onChat: {
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
                )
            } else {
                // Empty detail
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "person.3")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.textMuted)
                    Text("Select an agent to view details")
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textSecondary)
                    Text("or create a new one")
                        .font(AppTheme.fontCaption)
                        .foregroundColor(AppTheme.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAgentSheet {
                appState.agents = appState.service.loadAgents()
            }
        }
    }

    private func testAgent(_ agent: AgentInfo) {
        isTesting = true
        testResult = nil
        Task {
            do {
                let result = try await appState.service.run(args: ["--model", agent.model, "Say hello in 10 words or less"])
                await MainActor.run {
                    testResult = result.isEmpty ? "(empty response)" : result
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "Error: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Agent List Row

struct AgentListRow: View {
    let agent: AgentInfo
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                GhostIcon(size: 22, animate: false, tint: agentColor(agent.name))

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name.capitalized)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .lineLimit(1)
                    Text(agent.displayModel)
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: agent.backendIcon)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppTheme.accent.opacity(0.12) : (isHovered ? AppTheme.bgCard.opacity(0.4) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.2) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Agent Detail Panel

struct AgentDetailPanel: View {
    let agent: AgentInfo
    @Binding var testResult: String?
    @Binding var isTesting: Bool
    let onTest: () -> Void
    let onDelete: () -> Void
    let onChat: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.paddingLg) {
                // Header
                HStack(spacing: 14) {
                    GhostIcon(size: 48, animate: false, tint: agentColor(agent.name))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.name.capitalized)
                            .font(AppTheme.fontTitle)
                            .foregroundColor(AppTheme.textPrimary)

                        Text(agent.description)
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()
                }

                // Action buttons
                HStack(spacing: 10) {
                    ActionButton(label: "Chat", icon: "bubble.left", color: AppTheme.accent, action: onChat)
                    ActionButton(label: "Test", icon: "play.circle", color: AppTheme.success, action: onTest)
                    ActionButton(label: "Open File", icon: "doc.text", color: AppTheme.textSecondary) {
                        let path = NSHomeDirectory() + "/.desktop-agent/agents/\(agent.name).md"
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

                // Info cards
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "Model", value: agent.model, icon: "cpu")
                        Divider().background(AppTheme.borderGlass)
                        InfoRow(label: "Provider", value: agent.providerName, icon: "cloud")
                        Divider().background(AppTheme.borderGlass)
                        InfoRow(label: "Backend", value: agent.backendLabel, icon: agent.backendIcon)
                    }
                }

                // Triggers
                if !agent.triggers.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "tag")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.accent)
                                Text("Triggers (\(agent.triggers.count))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                            }

                            FlowLayout(spacing: 6) {
                                ForEach(agent.triggers, id: \.self) { trigger in
                                    Text(trigger)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(AppTheme.bgPrimary.opacity(0.4))
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                    }
                }

                // System Prompt
                if !agent.systemPrompt.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.accent)
                                Text("System Prompt")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                            }

                            Text(agent.systemPrompt)
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

                // Test result
                if isTesting {
                    GlassCard {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing agent...")
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                        }
                    }
                }

                if let result = testResult {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.success)
                                Text("Test Result")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                            }

                            Text(result)
                                .font(AppTheme.fontBody)
                                .foregroundColor(AppTheme.textSecondary)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.bgPrimary.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // File path
                HStack {
                    Text("~/.desktop-agent/agents/\(agent.name).md")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                    Spacer()
                }

                Spacer(minLength: 40)
            }
            .padding(AppTheme.paddingXl)
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
