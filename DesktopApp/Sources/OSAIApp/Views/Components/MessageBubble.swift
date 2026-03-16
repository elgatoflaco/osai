import SwiftUI

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isLastAssistantMessage: Bool = false
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    @State private var appeared = false
    @State private var copied = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 60)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 20)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.accent.opacity(0.2), lineWidth: 0.5))

                Text(timeString(message.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.trailing, 4)
            }

            Image(systemName: "person.circle.fill")
                .font(.system(size: 26))
                .foregroundColor(AppTheme.textSecondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You said: \(message.content)")
        .accessibilityValue("at \(timeString(message.timestamp))")
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            GhostIcon(size: 26, animate: message.isStreaming, isProcessing: message.isStreaming)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                // Agent badge
                if let agent = message.agentName {
                    AgentBadge(name: agent)
                }

                // Activity strip
                if !message.activities.isEmpty {
                    ActivityStrip(activities: message.activities, isStreaming: message.isStreaming)
                }

                // Content with hover copy button
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let toolName = message.toolName {
                            ToolCallCard(name: toolName, result: message.toolResult ?? "")
                        } else if message.isStreaming && message.content.isEmpty {
                            StreamingPlaceholder(hasActivities: !message.activities.isEmpty)
                        } else if !message.content.isEmpty {
                            ResponseView(text: message.content, isStreaming: message.isStreaming)
                        }
                    }

                    // Copy & retry buttons on hover
                    if message.role == .assistant && !message.content.isEmpty && !message.isStreaming && (isHovered || copied) {
                        HStack(spacing: 4) {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 9))
                                    Text(copied ? "Copied" : "Copy").font(.system(size: 9))
                                }
                                .foregroundColor(copied ? AppTheme.success : AppTheme.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppTheme.bgCard.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(copied ? "Copied to clipboard" : "Copy response")

                            if isLastAssistantMessage, let onRetry = onRetry {
                                Button(action: onRetry) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.clockwise").font(.system(size: 9))
                                        Text("Retry").font(.system(size: 9))
                                    }
                                    .foregroundColor(AppTheme.textMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.bgCard.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Retry response")
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                }

                // Footer
                HStack(spacing: 10) {
                    Text(timeString(message.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textMuted)

                    Spacer()

                    if message.isStreaming, let onCancel = onCancel {
                        Button(action: onCancel) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.circle.fill").font(.system(size: 12))
                                Text("Stop").font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(AppTheme.error.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(AppTheme.error.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop generating response")
                    }
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.isStreaming ? "Assistant is responding" : "Assistant said")
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
}

// MARK: - Activity Strip (redesigned)

struct ActivityStrip: View {
    let activities: [ActivityItem]
    let isStreaming: Bool
    @State private var expanded = false
    @State private var expandedOutputId: String?

    private var completedCount: Int { activities.filter(\.isComplete).count }
    private var failedCount: Int { activities.filter { $0.success == false }.count }
    private var toolActivities: [ActivityItem] { activities.filter { $0.type == .toolCall } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            Button(action: { expanded.toggle() }) {
                HStack(spacing: 8) {
                    // Progress indicator
                    ZStack {
                        Circle()
                            .stroke(AppTheme.borderGlass, lineWidth: 2)
                            .frame(width: 18, height: 18)
                        Circle()
                            .trim(from: 0, to: activities.isEmpty ? 0 : CGFloat(completedCount) / CGFloat(activities.count))
                            .stroke(failedCount > 0 ? AppTheme.warning : AppTheme.success, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 18, height: 18)
                            .rotationEffect(.degrees(-90))
                        if completedCount == activities.count && !isStreaming {
                            Image(systemName: failedCount > 0 ? "exclamationmark" : "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(failedCount > 0 ? AppTheme.warning : AppTheme.success)
                        }
                    }

                    // Summary text
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summaryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                        if let current = activities.last(where: { !$0.isComplete }) {
                            let desc = !current.detail.isEmpty ? current.detail : current.label
                            Text(desc)
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Activity strip: \(summaryText)")
            .accessibilityHint(expanded ? "Double tap to collapse" : "Double tap to expand")
            .accessibilityValue(expanded ? "expanded" : "collapsed")

            // Expanded list
            if expanded {
                Divider()
                    .background(AppTheme.borderGlass)
                    .padding(.horizontal, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(activities) { activity in
                            ActivityRow(
                                activity: activity,
                                isOutputExpanded: expandedOutputId == activity.id,
                                onToggleOutput: {
                                    expandedOutputId = expandedOutputId == activity.id ? nil : activity.id
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4).padding(.vertical, 6)
                }
                .frame(maxHeight: 260)
            }
        }
        .background(AppTheme.bgCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.borderGlass, lineWidth: 0.5))
    }

    private var summaryText: String {
        if completedCount == activities.count && !isStreaming {
            if failedCount > 0 {
                return "\(activities.count) tasks (\(failedCount) failed)"
            }
            return "\(activities.count) tasks completed"
        }
        return "\(completedCount)/\(activities.count) tasks"
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: ActivityItem
    let isOutputExpanded: Bool
    let onToggleOutput: () -> Void

    @State private var shimmerPhase: CGFloat = 0
    @State private var statusAppeared = false

    private var hasExpandableContent: Bool {
        activity.output != nil || !activity.detail.isEmpty
    }

    private func toolCategoryIcon(_ name: String) -> String {
        if name.hasPrefix("run_shell") || name.hasPrefix("run_applescript") { return "terminal" }
        if name.hasPrefix("read_file") || name.hasPrefix("write_file") || name.hasPrefix("list_directory") || name.hasPrefix("file_info") { return "doc.text" }
        if name.hasPrefix("open_url") || name.hasPrefix("navigate") || name.contains("browser") || name.contains("chrome") { return "globe" }
        if name.hasPrefix("send_email") || name.contains("gmail") { return "envelope" }
        if name.hasPrefix("click") || name.hasPrefix("type_text") || name.hasPrefix("press_key") || name.hasPrefix("scroll") { return "cursorarrow.click.2" }
        if name.hasPrefix("take_screenshot") || name.hasPrefix("screenshot") || name.contains("snapshot") { return "camera.viewfinder" }
        if name.hasPrefix("open_app") || name.hasPrefix("activate_app") { return "app" }
        if name.contains("calendar") || name.contains("gcal") { return "calendar" }
        if name.contains("search") { return "magnifyingglass" }
        if name.contains("memory") || name.hasPrefix("save_memory") || name.hasPrefix("recall") { return "brain" }
        if name.contains("schedule") || name.contains("cron") || name.contains("task") { return "clock" }
        if name.hasPrefix("discover_tools") { return "wrench.and.screwdriver.fill" }
        if name.contains("mcp_") { return "puzzlepiece.extension" }
        if name.contains("reservation") || name.contains("noweat") { return "fork.knife" }
        return "gearshape"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 8) {
                statusIcon.frame(width: 16)

                Image(systemName: activity.type == .toolCall ? toolCategoryIcon(activity.label) : activity.icon)
                    .font(.system(size: 10))
                    .foregroundColor(iconColor)
                    .frame(width: 14)

                // Label + detail
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)

                    if !activity.detail.isEmpty && !isOutputExpanded {
                        Text(activity.detail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AppTheme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let ms = activity.durationMs {
                    Text(formatMs(ms))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                } else if !activity.isComplete {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                }

                if hasExpandableContent {
                    Image(systemName: isOutputExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7))
                        .foregroundColor(AppTheme.textMuted)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if hasExpandableContent { onToggleOutput() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(activity.label)\(activity.isComplete ? (activity.success == false ? ", failed" : ", completed") : ", in progress")")
            .accessibilityValue(activity.detail.isEmpty ? "" : activity.detail)
            .accessibilityHint(hasExpandableContent ? "Double tap to toggle details" : "")
            .background(
                ZStack {
                    if isOutputExpanded {
                        AppTheme.bgPrimary.opacity(0.3)
                    }
                    // Subtle shimmer overlay while activity is in progress
                    if !activity.isComplete {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, AppTheme.accent.opacity(0.06), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerPhase)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                    shimmerPhase = 200
                                }
                            }
                            .clipped()
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Expanded detail + output
            if isOutputExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Command detail
                    if !activity.detail.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "terminal")
                                .font(.system(size: 8))
                                .foregroundColor(AppTheme.textMuted)
                            Text(activity.detail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }

                    // Output with clickable paths
                    if let output = activity.output, !output.isEmpty {
                        ClickableOutputView(text: output)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.bgPrimary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if activity.isComplete {
            if let success = activity.success {
                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(success ? AppTheme.success : AppTheme.error)
                    .scaleEffect(statusAppeared ? 1.0 : 0.01)
                    .opacity(statusAppeared ? 1 : 0)
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            statusAppeared = true
                        }
                    }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.success)
                    .scaleEffect(statusAppeared ? 1.0 : 0.01)
                    .opacity(statusAppeared ? 1 : 0)
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            statusAppeared = true
                        }
                    }
            }
        } else {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 8, height: 8)
        }
    }

    private var iconColor: Color {
        switch activity.type {
        case .toolCall: return AppTheme.accent
        case .mcpLoading: return .purple
        case .agentRoute: return .orange
        case .status: return AppTheme.textMuted
        case .thinking: return AppTheme.textMuted
        }
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        if ms < 60000 { return String(format: "%.1fs", Double(ms) / 1000) }
        return "\(ms / 60000)m \((ms % 60000) / 1000)s"
    }
}

// MARK: - Clickable Output (file paths open in Finder, images inline)

struct ClickableOutputView: View {
    let text: String

    var body: some View {
        let segments = parseSegments(text)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let str):
                    Text(str)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                        .lineLimit(8)
                        .textSelection(.enabled)

                case .filePath(let path):
                    Button(action: { openPath(path) }) {
                        HStack(spacing: 4) {
                            Image(systemName: fileIcon(path))
                                .font(.system(size: 9))
                            Text(abbreviatePath(path))
                                .font(.system(size: 10, design: .monospaced))
                                .underline()
                        }
                        .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                case .image(let path):
                    ImagePreviewView(path: path)
                }
            }
        }
    }

    // Parse text into segments: plain text, file paths, images
    private enum Segment {
        case text(String)
        case filePath(String)
        case image(String)
    }

    private func parseSegments(_ text: String) -> [Segment] {
        let lines = text.components(separatedBy: "\n")
        var segments: [Segment] = []
        var plainLines: [String] = []

        for line in lines {
            let paths = extractPaths(from: line)
            if !paths.isEmpty {
                // Flush plain text
                if !plainLines.isEmpty {
                    segments.append(.text(plainLines.joined(separator: "\n")))
                    plainLines = []
                }
                for path in paths {
                    let ext = (path as NSString).pathExtension.lowercased()
                    let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp", "heic"]
                    if imageExts.contains(ext) {
                        segments.append(.image(path))
                    } else {
                        segments.append(.filePath(path))
                    }
                }
            } else {
                plainLines.append(line)
            }
        }

        if !plainLines.isEmpty {
            segments.append(.text(plainLines.joined(separator: "\n")))
        }
        return segments
    }

    private func extractPaths(from line: String) -> [String] {
        // Match absolute paths: /Users/..., /tmp/..., ~/...
        let pattern = "(?:/(?:Users|tmp|var|Applications|System|Library|opt|usr|Volumes)[^\\s,;\"'\\]\\)]*|~[^\\s,;\"'\\]\\)]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap {
            Range($0.range, in: line).map { String(line[$0]) }
        }.filter { path in
            // Only include paths that look like real files (have extension or end without trailing punctuation)
            let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            return FileManager.default.fileExists(atPath: clean) || clean.contains(".")
        }
    }

    private func openPath(_ path: String) {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        let ext = (clean as NSString).pathExtension.lowercased()
        let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "bmp", "heic"]
        if imageExts.contains(ext) {
            NSWorkspace.shared.open(URL(fileURLWithPath: clean))
        } else {
            NSWorkspace.shared.selectFile(clean, inFileViewerRootedAtPath: "")
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func fileIcon(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "pdf": return "doc.richtext"
        case "txt", "md", "log": return "doc.text"
        case "swift", "py", "js", "ts", "json", "xml", "html", "css": return "doc.text.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "mp4", "mov", "avi": return "film"
        case "zip", "gz", "tar": return "archivebox"
        default:
            if (path as NSString).pathExtension.isEmpty { return "folder" }
            return "doc"
        }
    }
}

