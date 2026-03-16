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
                .accessibilityLabel("Message input")
                .accessibilityHint("Type a message and press Enter to send")
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
            .accessibilityLabel("Send message")
            .accessibilityHint(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Type a message first" : "Double tap to send")
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
    var onUpArrowInEmptyInput: (() -> Void)?
    var onDownArrowHistory: (() -> Void)?
    var onEscapeKey: (() -> Void)?
    var onPasteImages: (([URL]) -> Void)?
    var onUserTyped: (() -> Void)?
    var isBrowsingHistory: Bool = false

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
        textView.onUpArrowInEmptyInput = onUpArrowInEmptyInput
        textView.onDownArrowHistory = onDownArrowHistory
        textView.onEscapeKey = onEscapeKey
        textView.onPasteImages = onPasteImages
        textView.isBrowsingHistory = isBrowsingHistory
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

        // Update closures
        textView.onSubmit = onSubmit
        textView.onUpArrowInEmptyInput = onUpArrowInEmptyInput
        textView.onDownArrowHistory = onDownArrowHistory
        textView.onEscapeKey = onEscapeKey
        textView.onPasteImages = onPasteImages
        textView.isBrowsingHistory = isBrowsingHistory

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
            parent.onUserTyped?()
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

/// NSTextView subclass that intercepts Return (submit) vs Shift+Return (newline),
/// Up arrow in empty input to recall the last user message, and Cmd+V to paste images.
class SubmittableTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onUpArrowInEmptyInput: (() -> Void)?
    var onDownArrowHistory: (() -> Void)?
    var onEscapeKey: (() -> Void)?
    var onPasteImages: (([URL]) -> Void)?

    /// Whether the user is currently browsing input history (enables down-arrow navigation)
    var isBrowsingHistory: Bool = false

    override func keyDown(with event: NSEvent) {
        // Return key without Shift modifier -> submit
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        // Up arrow: navigate history when input is empty or cursor is at the very beginning
        if event.keyCode == 126 {
            let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let atBeginning = selectedRange().location == 0 && selectedRange().length == 0
            if isEmpty || atBeginning || isBrowsingHistory {
                onUpArrowInEmptyInput?()
                return
            }
        }
        // Down arrow: navigate history forward when browsing
        if event.keyCode == 125 && isBrowsingHistory {
            onDownArrowHistory?()
            return
        }
        // Escape key -> clear input or bubble up
        if event.keyCode == 53 {
            onEscapeKey?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // Check for image data on the pasteboard before falling back to default paste
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        let hasImage = imageTypes.contains(where: { pb.data(forType: $0) != nil })

        if hasImage, let handler = onPasteImages {
            var savedURLs: [URL] = []

            for imageType in imageTypes {
                if let data = pb.data(forType: imageType) {
                    let ext = imageType == .png ? "png" : "tiff"
                    let tempDir = FileManager.default.temporaryDirectory
                    let filename = "pasted-image-\(UUID().uuidString.prefix(8)).\(ext)"
                    let fileURL = tempDir.appendingPathComponent(filename)
                    do {
                        // Convert TIFF to PNG for consistency
                        if imageType == .tiff, let image = NSImage(data: data),
                           let tiffData = image.tiffRepresentation,
                           let bitmap = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmap.representation(using: .png, properties: [:]) {
                            let pngURL = tempDir.appendingPathComponent("pasted-image-\(UUID().uuidString.prefix(8)).png")
                            try pngData.write(to: pngURL)
                            savedURLs.append(pngURL)
                        } else {
                            try data.write(to: fileURL)
                            savedURLs.append(fileURL)
                        }
                    } catch {
                        // Fall through to default paste
                    }
                    break // Only handle the first available image type
                }
            }

            if !savedURLs.isEmpty {
                handler(savedURLs)
                return
            }
        }

        // Default paste behavior for text
        super.paste(sender)
    }
}

// MARK: - Model Selector

struct ModelSelectorButton: View {
    @EnvironmentObject var appState: AppState
    @State private var showPopover = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: appState.modelDefinition(for: appState.selectedModel)?.icon ?? "cpu")
                    .font(.system(size: 10))
                Text(appState.selectedModelShortName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.bgCard.opacity(0.8))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppTheme.borderGlass, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select model")
        .accessibilityValue(appState.selectedModelShortName)
        .accessibilityHint("Double tap to change the AI model")
        .help("Change model")
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            ModelSelectorPopover(isPresented: $showPopover)
                .environmentObject(appState)
        }
    }
}

