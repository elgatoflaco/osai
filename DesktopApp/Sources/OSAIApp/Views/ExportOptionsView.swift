import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportOptionsView: View {
    @EnvironmentObject var appState: AppState
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss

    @State private var format: AppState.ExportFormat = .markdown
    @State private var includeTimestamps = true
    @State private var includeToolActivities = true
    @State private var includeTokenStats = true
    @State private var showPreview = true

    private var options: AppState.ExportOptions {
        AppState.ExportOptions(
            format: format,
            includeTimestamps: includeTimestamps,
            includeToolActivities: includeToolActivities,
            includeTokenStats: includeTokenStats
        )
    }

    private var exportContent: String {
        appState.generateExport(for: conversation, options: options)
    }

    private var previewText: String {
        let content = exportContent
        if content.count <= 500 { return content }
        return String(content.prefix(500)) + "\n..."
    }

    @ViewBuilder
    private var previewContent: some View {
        switch format {
        case .markdown:
            markdownPreview
        case .json:
            Text(previewText)
                .font(AppTheme.fontMono)
                .foregroundColor(AppTheme.accent)
        case .plainText:
            Text(previewText)
                .font(AppTheme.fontBody)
                .foregroundColor(AppTheme.textPrimary)
        case .html:
            Text(previewText)
                .font(AppTheme.fontMono)
                .foregroundColor(AppTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        let lines = previewText.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("# ") {
                    Text(line.dropFirst(2))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.bottom, 2)
                } else if line.hasPrefix("## ") {
                    Text(line.dropFirst(3))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.bottom, 1)
                } else if line.hasPrefix("### ") {
                    Text(line.dropFirst(4))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                            .foregroundColor(AppTheme.accent)
                        Text(line.dropFirst(2))
                            .font(AppTheme.fontBody)
                            .foregroundColor(AppTheme.textPrimary)
                    }
                } else if line.hasPrefix("```") {
                    Text(line)
                        .font(AppTheme.fontMono)
                        .foregroundColor(AppTheme.textMuted)
                } else if line.hasPrefix("> ") {
                    Text(line.dropFirst(2))
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(AppTheme.accent.opacity(0.4))
                                .frame(width: 3)
                        }
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    Text(line)
                        .font(AppTheme.fontBody)
                        .foregroundColor(AppTheme.textPrimary)
                }
            }
        }
    }

    /// Estimates byte size of the export and returns a human-readable string.
    private func estimatedSize(for fmt: AppState.ExportFormat) -> String {
        let opts = AppState.ExportOptions(
            format: fmt,
            includeTimestamps: includeTimestamps,
            includeToolActivities: includeToolActivities,
            includeTokenStats: includeTokenStats
        )
        let content = appState.generateExport(for: conversation, options: opts)
        let bytes = content.utf8.count
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Conversation")
                        .font(AppTheme.fontHeadline)
                        .foregroundColor(AppTheme.textPrimary)
                    Text(conversation.title)
                        .font(AppTheme.fontCaption)
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.paddingLg)

            Divider().background(AppTheme.borderGlass)

            ScrollView {
                VStack(spacing: AppTheme.paddingMd) {
                    // Format cards
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textSecondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], spacing: 10) {
                            ForEach(AppState.ExportFormat.allCases) { fmt in
                                FormatCard(
                                    format: fmt,
                                    isSelected: format == fmt,
                                    estimatedSize: estimatedSize(for: fmt)
                                ) {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        format = fmt
                                    }
                                }
                            }
                        }
                    }

                    // Options toggles
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Options")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textSecondary)

                        optionToggle(
                            "Include timestamps",
                            icon: "clock",
                            isOn: $includeTimestamps
                        )
                        optionToggle(
                            "Include tool activities",
                            icon: "wrench.and.screwdriver",
                            isOn: $includeToolActivities
                        )
                        optionToggle(
                            "Include token stats",
                            icon: "number",
                            isOn: $includeTokenStats
                        )
                    }

                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Preview")
                                .font(AppTheme.fontCaption)
                                .foregroundColor(AppTheme.textSecondary)
                            Spacer()
                            Text("\(exportContent.count) chars")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showPreview.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showPreview ? "eye.fill" : "eye.slash")
                                        .font(.system(size: 10))
                                    Text(showPreview ? "Hide" : "Show")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }

                        if showPreview {
                            ScrollView {
                                previewContent
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(AppTheme.paddingSm)
                            }
                            .frame(height: 160)
                            .background(.ultraThinMaterial)
                            .background(AppTheme.bgGlass)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                                    .stroke(AppTheme.borderGlass, lineWidth: 1)
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(AppTheme.paddingLg)
            }

            Divider().background(AppTheme.borderGlass)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(ExportButtonStyle())

                Button(action: shareContent) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(ExportButtonStyle())

                Spacer()

                Button(action: saveToFile) {
                    Label("Save to File", systemImage: "arrow.down.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .buttonStyle(ExportPrimaryButtonStyle())
            }
            .padding(AppTheme.paddingLg)
        }
        .frame(width: 520, height: 640)
        .background(.ultraThinMaterial)
        .background(AppTheme.bgPrimary)
    }

    // MARK: - Components

    private func optionToggle(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textMuted)
                .frame(width: 16)
            Text(label)
                .font(AppTheme.fontBody)
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.bgSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportContent, forType: .string)
        appState.showToast("Copied to clipboard", type: .success)
        dismiss()
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.title = "Save Export"
        let safeName = conversation.title
            .replacingOccurrences(of: "[^a-zA-Z0-9_ -]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = String(safeName.prefix(60)) + "." + format.fileExtension

        switch format {
        case .markdown, .plainText:
            panel.allowedContentTypes = [.plainText]
        case .json:
            panel.allowedContentTypes = [.json]
        case .html:
            panel.allowedContentTypes = [.html]
        }
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = exportContent
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            appState.showToast("Exported to \(url.lastPathComponent)", type: .success)
            dismiss()
        } catch {
            appState.showToast("Export failed: \(error.localizedDescription)", type: .error)
        }
    }

    private func shareContent() {
        let content = exportContent
        let picker = NSSharingServicePicker(items: [content as NSString])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}

// MARK: - Format Card

private struct FormatCard: View {
    let format: AppState.ExportFormat
    let isSelected: Bool
    let estimatedSize: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: format.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? AppTheme.accent.opacity(0.15) : AppTheme.bgSecondary.opacity(0.5))
                        )
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accent)
                    }
                }

                Text(format.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Text(format.description)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(".\(format.fileExtension)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                    Spacer()
                    Text("~\(estimatedSize)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                }
                .padding(.top, 2)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .background(AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(
                        isSelected ? AppTheme.accent.opacity(0.5) : (isHovered ? AppTheme.accent.opacity(0.25) : AppTheme.borderGlass),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(isHovered ? 0.3 : 0.15), radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 6 : 4)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Button Styles

struct ExportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppTheme.bgSecondary.opacity(configuration.isPressed ? 0.8 : 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.borderGlass, lineWidth: 1)
            )
    }
}

struct ExportPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.accent.opacity(configuration.isPressed ? 0.7 : 1.0))
            )
    }
}