// MARK: - Image Preview

struct ImagePreviewView: View {
    let path: String
    @State private var loadedImage: NSImage?
    @State private var isLoading = true
    @State private var isHovered = false

    private var filename: String {
        (path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(filename)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                        .lineLimit(1)
                }
                .padding(8)
                .background(AppTheme.bgPrimary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let nsImage = loadedImage {
                VStack(alignment: .leading, spacing: 4) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isHovered ? AppTheme.accent.opacity(0.4) : AppTheme.borderGlass, lineWidth: isHovered ? 1.5 : 0.5)
                        )
                        .shadow(color: .black.opacity(isHovered ? 0.15 : 0), radius: 4, y: 2)
                        .onTapGesture { openInPreview() }
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }

                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                        Text(filename)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AppTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            } else {
                // Failed to load
                Button(action: { openInPreview() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 9))
                        Text(filename)
                            .font(.system(size: 10, design: .monospaced))
                            .underline()
                    }
                    .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            let image = NSImage(contentsOfFile: clean)
            DispatchQueue.main.async {
                loadedImage = image
                isLoading = false
            }
        }
    }

    private func openInPreview() {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        NSWorkspace.shared.open(URL(fileURLWithPath: clean))
    }
}

// MARK: - Response View

struct ResponseView: View {
    let text: String
    let isStreaming: Bool
    @State private var cursorVisible = true

