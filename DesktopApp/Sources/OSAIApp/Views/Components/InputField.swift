import SwiftUI

struct TaskInputField: View {
    @Binding var text: String
    var placeholder: String = "Ask anything..."
    var onSubmit: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.accent.opacity(0.6))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPrimary)
                .focused($fieldFocused)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSubmit()
                    }
                }

            Button(action: {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onSubmit()
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.textMuted : AppTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    fieldFocused ? AppTheme.accent.opacity(0.4) : AppTheme.borderGlass,
                    lineWidth: fieldFocused ? 1.5 : 1
                )
        )
        .shadow(color: fieldFocused ? AppTheme.accentGlow.opacity(0.2) : .black.opacity(0.15), radius: fieldFocused ? 20 : 12, x: 0, y: 6)
        .animation(.easeOut(duration: 0.2), value: fieldFocused)
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    var isDisabled: Bool = false
    var onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var showSlashMenu = false
    @State private var slashFilter = ""

    private let slashCommands: [(command: String, icon: String, description: String)] = [
        ("/new", "plus.circle", "Start new conversation"),
        ("/clear", "trash", "Clear current chat"),
        ("/compact", "arrow.down.right.and.arrow.up.left", "Compact context window"),
        ("/model", "cpu", "Change model"),
        ("/agent", "person.circle", "Select agent"),
        ("/help", "questionmark.circle", "Show help"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Slash command menu
            if showSlashMenu {
                let filtered = slashCommands.filter { cmd in
                    slashFilter.isEmpty || cmd.command.contains(slashFilter.lowercased())
                }
                if !filtered.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { _, cmd in
                            Button(action: {
                                text = cmd.command + " "
                                showSlashMenu = false
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: cmd.icon)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.accent)
                                        .frame(width: 16)
                                    Text(cmd.command)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Text(cmd.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.textMuted)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(AppTheme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.borderGlass, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
                    .frame(maxWidth: 350)
                    .padding(.bottom, 6)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Use a regular single-line TextField that responds to Enter
                TextField("Message...", text: $text)
                    .textFieldStyle(.plain)
                    .font(AppTheme.fontBody)
                    .foregroundColor(AppTheme.textPrimary)
                    .focused($isFocused)
                    .disabled(isDisabled)
                    .onSubmit {
                        submitIfValid()
                    }
                    .onChange(of: text) { _, newValue in
                        if newValue.hasPrefix("/") {
                            showSlashMenu = true
                            slashFilter = String(newValue.dropFirst())
                        } else {
                            showSlashMenu = false
                        }
                    }

                Button(action: submitIfValid) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSubmit ? AppTheme.accent : AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .background(AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
            )
        }
    }

    private var canSubmit: Bool {
        !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitIfValid() {
        guard canSubmit else { return }
        onSubmit()
    }
}
