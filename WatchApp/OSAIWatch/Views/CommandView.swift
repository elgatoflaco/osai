import SwiftUI
import WatchKit

struct CommandView: View {
    @EnvironmentObject var connection: AgentConnection
    @EnvironmentObject var settings: WatchSettings
    @State private var inputText: String = ""
    @State private var crownValue: Double = 0
    @State private var selectedPresetIndex: Int = 0
    @State private var isSending: Bool = false
    @State private var recentCommands: [String] = []

    private let presets = PresetCommand.defaults

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Dictation Input
                dictationSection

                // Preset Commands
                presetSection

                // Recent Commands
                recentSection
            }
            .padding(.horizontal, 4)
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: Double(presets.count - 1),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: settings.hapticFeedbackEnabled
        )
        .onChange(of: crownValue) { _, newValue in
            selectedPresetIndex = min(max(Int(newValue.rounded()), 0), presets.count - 1)
        }
        .navigationTitle("Command")
        .onAppear {
            loadRecentCommands()
        }
    }

    // MARK: - Dictation Section

    private var dictationSection: some View {
        VStack(spacing: 8) {
            Button {
                presentTextInput()
            } label: {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.blue)
                    Text(inputText.isEmpty ? "Tap to dictate..." : inputText)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(inputText.isEmpty ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            if !inputText.isEmpty {
                Button {
                    sendCommand(inputText)
                } label: {
                    HStack {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Send")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isSending || connection.connectionState != .connected)
            }
        }
    }

    // MARK: - Preset Commands

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                Button {
                    sendCommand(preset.command)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: preset.icon)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .frame(width: 20)

                        Text(preset.label)
                            .font(.callout)

                        Spacer()

                        if index == selectedPresetIndex {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        index == selectedPresetIndex
                            ? Color.blue.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSending || connection.connectionState != .connected)
                .contextMenu {
                    Button {
                        inputText = preset.command
                    } label: {
                        Label("Edit Before Sending", systemImage: "pencil")
                    }
                }
            }
        }
    }

    // MARK: - Recent Commands

    private var recentSection: some View {
        Group {
            if !recentCommands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Clear") {
                            recentCommands.removeAll()
                            saveRecentCommands()
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    ForEach(recentCommands.prefix(5), id: \.self) { command in
                        Button {
                            sendCommand(command)
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Text(command)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                recentCommands.removeAll { $0 == command }
                                saveRecentCommands()
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func presentTextInput() {
        WKExtension.shared().visibleInterfaceController?.presentTextInputController(
            withSuggestions: presets.map { $0.command },
            allowedInputMode: .allowEmoji
        ) { results in
            if let text = results?.first as? String {
                inputText = text
            }
        }
    }

    private func sendCommand(_ text: String) {
        guard !text.isEmpty else { return }
        isSending = true

        // Save to recent
        recentCommands.removeAll { $0 == text }
        recentCommands.insert(text, at: 0)
        if recentCommands.count > 10 {
            recentCommands = Array(recentCommands.prefix(10))
        }
        saveRecentCommands()

        Task {
            await connection.sendMessage(text: text)
            await MainActor.run {
                isSending = false
                inputText = ""
                if settings.hapticFeedbackEnabled {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadRecentCommands() {
        recentCommands = UserDefaults.standard.stringArray(forKey: "osai.recent.commands") ?? []
    }

    private func saveRecentCommands() {
        UserDefaults.standard.set(recentCommands, forKey: "osai.recent.commands")
    }
}

#Preview {
    NavigationStack {
        CommandView()
            .environmentObject(AgentConnection())
            .environmentObject(WatchSettings())
    }
}