    var body: some View {
        let sections = ResponseParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                if isStreaming && idx == sections.count - 1 {
                    // Last section with blinking cursor appended
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        sectionView(section)
                        if cursorVisible {
                            Text("\u{258C}")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                } else {
                    sectionView(section)
                }
            }
        }
        .onAppear { startCursorTimer() }
        .onChange(of: isStreaming) { streaming in
            if streaming { cursorVisible = true; startCursorTimer() }
        }
    }

    private func startCursorTimer() {
        guard isStreaming else { return }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !isStreaming { timer.invalidate(); return }
            cursorVisible.toggle()
        }
    }

    @ViewBuilder
    private func sectionView(_ section: ResponseSection) -> some View {
        switch section {
        case .paragraph(let text):
            RichTextView(text: text)

        case .heading(let text, let level):
            Text(text)
                .font(.system(
                    size: level == 1 ? 20 : level == 2 ? 17 : 15,
                    weight: level == 1 ? .bold : level == 2 ? .semibold : .medium,
                    design: .rounded
                ))
                .foregroundColor(AppTheme.textPrimary)
                .padding(.top, level == 1 ? 8 : level == 2 ? 6 : 4)

        case .sectionCard(let title, let icon, let color, let items):
            SectionCardView(title: title, icon: icon, accentColor: color, items: items)

        case .stepProgress(let steps):
            StepProgressView(steps: steps)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(AppTheme.accent).frame(width: 5, height: 5).padding(.top, 6)
                        if let attributed = try? AttributedString(markdown: item, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                            Text(attributed).font(.system(size: 14)).foregroundColor(AppTheme.textPrimary).lineSpacing(3)
                        } else {
                            Text(item).font(.system(size: 14)).foregroundColor(AppTheme.textPrimary).lineSpacing(3)
                        }
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 20, height: 20)
                            .background(AppTheme.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        if let attributed = try? AttributedString(markdown: item, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                            Text(attributed).font(.system(size: 14)).foregroundColor(AppTheme.textPrimary).lineSpacing(3)
                        } else {
                            Text(item).font(.system(size: 14)).foregroundColor(AppTheme.textPrimary).lineSpacing(3)
                        }
                    }
                }
            }

        case .codeBlock(let code, let lang):
            CodeBlockView(code: code, language: lang)

        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)

        case .blockquote(let lines):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppTheme.accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        RichTextView(text: line)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.bgCard.opacity(0.4))
            )

        case .divider:
            Rectangle().fill(AppTheme.borderGlass).frame(height: 1).padding(.vertical, 4)
        }
    }
}

