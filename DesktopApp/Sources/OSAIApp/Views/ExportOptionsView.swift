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
                    // Format selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format")
                            .font(AppTheme.fontCaption)
                            .foregroundColor(AppTheme.textSecondary)

                        Picker("Format", selection: $format) {
                            ForEach(AppState.ExportFormat.allCases) { fmt in
                                HStack(spacing: 4) {
                                    Image(systemName: fmt.icon)
                                    Text(fmt.rawValue)
                                }
                                .tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
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
                        }

                        ScrollView {
                            Text(previewText)
                                .font(AppTheme.fontMono)
                                .foregroundColor(AppTheme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AppTheme.paddingSm)
                        }
                        .frame(height: 180)
                        .background(AppTheme.bgSecondary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                                .stroke(AppTheme.borderGlass, lineWidth: 1)
                        )
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
        .frame(width: 520, height: 580)
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
