import SwiftUI
import AppKit

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

// MARK: - Auto-growing NSTextView wrapper

/// A multi-line text editor backed by NSTextView that:
/// - Starts at single-line height and auto-grows up to `maxLines`
/// - Submits on Return, inserts newline on Shift+Return
/// - Transparent background to blend with glass styling
struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var placeholderText: String
    var isDisabled: Bool
    var isFocused: Binding<Bool>
    var onSubmit: () -> Void

    private let lineHeight: CGFloat = 20
    private let maxLines: Int = 5
    private let singleLineHeight: CGFloat = 22

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width]

        let textView = SubmittableTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = !isDisabled
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Placeholder support
        context.coordinator.textView = textView
        context.coordinator.placeholderText = placeholderText

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmittableTextView else { return }

        // Update submit closure
        textView.onSubmit = onSubmit

        // Only update text if it differs (avoid cursor jumping)
        if textView.string != text {
            textView.string = text
            context.coordinator.updatePlaceholder()
            context.coordinator.recalcHeight(for: textView, in: scrollView)
        }

        textView.isEditable = !isDisabled

        // Handle focus requests
        if isFocused.wrappedValue, textView.window != nil, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var textView: NSTextView?
        var placeholderText: String = ""
        private var placeholderLayer: CATextLayer?

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updatePlaceholder()

            if let scrollView = textView.enclosingScrollView {
                recalcHeight(for: textView, in: scrollView)
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }

        func updatePlaceholder() {
            guard let textView = textView else { return }
            if textView.string.isEmpty {
                if placeholderLayer == nil {
                    let layer = CATextLayer()
                    layer.string = placeholderText
                    layer.font = textView.font
                    layer.fontSize = textView.font?.pointSize ?? 14
                    layer.foregroundColor = NSColor(AppTheme.textMuted).cgColor
                    layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
                    placeholderLayer = layer
                }
                if let layer = placeholderLayer, layer.superlayer == nil {
                    textView.wantsLayer = true
                    layer.frame = CGRect(x: textView.textContainerInset.width,
                                         y: textView.textContainerInset.height,
                                         width: textView.bounds.width - textView.textContainerInset.width * 2,
                                         height: parent.singleLineHeight)
                    textView.layer?.addSublayer(layer)
                }
            } else {
                placeholderLayer?.removeFromSuperlayer()
            }
        }

        func recalcHeight(for textView: NSTextView, in scrollView: NSScrollView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let insetHeight = textView.textContainerInset.height * 2
            let naturalHeight = usedRect.height + insetHeight
            let minH = parent.singleLineHeight
            let maxH = parent.lineHeight * CGFloat(parent.maxLines) + insetHeight
            let targetHeight = min(max(naturalHeight, minH), maxH)

            // Enable scrolling only when at max
            scrollView.hasVerticalScroller = naturalHeight > maxH

            let heightConstraint = scrollView.constraints.first { $0.firstAttribute == .height }
            if let existing = heightConstraint {
                if existing.constant != targetHeight {
                    existing.constant = targetHeight
                }
            } else {
                let c = scrollView.heightAnchor.constraint(equalToConstant: targetHeight)
                c.priority = .defaultHigh
                c.isActive = true
            }
        }
    }
}

/// NSTextView subclass that intercepts Return (submit) vs Shift+Return (newline).
class SubmittableTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Return key without Shift modifier -> submit
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - ChatInputBar

struct ChatInputBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var text: String
    @Binding var attachedFiles: [URL]
    var isDisabled: Bool = false
    var onSubmit: () -> Void

    @State private var isFocused: Bool = false
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
                Button(action: openFilePicker) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Attach files")
                .padding(.bottom, 2)

                GrowingTextEditor(
                    text: $text,
                    font: NSFont.systemFont(ofSize: 14),
                    textColor: NSColor(AppTheme.textPrimary),
                    placeholderText: "Message...",
                    isDisabled: isDisabled,
                    isFocused: $isFocused,
                    onSubmit: submitIfValid
                )

                Button(action: submitIfValid) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSubmit ? AppTheme.accent : AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .background(AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
            )
        }
        .onChange(of: text) { _, newValue in
            if newValue.hasPrefix("/") {
                showSlashMenu = true
                slashFilter = String(newValue.dropFirst())
            } else {
                showSlashMenu = false
            }
        }
        .onChange(of: appState.shouldFocusInput) { _, shouldFocus in
            if shouldFocus {
                isFocused = true
                appState.shouldFocusInput = false
            }
        }
    }

    private var canSubmit: Bool {
        !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitIfValid() {
        guard canSubmit else { return }
        onSubmit()
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Attach Files"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if !attachedFiles.contains(url) {
                attachedFiles.append(url)
            }
        }
    }
}