// MARK: - Section Card

struct SectionCardView: View {
    let title: String
    let icon: String
    let accentColor: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(accentColor)
                    .frame(width: 24, height: 24)
                    .background(accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(accentColor.opacity(0.6)).frame(width: 4, height: 4).padding(.top, 7)
                    if let attributed = try? AttributedString(markdown: item, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary)
                            .lineSpacing(3).textSelection(.enabled)
                    } else {
                        Text(item)
                            .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary)
                            .lineSpacing(3).textSelection(.enabled)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.bgCard.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.06), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Step Progress

struct StepProgressView: View {
    let steps: [(label: String, done: Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(step.done ? AppTheme.success : AppTheme.accent.opacity(0.3))
                                .frame(width: 12, height: 12)
                            if step.done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        if idx < steps.count - 1 {
                            Rectangle()
                                .fill(step.done ? AppTheme.success.opacity(0.3) : AppTheme.borderGlass)
                                .frame(width: 1.5, height: 22)
                        }
                    }
                    Text(step.label)
                        .font(.system(size: 13))
                        .foregroundColor(step.done ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .padding(.bottom, idx < steps.count - 1 ? 6 : 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.bgCard.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.borderGlass, lineWidth: 0.5))
    }
}

// MARK: - Markdown Table

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                        Text(header)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minWidth: 80, alignment: .leading)
                        if idx < headers.count - 1 {
                            Rectangle()
                                .fill(AppTheme.borderGlass)
                                .frame(width: 0.5)
                        }
                    }
                }
                .background(AppTheme.bgCard.opacity(0.8))

                // Header bottom border
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.3))
                    .frame(height: 1)

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { colIdx in
                            Text(colIdx < row.count ? row[colIdx] : "")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(minWidth: 80, alignment: .leading)
                            if colIdx < headers.count - 1 {
                                Rectangle()
                                    .fill(AppTheme.borderGlass.opacity(0.5))
                                    .frame(width: 0.5)
                            }
                        }
                    }
                    .background(rowIdx % 2 == 0 ? Color.clear : AppTheme.bgCard.opacity(0.3))

                    if rowIdx < rows.count - 1 {
                        Rectangle()
                            .fill(AppTheme.borderGlass.opacity(0.3))
                            .frame(height: 0.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.borderGlass, lineWidth: 0.5))
        }
        .textSelection(.enabled)
    }
}