struct ModelSelectorPopover: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select Model")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().background(AppTheme.borderGlass)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.modelsGroupedByProvider, id: \.provider) { group in
                        // Provider header
                        Text(group.provider)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.textMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(group.models) { model in
                            let isSelected = appState.selectedModel == model.id
                            let hasKey = appState.hasAPIKey(for: model.providerKey)

                            Button(action: {
                                if hasKey {
                                    appState.selectedModel = model.id
                                    isPresented = false
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: model.icon)
                                        .font(.system(size: 12))
                                        .foregroundColor(hasKey ? AppTheme.accent : AppTheme.textMuted)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(model.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(hasKey ? AppTheme.textPrimary : AppTheme.textMuted)
                                        if !hasKey {
                                            Text("No API key")
                                                .font(.system(size: 10))
                                                .foregroundColor(AppTheme.error.opacity(0.7))
                                        }
                                    }

                                    Spacer()

                                    Text(model.tag)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(hasKey ? tagColor(model.tag) : AppTheme.textMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((hasKey ? tagColor(model.tag) : AppTheme.textMuted).opacity(0.12))
                                        .clipShape(Capsule())

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(isSelected ? AppTheme.accent.opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasKey)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .frame(width: 280, height: 360)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "Fast": return AppTheme.success
        case "Smart": return AppTheme.accent
        case "Powerful": return Color.purple
        case "Vision": return Color.blue
        case "Reasoning": return Color.orange
        case "Local": return AppTheme.textSecondary
        default: return AppTheme.textSecondary
        }
    }
}

// MARK: - ChatInputBar

struct ChatInputBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var text: String
    @Binding var attachedFiles: [URL]
    var isDisabled: Bool = false
    var isDragOver: Bool = false
    var onUpArrowInEmptyInput: (() -> Void)?
    var onDownArrowHistory: (() -> Void)?
    var onPasteImages: (([URL]) -> Void)?
    var onSubmit: () -> Void

    @State private var isFocused: Bool = false
    @State private var showSlashMenu = false
    @State private var slashFilter = ""
    @State private var showTemplatePopover = false
    @State private var showTemplateManager = false

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
                            .accessibilityLabel("\(cmd.command), \(cmd.description)")
                        }
                    }
                    .accessibilityLabel("Slash commands menu")
                    .background(AppTheme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.borderGlass, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: -4)
                    .frame(maxWidth: 350)
                    .padding(.bottom, 6)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                ModelSelectorButton()
                    .padding(.bottom, 2)

                Button(action: openFilePicker) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach files")
                .accessibilityHint("Double tap to open file picker")
                .help("Attach files")
                .padding(.bottom, 2)

                Button(action: { showTemplatePopover.toggle() }) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Prompt templates")
                .accessibilityHint("Double tap to browse and insert prompt templates")
                .help("Prompt templates")
                .padding(.bottom, 2)
                .popover(isPresented: $showTemplatePopover, arrowEdge: .top) {
                    PromptTemplatePopover(
                        text: $text,
                        isPresented: $showTemplatePopover,
                        showManager: $showTemplateManager
                    )
                    .environmentObject(appState)
                }

                GrowingTextEditor(
                    text: $text,
                    font: NSFont.systemFont(ofSize: 14),
                    textColor: NSColor(AppTheme.textPrimary),
                    placeholderText: "Message...",
                    isDisabled: isDisabled,
                    isFocused: $isFocused,
                    onSubmit: submitIfValid,
                    onUpArrowInEmptyInput: onUpArrowInEmptyInput,
                    onDownArrowHistory: onDownArrowHistory,
                    onEscapeKey: {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            text = ""
                        } else {
                            appState.closeCurrentConversation()
                        }
                    },
                    onPasteImages: onPasteImages,
                    onUserTyped: {
                        appState.resetInputHistoryNavigation()
                    },
                    isBrowsingHistory: appState.isBrowsingInputHistory
                )
                .accessibilityLabel("Message input")
                .accessibilityHint("Type a message and press Enter to send. Shift+Enter for new line.")

                Button(action: submitIfValid) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSubmit ? AppTheme.accent : AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityLabel("Send message")
                .accessibilityHint(canSubmit ? "Double tap to send" : "Type a message first")
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .background(AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isDragOver ? AppTheme.accent.opacity(0.7) :
                        isFocused ? AppTheme.accent.opacity(0.3) :
                        AppTheme.borderGlass,
                        lineWidth: isDragOver ? 2 : 1
                    )
            )
            .shadow(color: isDragOver ? AppTheme.accentGlow.opacity(0.35) : .clear, radius: 16, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.25), value: isDragOver)

            // History browsing indicator
            if appState.isBrowsingInputHistory {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text("History \(appState.inputHistoryPositionLabel)")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(AppTheme.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.bgCard.opacity(0.6))
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.15), value: appState.isBrowsingInputHistory)
                .padding(.top, 4)
                .accessibilityLabel("Browsing input history, position \(appState.inputHistoryPositionLabel)")
            }
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
        .sheet(isPresented: $showTemplateManager) {
            PromptTemplateManagerSheet()
                .environmentObject(appState)
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

// MARK: - Prompt Template Popover

struct PromptTemplatePopover: View {
    @EnvironmentObject var appState: AppState
    @Binding var text: String
    @Binding var isPresented: Bool
    @Binding var showManager: Bool
    @State private var searchText = ""
    @State private var showSaveSheet = false
    @State private var newTemplateName = ""
    @State private var newTemplateCategory = "Custom"

    private var filteredTemplates: [PromptTemplate] {
        if searchText.isEmpty {
            return appState.promptTemplates
        }
        let query = searchText.lowercased()
        return appState.promptTemplates.filter {
            $0.name.lowercased().contains(query) ||
            $0.content.lowercased().contains(query) ||
            $0.category.lowercased().contains(query)
        }
    }

    private var groupedTemplates: [(category: String, templates: [PromptTemplate])] {
        let grouped = Dictionary(grouping: filteredTemplates, by: { $0.category })
        return PromptTemplate.categories.compactMap { cat in
            guard let templates = grouped[cat], !templates.isEmpty else { return nil }
            return (category: cat, templates: templates)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Prompt Templates")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showManager = true
                    }
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Manage templates")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)
                TextField("Filter templates...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.bgCard.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider().background(AppTheme.borderGlass)

            // Templates list
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    if groupedTemplates.isEmpty {
                        Text("No templates found")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(groupedTemplates, id: \.category) { group in
                            Text(group.category)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.textMuted)
                                .textCase(.uppercase)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 4)

                            ForEach(group.templates) { template in
                                Button(action: {
                                    text = template.content
                                    isPresented = false
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: template.icon)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.accent)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(template.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(template.content.prefix(60) + (template.content.count > 60 ? "..." : ""))
                                                .font(.system(size: 10))
                                                .foregroundColor(AppTheme.textMuted)
                                                .lineLimit(1)
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
                    }
                }
                .padding(.bottom, 6)
            }

            // Save current as template
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().background(AppTheme.borderGlass)
                Button(action: { showSaveSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.accent)
                        Text("Save current as template")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300, height: 380)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgGlass)
        .popover(isPresented: $showSaveSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save as Template")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                TextField("Template name", text: $newTemplateName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Picker("Category", selection: $newTemplateCategory) {
                    ForEach(PromptTemplate.categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 11))

                HStack {
                    Spacer()
                    Button("Cancel") { showSaveSheet = false }
                        .buttonStyle(.plain)
                        .foregroundColor(AppTheme.textSecondary)
                    Button("Save") {
                        let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let icon = PromptTemplate.categoryIcons[newTemplateCategory] ?? "star"
                        appState.savePromptTemplate(name: name, content: text, category: newTemplateCategory, icon: icon)
                        newTemplateName = ""
                        showSaveSheet = false
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .frame(width: 280)
        }
    }
}

// MARK: - Prompt Template Manager Sheet

struct PromptTemplateManagerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: PromptTemplate?
    @State private var showCreateNew = false
    @State private var editName = ""
    @State private var editContent = ""
    @State private var editCategory = "Custom"
    @State private var editIcon = "star"

    private let iconOptions = [
        "star", "magnifyingglass.circle", "doc.text.magnifyingglass",
        "globe", "face.smiling", "checkmark.shield",
        "pencil", "lightbulb", "hammer", "terminal",
        "book", "brain.head.profile", "text.bubble",
        "arrow.triangle.2.circlepath", "wand.and.stars",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Templates")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button(action: { showCreateNew = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Create new template")
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.accent)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(16)

            Divider().background(AppTheme.borderGlass)

            // Template list
            List {
                ForEach(PromptTemplate.categories, id: \.self) { category in
                    let templates = appState.promptTemplates.filter { $0.category == category }
                    if !templates.isEmpty {
                        Section(header: Text(category).font(.system(size: 11, weight: .semibold)).foregroundColor(AppTheme.textMuted)) {
                            ForEach(templates) { template in
                                HStack(spacing: 10) {
                                    Image(systemName: template.icon)
                                        .font(.system(size: 13))
                                        .foregroundColor(AppTheme.accent)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                        Text(template.content.prefix(80) + (template.content.count > 80 ? "..." : ""))
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textMuted)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button(action: {
                                        selectedTemplate = template
                                        editName = template.name
                                        editContent = template.content
                                        editCategory = template.category
                                        editIcon = template.icon
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: {
                                        appState.deletePromptTemplate(id: template.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.error)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 520, height: 480)
        .background(.ultraThinMaterial)
        .sheet(item: $selectedTemplate) { template in
            templateEditorSheet(isNew: false)
        }
        .sheet(isPresented: $showCreateNew) {
            templateEditorSheet(isNew: true)
        }
    }

    private func templateEditorSheet(isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Template" : "Edit Template")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            TextField("Template name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            Text("Content")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            TextEditor(text: $editContent)
                .font(.system(size: 12))
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(AppTheme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.borderGlass, lineWidth: 1))

            Picker("Category", selection: $editCategory) {
                ForEach(PromptTemplate.categories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            .pickerStyle(.segmented)

            // Icon picker
            Text("Icon")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8), spacing: 6) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button(action: { editIcon = icon }) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(editIcon == icon ? .white : AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(editIcon == icon ? AppTheme.accent : AppTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    selectedTemplate = nil
                    showCreateNew = false
                    resetEditor()
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.textSecondary)

                Button(isNew ? "Create" : "Save") {
                    let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    if isNew {
                        appState.savePromptTemplate(name: name, content: editContent, category: editCategory, icon: editIcon)
                        showCreateNew = false
                    } else if var updated = selectedTemplate {
                        updated.name = name
                        updated.content = editContent
                        updated.category = editCategory
                        updated.icon = editIcon
                        appState.updatePromptTemplate(updated)
                        selectedTemplate = nil
                    }
                    resetEditor()
                }
                .buttonStyle(.borderedProminent)
                .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 440)
    }

    private func resetEditor() {
        editName = ""
        editContent = ""
        editCategory = "Custom"
        editIcon = "star"
    }
}