// MARK: - Code Block

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with language label and copy button
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textMuted)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(copied ? AppTheme.success : AppTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(AppTheme.bgPrimary.opacity(0.9))

            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.bgPrimary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.borderGlass, lineWidth: 0.5))
    }
}

// MARK: - Streaming / Typing

struct StreamingPlaceholder: View {
    let hasActivities: Bool
    var body: some View {
        if hasActivities {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Working...").font(.system(size: 12)).foregroundColor(AppTheme.textMuted)
            }
        } else {
            TypingIndicator()
        }
    }
}

struct TypingIndicator: View {
    @State private var phase: Int = 0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(AppTheme.accent).frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.2 : 0.7)
                    .opacity(phase == i ? 1.0 : 0.35)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.25)) { phase = (phase + 1) % 3 }
            }
        }
    }
}

// MARK: - Tool Call Card

struct ToolCallCard: View {
    let name: String
    let result: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { expanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver").font(.system(size: 11)).foregroundColor(AppTheme.accent)
                    Text(name).font(.system(size: 12, weight: .medium)).foregroundColor(AppTheme.accent)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9)).foregroundColor(AppTheme.textMuted)
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                Text(result).font(.system(size: 12, design: .monospaced)).foregroundColor(AppTheme.textSecondary)
                    .textSelection(.enabled).padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .background(AppTheme.bgPrimary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.accent.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - Response Parser

enum ResponseSection {
    case paragraph(String)
    case heading(String, Int)
    case sectionCard(title: String, icon: String, color: Color, items: [String])
    case stepProgress([(label: String, done: Bool)])
    case bulletList([String])
    case numberedList([String])
    case codeBlock(String, String)
    case table(headers: [String], rows: [[String]])
    case blockquote([String])
    case divider
}

struct ResponseParser {

    // MARK: - Parse

    static func parse(_ text: String) -> [ResponseSection] {
        let lines = text.components(separatedBy: "\n")
        var sections: [ResponseSection] = []
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }

            // Code blocks
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                var foundClose = false
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        foundClose = true
                        break
                    }
                    code.append(lines[i]); i += 1
                }
                sections.append(.codeBlock(code.joined(separator: "\n"), lang))
                if foundClose { i += 1 }
                continue
            }

            // Table
            if isTableRow(trimmed) {
                var tableLines: [String] = []
                while i < lines.count {
                    let tl = lines[i].trimmingCharacters(in: .whitespaces)
                    if isTableRow(tl) {
                        tableLines.append(tl)
                        i += 1
                    } else {
                        break
                    }
                }
                if tableLines.count >= 2 {
                    let headerCells = parseTableRow(tableLines[0])
                    // Skip separator row (|---|---|)
                    let startRow = isTableSeparator(tableLines.count > 1 ? tableLines[1] : "") ? 2 : 1
                    var dataRows: [[String]] = []
                    for r in startRow..<tableLines.count {
                        dataRows.append(parseTableRow(tableLines[r]))
                    }
                    sections.append(.table(headers: headerCells, rows: dataRows))
                } else if tableLines.count == 1 {
                    // Single table line, treat as paragraph
                    sections.append(.paragraph(tableLines[0]))
                }
                continue
            }

            // Divider
            if trimmed.hasPrefix("---") || trimmed.hasPrefix("===") || trimmed.hasPrefix("___") {
                sections.append(.divider); i += 1; continue
            }

            // Blockquotes
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                        i += 1
                    } else if ql == ">" {
                        quoteLines.append("")
                        i += 1
                    } else {
                        break
                    }
                }
                if !quoteLines.isEmpty { sections.append(.blockquote(quoteLines)) }
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") { sections.append(.heading(String(trimmed.dropFirst(4)), 3)); i += 1; continue }
            if trimmed.hasPrefix("## ") { sections.append(.heading(String(trimmed.dropFirst(3)), 2)); i += 1; continue }
            if trimmed.hasPrefix("# ") { sections.append(.heading(String(trimmed.dropFirst(2)), 1)); i += 1; continue }

            // Emoji section header
            if let sectionResult = tryParseSectionCard(lines: lines, startIndex: i) {
                sections.append(sectionResult.section)
                i = sectionResult.nextIndex
                continue
            }

            // Step sequence
            if isStepLine(trimmed) {
                var steps: [(label: String, done: Bool)] = []
                while i < lines.count {
                    let sl = lines[i].trimmingCharacters(in: .whitespaces)
                    if sl.isEmpty { i += 1; continue }
                    if isStepLine(sl) || isCompletionLine(sl) {
                        steps.append((label: sl, done: isCompletionLine(sl)))
                        i += 1
                    } else { break }
                }
                if !steps.isEmpty { sections.append(.stepProgress(steps)) }
                continue
            }

            // Plan block
            if trimmed.contains("Plan:") || trimmed.contains("Plan:**") {
                var items: [String] = []
                i += 1
                while i < lines.count {
                    let pl = lines[i].trimmingCharacters(in: .whitespaces)
                    if pl.isEmpty { i += 1; continue }
                    if let fc = pl.first, fc.isNumber, pl.contains(". ") {
                        items.append(String(pl.drop(while: { $0 != "." }).dropFirst(1)).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else { break }
                }
                if !items.isEmpty {
                    sections.append(.sectionCard(title: "Plan", icon: "list.clipboard", color: AppTheme.accent, items: items))
                }
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                var items: [String] = []
                while i < lines.count {
                    let bl = lines[i].trimmingCharacters(in: .whitespaces)
                    if bl.hasPrefix("- ") || bl.hasPrefix("* ") || bl.hasPrefix("• ") {
                        items.append(String(bl.dropFirst(2)))
                        i += 1
                    } else { break }
                }
                sections.append(.bulletList(items))
                continue
            }

            // Numbered list
            if let fc = trimmed.first, fc.isNumber, trimmed.contains(". ") {
                var items: [String] = []
                while i < lines.count {
                    let nl = lines[i].trimmingCharacters(in: .whitespaces)
                    if let fc2 = nl.first, fc2.isNumber, nl.contains(". ") {
                        items.append(String(nl.drop(while: { $0 != "." }).dropFirst(1)).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else { break }
                }
                if !items.isEmpty { sections.append(.numberedList(items)) }
                continue
            }

            // Paragraph
            var para: [String] = []
            while i < lines.count {
                let pl = lines[i].trimmingCharacters(in: .whitespaces)
                if pl.isEmpty || pl.hasPrefix("#") || pl.hasPrefix("```") || pl.hasPrefix("---") ||
                   pl.hasPrefix("- ") || pl.hasPrefix("* ") || pl.hasPrefix("• ") ||
                   pl.hasPrefix("> ") || pl == ">" ||
                   isStepLine(pl) || pl.contains("Plan:") || isSectionHeader(pl) || isTableRow(pl) {
                    break
                }
                para.append(pl)
                i += 1
            }
            if !para.isEmpty {
                let text = para.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { sections.append(.paragraph(text)) }
            }
        }

        return sections
    }

    // MARK: - Section Card Detection

    private static func tryParseSectionCard(lines: [String], startIndex: Int) -> (section: ResponseSection, nextIndex: Int)? {
        let trimmed = lines[startIndex].trimmingCharacters(in: .whitespaces)
        guard isSectionHeader(trimmed) else { return nil }

        let title = extractSectionTitle(trimmed)
        let (icon, color) = sectionIconAndColor(trimmed)

        var items: [String] = []
        var i = startIndex + 1
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { i += 1; continue }
            if line.hasPrefix("• ") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                items.append(String(line.dropFirst(2)))
                i += 1
            } else if isSectionHeader(line) || line.hasPrefix("#") || line.hasPrefix("```") {
                break
            } else {
                items.append(line)
                i += 1
            }
        }

        if items.isEmpty { return nil }
        return (.sectionCard(title: title, icon: icon, color: color, items: items), i)
    }

    static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let first = trimmed.unicodeScalars.first!.value
        let isEmoji = (first >= 0x1F300 && first <= 0x1FAFF) ||
                      (first >= 0x2600 && first <= 0x27BF) ||
                      (first >= 0x2700 && first <= 0x27BF)
        guard isEmoji else { return false }
        let stripped = trimmed.trimmingCharacters(in: .whitespaces)
        return stripped.hasSuffix(":") || stripped.hasSuffix(":**")
    }

    private static func extractSectionTitle(_ line: String) -> String {
        var result = stripEmojis(line).trimmingCharacters(in: .whitespaces)
        if result.hasSuffix(":**") { result = String(result.dropLast(3)) }
        else if result.hasSuffix(":") { result = String(result.dropLast()) }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func sectionIconAndColor(_ line: String) -> (String, Color) {
        if line.contains("🏛") || line.contains("🗳") { return ("building.columns", Color(red: 0.8, green: 0.4, blue: 0.4)) }
        if line.contains("🌍") || line.contains("🌎") || line.contains("🌏") || line.contains("🗺") { return ("globe", Color(red: 0.3, green: 0.6, blue: 0.9)) }
        if line.contains("🧪") || line.contains("💻") || line.contains("🔬") { return ("flask", Color(red: 0.5, green: 0.8, blue: 0.5)) }
        if line.contains("🎬") || line.contains("🎭") || line.contains("🎨") || line.contains("🎵") { return ("film", Color(red: 0.9, green: 0.6, blue: 0.3)) }
        if line.contains("💰") || line.contains("📈") || line.contains("💹") { return ("chart.line.uptrend.xyaxis", Color(red: 0.3, green: 0.8, blue: 0.5)) }
        if line.contains("⚽") || line.contains("🏀") || line.contains("🏈") { return ("sportscourt", Color(red: 0.3, green: 0.7, blue: 0.3)) }
        if line.contains("🏥") || line.contains("💊") || line.contains("🩺") { return ("heart", Color(red: 0.9, green: 0.3, blue: 0.3)) }
        if line.contains("📋") || line.contains("📝") { return ("doc.text", AppTheme.accent) }
        if line.contains("📰") || line.contains("🗞") { return ("newspaper", Color(red: 0.6, green: 0.6, blue: 0.8)) }
        if line.contains("🔒") || line.contains("🛡") { return ("lock.shield", Color(red: 0.5, green: 0.5, blue: 0.8)) }
        return ("sparkles", AppTheme.accent)
    }

    // MARK: - Helpers

    private static func isStepLine(_ line: String) -> Bool {
        line.contains("**Paso") || line.contains("**Step") || (line.contains("Paso ") && line.contains(":"))
    }

    private static func isCompletionLine(_ line: String) -> Bool {
        line.hasPrefix("✅") || line.contains("Listo:") || line.contains("¡Listo")
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.filter({ $0 == "|" }).count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        let inner = trimmed.replacingOccurrences(of: "|", with: "")
                          .replacingOccurrences(of: "-", with: "")
                          .replacingOccurrences(of: ":", with: "")
                          .trimmingCharacters(in: .whitespaces)
        return inner.isEmpty
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func stripEmojis(_ text: String) -> String {
        text.unicodeScalars.filter { s in
            !(s.value >= 0x1F300 && s.value <= 0x1FAFF) &&
            !(s.value >= 0x2600 && s.value <= 0x27BF) &&
            !(s.value >= 0xFE00 && s.value <= 0xFE0F) &&
            s.value != 0x200D
        }.map { String($0) }.joined()
    }
}

// MARK: - Rich Text View (markdown + clickable paths + inline code highlighting)

struct RichTextView: View {
    let text: String

    var body: some View {
        let parts = splitByPaths(text)
        // Use a FlowLayout-like approach: if there are paths, render mixed
        if parts.count == 1, case .plain(let str) = parts[0] {
            // Simple text — render with inline code highlighting
            inlineMarkdownText(str)
        } else {
            // Has paths — render inline
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .plain(let str):
                        inlineMarkdownText(str)
                    case .path(let path):
                        Button(action: {
                            let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
                            NSWorkspace.shared.selectFile(clean, inFileViewerRootedAtPath: "")
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc").font(.system(size: 10))
                                Text(abbreviate(path))
                                    .font(.system(size: 13, design: .monospaced))
                                    .underline()
                            }
                            .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                }
            }
        }
    }

    /// Renders text with AttributedString markdown and highlights inline code with a background
    @ViewBuilder
    private func inlineMarkdownText(_ str: String) -> some View {
        if str.contains("`") {
            // Split on inline code to render code spans with background
            let segments = parseInlineCode(str)
            let combined = segments.reduce(AttributedString()) { result, segment in
                var combined = result
                switch segment {
                case .text(let t):
                    if var attr = try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        attr.font = .system(size: 14)
                        Self.styleLinks(&attr)
                        combined.append(attr)
                    } else {
                        var attr = AttributedString(t)
                        attr.font = .system(size: 14)
                        attr.foregroundColor = AppTheme.textPrimary
                        combined.append(attr)
                    }
                case .code(let c):
                    var space = AttributedString("\u{200A}")
                    space.font = .system(size: 2)
                    combined.append(space)
                    var attr = AttributedString(c)
                    attr.font = .system(size: 12.5, design: .monospaced)
                    attr.foregroundColor = AppTheme.accent
                    attr.backgroundColor = AppTheme.bgCard
                    combined.append(attr)
                    combined.append(space)
                }
                return combined
            }
            Text(combined)
                .lineSpacing(4).textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    NSWorkspace.shared.open(url)
                    return .handled
                })
        } else {
            if var attributed = try? AttributedString(markdown: str, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let _ = Self.styleLinks(&attributed)
                Text(attributed)
                    .font(.system(size: 14)).foregroundColor(AppTheme.textPrimary)
                    .lineSpacing(4).textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
            } else {
                Text(str)
                    .font(.system(size: 14)).foregroundColor(AppTheme.textPrimary)
                    .lineSpacing(4).textSelection(.enabled)
            }
        }
    }

    /// Styles link runs in an AttributedString to be blue and underlined
    private static func styleLinks(_ attr: inout AttributedString) {
        for run in attr.runs {
            if attr[run.range].link != nil {
                attr[run.range].foregroundColor = Color(red: 0.3, green: 0.55, blue: 1.0)
                attr[run.range].underlineStyle = .single
            }
        }
    }

    private enum InlineSegment {
        case text(String)
        case code(String)
    }

    /// Splits text into alternating text and inline code segments
    private func parseInlineCode(_ text: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var current = ""
        var inCode = false
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]
            if ch == "`" {
                if inCode {
                    // End of code span
                    if !current.isEmpty { segments.append(.code(current)) }
                    current = ""
                    inCode = false
                } else {
                    // Start of code span
                    if !current.isEmpty { segments.append(.text(current)) }
                    current = ""
                    inCode = true
                }
            } else {
                current.append(ch)
            }
            i = text.index(after: i)
        }

        // Flush remaining
        if !current.isEmpty {
            if inCode {
                // Unclosed backtick during streaming — render as text with the backtick
                segments.append(.text("`" + current))
            } else {
                segments.append(.text(current))
            }
        }

        return segments
    }

    private enum TextPart {
        case plain(String)
        case path(String)
    }

    private func splitByPaths(_ text: String) -> [TextPart] {
        let pattern = "(?:/(?:Users|tmp|var|Applications|System|Library|opt|usr|Volumes)[^\\s,;\"'\\]\\)]*|~/[^\\s,;\"'\\]\\)]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.plain(text)] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)

        if matches.isEmpty { return [.plain(text)] }

        var parts: [TextPart] = []
        var lastEnd = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastEnd {
                let before = nsText.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
                let trimmed = before.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { parts.append(.plain(trimmed)) }
            }
            let path = nsText.substring(with: matchRange)
            parts.append(.path(path))
            lastEnd = matchRange.location + matchRange.length
        }

        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
            if !remaining.isEmpty { parts.append(.plain(remaining)) }
        }

        return parts
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Agent Badge

struct AgentBadge: View {
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            GhostIcon(size: 12, animate: false, tint: agentColor(name))
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(agentColor(name))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(agentColor(name).opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(agentColor(name).opacity(0.2), lineWidth: 0.5))
    }
}
