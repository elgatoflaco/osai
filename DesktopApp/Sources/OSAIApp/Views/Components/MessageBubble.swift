import SwiftUI
import AppKit
import Quartz

// MARK: - Zen Mode Environment Key

private struct ZenModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var zenMode: Bool {
        get { self[ZenModeKey.self] }
        set { self[ZenModeKey.self] = newValue }
    }
}

// MARK: - Image Path Detection

private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"]

/// Extracts image file paths from message text.
/// Matches absolute paths (/path/to/image.png) and file:// URLs.
private func extractImagePaths(from text: String) -> [String] {
    var paths: [String] = []
    // Match file:///... URLs ending with image extension
    let fileURLPattern = #"file:///[^\s\"\]\)>]+"#
    // Match absolute paths like /Users/.../screenshot.png
    let absPathPattern = #"(?<!\w)/(?:Users|tmp|var|private)[^\s\"\]\)>]*\.(?:png|jpg|jpeg|gif|webp|bmp|tiff|heic)"#
    for pattern in [fileURLPattern, absPathPattern] {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) {
                    var path = String(text[r])
                    if path.hasPrefix("file://") {
                        path = path.replacingOccurrences(of: "file://", with: "")
                    }
                    // Remove URL-encoded characters
                    if let decoded = path.removingPercentEncoding {
                        path = decoded
                    }
                    let ext = (path as NSString).pathExtension.lowercased()
                    if imageExtensions.contains(ext) && !paths.contains(path) {
                        paths.append(path)
                    }
                }
            }
        }
    }
    return paths
}

// MARK: - Markdown Image Extraction

/// Represents an image reference found in message content.
enum InlineImageRef: Identifiable, Hashable {
    case local(path: String)
    case remote(url: URL, alt: String)

    var id: String {
        switch self {
        case .local(let path): return "local:\(path)"
        case .remote(let url, _): return "remote:\(url.absoluteString)"
        }
    }
}

/// Extracts all inline image references from message text:
/// - Markdown syntax: ![alt](url)
/// - Raw image URLs: https://...image.png
/// - Local paths (via extractImagePaths)
private func extractAllImageRefs(from text: String) -> [InlineImageRef] {
    var refs: [InlineImageRef] = []
    var seenIds = Set<String>()

    // 1. Markdown image syntax: ![alt](url)
    let mdPattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
    if let mdRegex = try? NSRegularExpression(pattern: mdPattern, options: []) {
        let range = NSRange(text.startIndex..., in: text)
        for match in mdRegex.matches(in: text, range: range) {
            if let altRange = Range(match.range(at: 1), in: text),
               let urlRange = Range(match.range(at: 2), in: text) {
                let alt = String(text[altRange])
                let urlStr = String(text[urlRange])
                // Could be a local path or remote URL
                if urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") {
                    if let url = URL(string: urlStr) {
                        let ref = InlineImageRef.remote(url: url, alt: alt)
                        if !seenIds.contains(ref.id) {
                            seenIds.insert(ref.id)
                            refs.append(ref)
                        }
                    }
                } else {
                    // Treat as local path
                    var path = urlStr
                    if path.hasPrefix("~") {
                        path = (path as NSString).expandingTildeInPath
                    }
                    let ref = InlineImageRef.local(path: path)
                    if !seenIds.contains(ref.id) {
                        seenIds.insert(ref.id)
                        refs.append(ref)
                    }
                }
            }
        }
    }

    // 2. Raw image URLs (not already captured by markdown syntax)
    let rawURLPattern = #"(?<!\()https?://[^\s\"\]\)>',]+\.(?:png|jpg|jpeg|gif|webp)(?:\?[^\s\"\]\)>',]*)?"#
    if let rawRegex = try? NSRegularExpression(pattern: rawURLPattern, options: [.caseInsensitive]) {
        let range = NSRange(text.startIndex..., in: text)
        for match in rawRegex.matches(in: text, range: range) {
            if let r = Range(match.range, in: text) {
                var raw = String(text[r])
                while raw.last == "." || raw.last == "," || raw.last == ";" || raw.last == ":" {
                    raw = String(raw.dropLast())
                }
                if let url = URL(string: raw) {
                    let ref = InlineImageRef.remote(url: url, alt: "")
                    if !seenIds.contains(ref.id) {
                        seenIds.insert(ref.id)
                        refs.append(ref)
                    }
                }
            }
        }
    }

    // 3. Local file paths
    for path in extractImagePaths(from: text) {
        let ref = InlineImageRef.local(path: path)
        if !seenIds.contains(ref.id) {
            seenIds.insert(ref.id)
            refs.append(ref)
        }
    }

    return refs
}

// MARK: - URL Detection for Link Previews

/// Extracts unique http/https URLs from message text, skipping URLs inside code blocks
/// and URLs that point to image files (those are handled by inline image rendering).
private func extractPreviewURLs(from text: String) -> [URL] {
    // Strip code blocks first so we don't detect URLs inside them
    let codeBlockPattern = #"```[\s\S]*?```"#
    var strippedText = text
    if let codeRegex = try? NSRegularExpression(pattern: codeBlockPattern, options: [.dotMatchesLineSeparators]) {
        strippedText = codeRegex.stringByReplacingMatches(
            in: strippedText,
            range: NSRange(strippedText.startIndex..., in: strippedText),
            withTemplate: ""
        )
    }
    // Also strip inline code
    let inlineCodePattern = #"`[^`]+`"#
    if let inlineRegex = try? NSRegularExpression(pattern: inlineCodePattern, options: []) {
        strippedText = inlineRegex.stringByReplacingMatches(
            in: strippedText,
            range: NSRange(strippedText.startIndex..., in: strippedText),
            withTemplate: ""
        )
    }
    // Strip markdown image syntax so image URLs don't appear as link previews
    let mdImagePattern = #"!\[[^\]]*\]\([^)]+\)"#
    if let mdImageRegex = try? NSRegularExpression(pattern: mdImagePattern, options: []) {
        strippedText = mdImageRegex.stringByReplacingMatches(
            in: strippedText,
            range: NSRange(strippedText.startIndex..., in: strippedText),
            withTemplate: ""
        )
    }

    let urlPattern = #"https?://[^\s\"\]\)>',]+"#
    guard let regex = try? NSRegularExpression(pattern: urlPattern, options: []) else { return [] }
    let range = NSRange(strippedText.startIndex..., in: strippedText)

    var seen = Set<String>()
    var urls: [URL] = []
    for match in regex.matches(in: strippedText, range: range) {
        if let r = Range(match.range, in: strippedText) {
            var raw = String(strippedText[r])
            // Trim trailing punctuation that got captured
            while raw.last == "." || raw.last == "," || raw.last == ";" || raw.last == ":" {
                raw = String(raw.dropLast())
            }
            // Skip image URLs
            let ext = (raw as NSString).pathExtension.lowercased()
            if imageExtensions.contains(ext) { continue }
            guard !seen.contains(raw), let url = URL(string: raw) else { continue }
            seen.insert(raw)
            urls.append(url)
        }
    }
    return urls
}

// MARK: - Code Block Extraction

/// Extracts fenced code blocks from markdown text, returning the code content of each block.
private func extractCodeBlocks(from text: String) -> [String] {
    let pattern = #"```(?:\w*)\n?([\s\S]*?)```"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    return regex.matches(in: text, range: range).compactMap { match in
        guard match.range(at: 1).location != NSNotFound else { return nil }
        let code = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }
}

/// Extracts the first http/https URL found in message text (including inside code blocks).
private func extractFirstURL(from text: String) -> String? {
    let pattern = #"https?://[^\s\"\]\)>',]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let r = Range(match.range, in: text) else { return nil }
    var raw = String(text[r])
    while raw.last == "." || raw.last == "," || raw.last == ";" || raw.last == ":" {
        raw = String(raw.dropLast())
    }
    return raw
}

// MARK: - Link Preview Card

struct LinkPreviewCard: View {
    let url: URL
    @State private var isHovered = false

    private var host: String {
        url.host ?? url.absoluteString
    }

    private var icon: String {
        let h = host.lowercased()
        if h.contains("github.com") { return "chevron.left.forwardslash.chevron.right" }
        if h.contains("stackoverflow.com") { return "text.bubble" }
        if h.contains("youtube.com") || h.contains("youtu.be") { return "play.rectangle" }
        if h.contains("twitter.com") || h.contains("x.com") { return "at" }
        return "globe"
    }

    private var iconColor: Color {
        let hash = abs(host.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }

    var body: some View {
        Button(action: {
            NSWorkspace.shared.open(url)
        }) {
            HStack(spacing: 10) {
                // Favicon placeholder
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 30, height: 30)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(host)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textMuted.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 350)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.bgCard.opacity(isHovered ? 0.9 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovered ? iconColor.opacity(0.3) : AppTheme.borderGlass,
                        lineWidth: isHovered ? 1.0 : 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityLabel("Open link: \(host)")
    }
}

// MARK: - Link Previews Stack

struct LinkPreviewsStack: View {
    let urls: [URL]
    private let maxVisible = 5

    var body: some View {
        let visible = Array(urls.prefix(maxVisible))
        let overflow = urls.count - maxVisible

        VStack(alignment: .leading, spacing: 6) {
            ForEach(visible, id: \.absoluteString) { url in
                LinkPreviewCard(url: url)
            }
            if overflow > 0 {
                Text("+\(overflow) more link\(overflow == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.leading, 4)
            }
        }
    }
}

// MARK: - Quick Look Coordinator

final class QLCoordinator: NSObject, QLPreviewPanelDataSource {
    var url: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return url != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        return url as? QLPreviewItem
    }
}

// MARK: - Image Overlay Controls (shared)

private struct ImageOverlayControls: View {
    @Binding var zoomScale: CGFloat
    @Binding var showFullSize: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Button(action: { zoomScale = max(0.5, zoomScale - 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.8))

                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    Button(action: { zoomScale = min(5.0, zoomScale + 0.25) }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.8))

                    Divider().frame(height: 16)

                    Button(action: { showFullSize = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
            }
            Spacer()
        }
    }
}

// MARK: - Expand Button Overlay

private struct ExpandButtonOverlay: View {
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        if isHovered {
            Button(action: action) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .padding(6)
        }
    }
}

// MARK: - Inline Image View (local files)

struct InlineImageView: View {
    let path: String
    @State private var nsImage: NSImage?
    @State private var showFullSize = false
    @State private var loadFailed = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var isHovered = false

    private static let qlCoordinator = QLCoordinator()

    var body: some View {
        Group {
            if let nsImage = nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.borderGlass, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .overlay(alignment: .topTrailing) {
                        ExpandButtonOverlay(isHovered: isHovered) {
                            showFullSize = true
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                    }
                    .onTapGesture {
                        showFullSize = true
                    }
                    .gesture(TapGesture(count: 2).onEnded {
                        openQuickLook()
                    })
                    .help("Click to enlarge. Double-click for Quick Look.")
            } else if loadFailed {
                // Placeholder for missing image
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textMuted)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.bgCard.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                )
            }
        }
        .onAppear { loadImage() }
        .sheet(isPresented: $showFullSize) {
            imageOverlay
        }
    }

    private func loadImage() {
        var resolvedPath = path
        if resolvedPath.hasPrefix("~") {
            resolvedPath = (resolvedPath as NSString).expandingTildeInPath
        }
        let url = URL(fileURLWithPath: resolvedPath)
        if let img = NSImage(contentsOf: url) {
            nsImage = img
        } else {
            loadFailed = true
        }
    }

    private func openQuickLook() {
        var resolvedPath = path
        if resolvedPath.hasPrefix("~") {
            resolvedPath = (resolvedPath as NSString).expandingTildeInPath
        }
        let url = URL(fileURLWithPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: resolvedPath) else { return }
        Self.qlCoordinator.url = url
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = Self.qlCoordinator
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    @ViewBuilder
    private var imageOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            if let nsImage = nsImage {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .frame(
                            minWidth: 200, maxWidth: .infinity,
                            minHeight: 200, maxHeight: .infinity
                        )
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = max(0.5, min(5.0, value))
                        }
                )
            }

            ImageOverlayControls(zoomScale: $zoomScale, showFullSize: $showFullSize)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Remote Inline Image View (AsyncImage)

struct RemoteInlineImageView: View {
    let url: URL
    let alt: String
    @State private var showFullSize = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var isHovered = false
    @State private var loadedImage: NSImage?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                // Loading placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.bgSecondary)
                    .frame(width: 200, height: 140)
                    .overlay(
                        ProgressView()
                            .controlSize(.small)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                    )

            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.borderGlass, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .overlay(alignment: .topTrailing) {
                        ExpandButtonOverlay(isHovered: isHovered) {
                            showFullSize = true
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                    }
                    .onTapGesture {
                        showFullSize = true
                    }
                    .help(alt.isEmpty ? "Click to enlarge" : alt)
                    .onAppear {
                        // Cache the NSImage for the full-size overlay
                        loadRemoteImage()
                    }

            case .failure:
                // Error state
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Failed to load image")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textMuted)
                        Text(url.lastPathComponent)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Button(action: {
                        // Open in browser as fallback
                        NSWorkspace.shared.open(url)
                    }) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 300)
                .background(AppTheme.bgCard.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                )

            @unknown default:
                EmptyView()
            }
        }
        .sheet(isPresented: $showFullSize) {
            remoteImageOverlay
        }
    }

    private func loadRemoteImage() {
        guard loadedImage == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: url),
               let img = NSImage(data: data) {
                DispatchQueue.main.async {
                    loadedImage = img
                }
            }
        }
    }

    @ViewBuilder
    private var remoteImageOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            if let nsImage = loadedImage {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .frame(
                            minWidth: 200, maxWidth: .infinity,
                            minHeight: 200, maxHeight: .infinity
                        )
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = max(0.5, min(5.0, value))
                        }
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .foregroundColor(.white)
            }

            ImageOverlayControls(zoomScale: $zoomScale, showFullSize: $showFullSize)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Inline Images Stack

struct InlineImagesStack: View {
    let refs: [InlineImageRef]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(refs) { ref in
                switch ref {
                case .local(let path):
                    InlineImageView(path: path)
                case .remote(let url, let alt):
                    RemoteInlineImageView(url: url, alt: alt)
                }
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    @EnvironmentObject var appState: AppState
    let message: ChatMessage
    var isLastAssistantMessage: Bool = false
    var zenMode: Bool = false
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    var onReaction: ((MessageReaction?) -> Void)?
    var onBranch: (() -> Void)?
    var onEdit: ((String) -> Void)?
    var onRestoreEdit: ((String) -> Void)?
    var onBookmark: (() -> Void)?
    var onReply: (() -> Void)?
    /// The quoted message content and role, looked up by the parent from replyToMessageId
    var quotedMessageContent: String?
    var quotedMessageRole: MessageRole?
    var onScrollToMessage: ((String) -> Void)?
    var shareMode: Bool = false
    var isSelectedForShare: Bool = false
    var onToggleShareSelection: (() -> Void)?
    var showAvatar: Bool = true
    var showTimestamp: Bool = true
    @State private var appeared = false
    @State private var copied = false
    @State private var isHovered = false
    @State private var copyToastText: String?
    @State private var copyToastOpacity: Double = 0
    @State private var reactionBounce: MessageReaction?
    @State private var showReactionPicker = false
    @State private var reactionAppeared = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var speakerPulse = false
    /// Per-message raw markdown override: nil follows global, true/false overrides
    @State private var localRawMode: Bool?
    @State private var showEditHistory = false
    /// Pulse animation state for streaming border glow
    @State private var streamingPulse = false

    /// Whether raw markdown is active for this message
    private var isRawMode: Bool {
        localRawMode ?? appState.showRawMarkdown
    }

    /// Whether this message is currently being spoken
    private var isSpeakingThis: Bool {
        appState.isSpeaking && appState.speakingMessageId == message.id
    }

    /// Whether another message is being spoken (not this one)
    private var isSpeakingOther: Bool {
        appState.isSpeaking && appState.speakingMessageId != message.id
    }

    /// Font size adjustment based on display density
    private var densityFontSize: CGFloat {
        switch appState.displayDensity {
        case "compact": return -1
        case "spacious": return 1
        default: return 0
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: appState.messageSpacing + 2) {
            // Share mode checkbox
            if shareMode {
                Button(action: { onToggleShareSelection?() }) {
                    Image(systemName: isSelectedForShare ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isSelectedForShare ? AppTheme.accent : AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .transition(.scale.combined(with: .opacity))
            }

            if message.role == .user {
                Spacer(minLength: 60)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 20)
            }
        }
        .environment(\.zenMode, zenMode)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .contextMenu { messageContextMenu }
        .overlay(alignment: .top) {
            if copyToastText != nil {
                Text(copyToastText ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent.opacity(0.9))
                    .clipShape(Capsule())
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 6, y: 2)
                    .opacity(copyToastOpacity)
                    .allowsHitTesting(false)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var messageContextMenu: some View {
        if !message.content.isEmpty && !message.isStreaming {
            Button(action: {
                copyToClipboard(message.content, label: "Message")
            }) {
                Label("Copy Message", systemImage: "doc.on.doc")
            }

            let codeBlocks = extractCodeBlocks(from: message.content)
            if codeBlocks.count == 1 {
                Button(action: {
                    copyToClipboard(codeBlocks[0], label: "Code")
                }) {
                    Label("Copy Code Block", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } else if codeBlocks.count > 1 {
                Menu {
                    ForEach(Array(codeBlocks.enumerated()), id: \.offset) { index, code in
                        let preview = String(code.prefix(40)).replacingOccurrences(of: "\n", with: " ")
                        Button(action: {
                            copyToClipboard(code, label: "Code block \(index + 1)")
                        }) {
                            Label("Block \(index + 1): \(preview)\(code.count > 40 ? "..." : "")", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                } label: {
                    Label("Copy Code Block", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Button(action: {
                copyToClipboard(message.content, label: "Markdown")
            }) {
                Label("Copy as Markdown", systemImage: "doc.richtext")
            }

            if let url = extractFirstURL(from: message.content) {
                Button(action: {
                    copyToClipboard(url, label: "Link")
                }) {
                    Label("Copy Link", systemImage: "link")
                }
            }

            Divider()

            Button(action: copyAsRichText) {
                Label("Copy as Rich Text", systemImage: "doc.text.fill")
            }

            Button(action: copyAsPlainText) {
                Label("Copy as Plain Text", systemImage: "doc.plaintext")
            }

            Divider()

            Button(action: shareMessage) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Sharing & Copy Actions

    private func copyToClipboard(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        showCopyToast("Copied!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private func showCopyToast(_ text: String) {
        copyToastText = text
        withAnimation(.easeIn(duration: 0.2)) {
            copyToastOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                copyToastOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyToastText = nil
        }
    }

    private func shareMessage() {
        let label = message.role == .user ? "You:" : "Assistant:"
        let body = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = "\(label)\n\(body)\n\n\u{2014} Shared from OSAI"
        showSharingPicker(items: [text])
    }

    private func copyAsMarkdown() {
        copyToClipboard(message.content, label: "Markdown")
    }

    private func copyAsRichText() {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let attrString = buildRichText(from: content, role: message.role)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let rtfData = attrString.rtf(from: NSRange(location: 0, length: attrString.length), documentAttributes: [:]) {
            pb.setData(rtfData, forType: .rtf)
        }
        pb.setString(attrString.string, forType: .string)
        copied = true
        showCopyToast("Copied!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private func copyAsPlainText() {
        let stripped = stripMarkdownFormatting(message.content)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(stripped, forType: .string)
        copied = true
        showCopyToast("Copied!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private func showSharingPicker(items: [Any]) {
        guard let window = NSApp.keyWindow else { return }
        let picker = NSSharingServicePicker(items: items)
        // Position picker relative to the key window's content view
        if let contentView = window.contentView {
            let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }

    private func buildRichText(from content: String, role: MessageRole) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let label = role == .user ? "You:" : "Assistant:"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ]
        result.append(NSAttributedString(string: "\(label)\n", attributes: labelAttrs))

        let bodyFont = NSFont.systemFont(ofSize: 13)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor
        ]

        let pattern = #"\*\*(.+?)\*\*|`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            result.append(NSAttributedString(string: content, attributes: bodyAttrs))
            return result
        }

        let nsContent = content as NSString
        var lastEnd = 0
        for match in regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length)) {
            if match.range.location > lastEnd {
                let plain = nsContent.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                result.append(NSAttributedString(string: plain, attributes: bodyAttrs))
            }
            if match.range(at: 1).location != NSNotFound {
                let boldAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
                result.append(NSAttributedString(string: nsContent.substring(with: match.range(at: 1)), attributes: boldAttrs))
            } else if match.range(at: 2).location != NSNotFound {
                let codeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .backgroundColor: NSColor.quaternaryLabelColor
                ]
                result.append(NSAttributedString(string: nsContent.substring(with: match.range(at: 2)), attributes: codeAttrs))
            }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < nsContent.length {
            result.append(NSAttributedString(string: nsContent.substring(from: lastEnd), attributes: bodyAttrs))
        }

        return result
    }

    private func stripMarkdownFormatting(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"```[\w]*\n?"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        return result
    }

    private var userBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 3) {
                if isEditing {
                    editingView
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        if message.replyToMessageId != nil {
                            quoteBar
                        }

                        Text(message.content)
                            .font(.system(size: zenMode ? 15 : 14 + densityFontSize))
                            .foregroundColor(AppTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, appState.messagePadding + 4)
                    .padding(.vertical, zenMode ? 14 : appState.messagePadding)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.accent.opacity(0.2), lineWidth: 0.5))
                    .overlay(alignment: .bottomLeading) {
                        if let reaction = message.reaction {
                            reactionBadge(reaction)
                                .offset(x: -4, y: 8)
                        }
                    }
                }

                if !isEditing {
                    userBubbleActions
                }
            }

            if showAvatar {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: appState.avatarSize))
                    .foregroundColor(AppTheme.textSecondary)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: appState.avatarSize, height: appState.avatarSize)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You said: \(message.content)")
        .accessibilityValue("at \(timeString(message.timestamp))")
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("Editing...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textMuted)

            TextEditor(text: $editText)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 60, maxHeight: 200)
                .background(AppTheme.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: AppTheme.accent.opacity(0.15), radius: 6, y: 0)

            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
                }) {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.bgCard.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button(action: {
                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
                    onEdit?(trimmed)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11))
                        Text("Save & Resend")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quote / Reply-To Bar

    @ViewBuilder
    private var quoteBar: some View {
        if let replyId = message.replyToMessageId,
           let content = quotedMessageContent {
            Button(action: {
                onScrollToMessage?(replyId)
            }) {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.accent)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: quotedMessageRole == .user ? "person.circle.fill" : "bubble.left.fill")
                                .font(.system(size: 9))
                                .foregroundColor(AppTheme.accent)
                            Text(quotedMessageRole == .user ? "You" : "Assistant")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                        }

                        Text(content)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.accent.opacity(0.15), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Replying to \(quotedMessageRole == .user ? "your" : "assistant") message")
        }
    }

    // MARK: - Reply Action Button

    private var replyActionButton: some View {
        Group {
            if let onReply = onReply {
                Button(action: onReply) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 9))
                        Text("Reply")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppTheme.bgCard.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Reply to this message")
            }
        }
    }

    // MARK: - User Bubble Actions

    private var bookmarkButton: some View {
        Group {
            if isHovered || message.isBookmarked {
                Button(action: { onBookmark?() }) {
                    Image(systemName: message.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 10))
                        .foregroundColor(message.isBookmarked ? AppTheme.accent : AppTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .background(AppTheme.bgCard.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel(message.isBookmarked ? "Remove bookmark" : "Bookmark message")
            }
        }
    }

    private var userBubbleActions: some View {
        HStack(spacing: 6) {
            bookmarkButton

            if isHovered {
                Button(action: shareMessage) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9))
                        Text("Share")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppTheme.bgCard.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Share message")

                if onEdit != nil {
                    Button(action: {
                        editText = message.content
                        withAnimation(.easeInOut(duration: 0.2)) { isEditing = true }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9))
                            Text("Edit")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.bgCard.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .accessibilityLabel("Edit this message")
                }

                if let onBranch = onBranch {
                    Button(action: onBranch) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text("Branch")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.bgCard.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .accessibilityLabel("Branch conversation from this message")
                }

                replyActionButton
            }

            if showTimestamp {
                HStack(spacing: 4) {
                    Text(timeString(message.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textMuted)

                    if !message.editHistory.isEmpty {
                        Button(action: { showEditHistory.toggle() }) {
                            Text("(edited)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(AppTheme.accent.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showEditHistory, arrowEdge: .bottom) {
                            editHistoryPopover
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
    }

    private var editHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.accent)
                Text("Edit History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(message.editHistory.count) edit\(message.editHistory.count == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(message.editHistory.reversed()) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(editHistoryTimeString(record.editedAt))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(AppTheme.textMuted)
                                Spacer()
                                if onRestoreEdit != nil {
                                    Button(action: {
                                        showEditHistory = false
                                        onRestoreEdit?(record.content)
                                    }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.system(size: 8))
                                            Text("Restore")
                                                .font(.system(size: 9, weight: .medium))
                                        }
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.accent.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Text(record.content)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(4)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        if record.id != message.editHistory.first?.id {
                            Divider().opacity(0.2).padding(.horizontal, 12)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .frame(width: 300)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.bgCard.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.borderGlass, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
    }

    private func editHistoryTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: appState.messageSpacing + 2) {
            if showAvatar {
                GhostIcon(size: appState.avatarSize, animate: message.isStreaming, isProcessing: message.isStreaming)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: appState.avatarSize, height: appState.avatarSize)
            }

            VStack(alignment: .leading, spacing: appState.displayDensity == "compact" ? 3 : appState.displayDensity == "spacious" ? 10 : 6) {
                // Agent badge
                if let agent = message.agentName {
                    AgentBadge(name: agent)
                }

                // Activity strip (hidden in zen mode and compact density)
                if !message.activities.isEmpty && !zenMode && appState.displayDensity != "compact" {
                    ActivityStrip(activities: message.activities, isStreaming: message.isStreaming)
                }

                // Quote bar for reply-to messages
                if message.replyToMessageId != nil {
                    quoteBar
                }

                // Content with hover copy button
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let toolName = message.toolName, !zenMode {
                            ToolCallCard(name: toolName, result: message.toolResult ?? "")
                        } else if message.isStreaming && message.content.isEmpty {
                            StreamingPlaceholder(hasActivities: !message.activities.isEmpty)
                        } else if !message.content.isEmpty {
                            if isRawMode && !message.isStreaming {
                                RawMarkdownView(text: message.content)
                            } else {
                                ResponseView(text: message.content, isStreaming: message.isStreaming, zenMode: zenMode)
                            }
                        }

                        // Inline images detected in message content
                        let imageRefs = extractAllImageRefs(from: message.content)
                        if !imageRefs.isEmpty {
                            InlineImagesStack(refs: imageRefs)
                                .padding(.top, 4)
                        }

                        // Link preview cards for URLs in message
                        if !message.isStreaming {
                            let previewURLs = extractPreviewURLs(from: message.content)
                            if !previewURLs.isEmpty {
                                LinkPreviewsStack(urls: previewURLs)
                                    .padding(.top, 4)
                            }
                        }
                    }

                    // Copy, share, bookmark, speak & retry buttons on hover
                    if message.role == .assistant && !message.content.isEmpty && !message.isStreaming && (isHovered || copied || message.isBookmarked || isSpeakingThis) {
                        HStack(spacing: 4) {
                            // Raw/Rendered markdown toggle
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    localRawMode = !(localRawMode ?? appState.showRawMarkdown)
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: isRawMode ? "doc.richtext" : "doc.plaintext").font(.system(size: 9))
                                    Text(isRawMode ? "Rendered" : "Raw").font(.system(size: 9))
                                }
                                .foregroundColor(isRawMode ? AppTheme.accent : AppTheme.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(isRawMode ? AppTheme.accent.opacity(0.12) : AppTheme.bgCard.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                                    isRawMode ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass,
                                    lineWidth: isRawMode ? 1.0 : 0.5
                                ))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isRawMode ? "Show rendered markdown" : "Show raw markdown")

                            bookmarkButton

                            // Text-to-Speech button
                            if appState.textToSpeechEnabled {
                                Button(action: {
                                    appState.speakMessage(id: message.id, content: message.content)
                                    if !isSpeakingThis {
                                        speakerPulse = true
                                    } else {
                                        speakerPulse = false
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: isSpeakingThis ? "speaker.wave.2.fill" : "speaker.wave.2")
                                            .font(.system(size: 9))
                                            .scaleEffect(isSpeakingThis && speakerPulse ? 1.15 : 1.0)
                                            .animation(
                                                isSpeakingThis
                                                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                                    : .default,
                                                value: speakerPulse
                                            )
                                        Text(isSpeakingThis ? "Stop" : "Speak")
                                            .font(.system(size: 9))
                                    }
                                    .foregroundColor(isSpeakingThis ? AppTheme.accent : (isSpeakingOther ? AppTheme.textMuted.opacity(0.4) : AppTheme.textMuted))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(isSpeakingThis ? AppTheme.accent.opacity(0.12) : AppTheme.bgCard.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                                        isSpeakingThis ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass,
                                        lineWidth: isSpeakingThis ? 1.0 : 0.5
                                    ))
                                }
                                .buttonStyle(.plain)
                                .disabled(isSpeakingOther)
                                .accessibilityLabel(isSpeakingThis ? "Stop speaking" : "Speak message")
                                .onChange(of: appState.isSpeaking) { speaking in
                                    if !speaking { speakerPulse = false }
                                }
                            }

                            Button(action: shareMessage) {
                                HStack(spacing: 3) {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 9))
                                    Text("Share").font(.system(size: 9))
                                }
                                .foregroundColor(AppTheme.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppTheme.bgCard.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Share message")

                            Button(action: {
                                copyToClipboard(message.content, label: "Message")
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

                            replyActionButton
                        }
                        .transition(.opacity)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let reaction = message.reaction {
                        reactionBadge(reaction)
                            .offset(x: 4, y: 8)
                    }
                }

                // Footer
                HStack(spacing: 10) {
                    if showTimestamp {
                        Text(timeString(message.timestamp))
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)

                        if !message.editHistory.isEmpty {
                            Button(action: { showEditHistory.toggle() }) {
                                Text("(edited)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(AppTheme.accent.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showEditHistory, arrowEdge: .bottom) {
                                editHistoryPopover
                            }
                        }

                        if let rtMs = message.responseTimeMs {
                            Text(responseTimeLabel(rtMs))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(responseTimeColor(rtMs).opacity(0.7))
                        }
                    }

                    // Reaction picker: show on hover or if a reaction is already set
                    if !message.isStreaming && !message.content.isEmpty && (isHovered || message.reaction != nil) {
                        reactionPickerButton
                            .transition(.opacity)
                    }

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
        .overlay(
            Group {
                if message.isStreaming {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.accent.opacity(streamingPulse ? 0.35 : 0.08), lineWidth: 1.5)
                        .shadow(color: AppTheme.accent.opacity(streamingPulse ? 0.25 : 0.0), radius: 6)
                        .animation(
                            Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: streamingPulse
                        )
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.isStreaming ? "Assistant is responding" : "Assistant said")
        .onChange(of: appState.showRawMarkdown) { _ in
            localRawMode = nil
        }
        .onChange(of: message.isStreaming) { streaming in
            if streaming {
                streamingPulse = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) { streamingPulse = false }
            }
        }
        .onAppear {
            if message.isStreaming { streamingPulse = true }
        }
    }

    // MARK: - Reaction Picker

    private var reactionPickerButton: some View {
        Button(action: {
            showReactionPicker.toggle()
        }) {
            HStack(spacing: 3) {
                if let reaction = message.reaction {
                    Text(reaction.emoji)
                        .font(.system(size: 12))
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 11))
                }
            }
            .foregroundColor(message.reaction != nil ? AppTheme.accent : AppTheme.textMuted.opacity(0.6))
            .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showReactionPicker, arrowEdge: .top) {
            reactionPickerPopover
        }
        .accessibilityLabel(message.reaction != nil ? "Change reaction" : "Add reaction")
    }

    private var reactionPickerPopover: some View {
        HStack(spacing: 6) {
            ForEach(MessageReaction.allReactions, id: \.self) { reaction in
                let isSelected = message.reaction == reaction
                Button(action: {
                    let newReaction: MessageReaction? = isSelected ? nil : reaction
                    reactionBounce = reaction
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {}
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reactionBounce = nil }
                    onReaction?(newReaction)
                    showReactionPicker = false
                }) {
                    Text(reaction.emoji)
                        .font(.system(size: 20))
                        .scaleEffect(reactionBounce == reaction ? 1.4 : (isSelected ? 1.15 : 1.0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: reactionBounce)
                        .frame(width: 32, height: 32)
                        .background(isSelected ? AppTheme.accent.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reaction.emoji)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func reactionBadge(_ reaction: MessageReaction) -> some View {
        Text(reaction.emoji)
            .font(.system(size: 14))
            .padding(4)
            .background(AppTheme.bgCard)
            .clipShape(Circle())
            .overlay(Circle().stroke(AppTheme.borderGlass, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            .scaleEffect(reactionAppeared ? 1.0 : 0.3)
            .opacity(reactionAppeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    reactionAppeared = true
                }
            }
            .onChange(of: message.reaction) { _ in
                reactionAppeared = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    reactionAppeared = true
                }
            }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private func responseTimeLabel(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }

    private func responseTimeColor(_ ms: Int) -> Color {
        if ms < 2000 { return AppTheme.success }
        if ms < 5000 { return AppTheme.warning }
        return AppTheme.error
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

// MARK: - Raw Markdown View

struct RawMarkdownView: View {
    let text: String

    private var lines: [String] {
        text.components(separatedBy: "\n")
    }

    private var lineNumberWidth: CGFloat {
        let digits = String(lines.count).count
        return CGFloat(max(digits, 2)) * 8 + 12
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                            Text("\(idx + 1)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.textMuted.opacity(0.4))
                                .frame(height: 18)
                        }
                    }
                    .frame(width: lineNumberWidth)
                    .padding(.trailing, 8)

                    // Separator
                    Rectangle()
                        .fill(AppTheme.borderGlass)
                        .frame(width: 1)
                        .padding(.trailing, 10)

                    // Raw text
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.textPrimary)
                                .frame(height: 18, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.bgCard.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.borderGlass, lineWidth: 0.5)
            )

            // "Raw" badge
            Text("Raw")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.textMuted.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.bgCard.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                .padding(8)
        }
    }
}

// MARK: - Response View

struct ResponseView: View {
    let text: String
    let isStreaming: Bool
    var zenMode: Bool = false
    @State private var cursorVisible = true

    var body: some View {
        let sections = ResponseParser.parse(text)
        VStack(alignment: .leading, spacing: zenMode ? 14 : 10) {
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

        case .table(let headers, let alignments, let rows):
            MarkdownTableView(headers: headers, alignments: alignments, rows: rows)

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
    let alignments: [ColumnAlignment]
    let rows: [[String]]

    private func alignment(for colIdx: Int) -> ColumnAlignment {
        colIdx < alignments.count ? alignments[colIdx] : .left
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                        Text(header)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.textPrimary)
                            .multilineTextAlignment(alignment(for: idx).swiftUIAlignment)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minWidth: 90, alignment: alignment(for: idx).frameAlignment)
                        if idx < headers.count - 1 {
                            Rectangle()
                                .fill(AppTheme.borderGlass)
                                .frame(width: 0.5)
                        }
                    }
                }
                .background(AppTheme.bgCard)

                // Header bottom border
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.4))
                    .frame(height: 1.5)

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { colIdx in
                            Text(colIdx < row.count ? row[colIdx] : "")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                                .multilineTextAlignment(alignment(for: colIdx).swiftUIAlignment)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .frame(minWidth: 90, alignment: alignment(for: colIdx).frameAlignment)
                            if colIdx < headers.count - 1 {
                                Rectangle()
                                    .fill(AppTheme.borderGlass.opacity(0.5))
                                    .frame(width: 0.5)
                            }
                        }
                    }
                    .background(rowIdx % 2 == 0 ? AppTheme.bgPrimary.opacity(0.3) : AppTheme.bgCard.opacity(0.4))

                    if rowIdx < rows.count - 1 {
                        Rectangle()
                            .fill(AppTheme.borderGlass.opacity(0.3))
                            .frame(height: 0.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.borderGlass, lineWidth: 1))
        }
        .textSelection(.enabled)
    }
}

// MARK: - Syntax Highlighting

// MARK: - Syntax Theme

struct SyntaxTheme {
    let name: String
    let keyword: Color
    let string: Color
    let comment: Color
    let number: Color
    let type: Color
    let function: Color
    let `operator`: Color
    let background: Color
    let foreground: Color

    static let monokai = SyntaxTheme(
        name: "Monokai",
        keyword: Color(red: 0xF9/255, green: 0x26/255, blue: 0x72/255),
        string: Color(red: 0xE6/255, green: 0xDB/255, blue: 0x74/255),
        comment: Color(red: 0x75/255, green: 0x71/255, blue: 0x5E/255),
        number: Color(red: 0xAE/255, green: 0x81/255, blue: 0xFF/255),
        type: Color(red: 0x66/255, green: 0xD9/255, blue: 0xEF/255),
        function: Color(red: 0xA6/255, green: 0xE2/255, blue: 0x2E/255),
        operator: Color(red: 0xF9/255, green: 0x26/255, blue: 0x72/255),
        background: Color(red: 0x27/255, green: 0x28/255, blue: 0x22/255),
        foreground: Color(red: 0xF8/255, green: 0xF8/255, blue: 0xF2/255)
    )

    static let dracula = SyntaxTheme(
        name: "Dracula",
        keyword: Color(red: 0xFF/255, green: 0x79/255, blue: 0xC6/255),
        string: Color(red: 0xF1/255, green: 0xFA/255, blue: 0x8C/255),
        comment: Color(red: 0x62/255, green: 0x72/255, blue: 0xA4/255),
        number: Color(red: 0xBD/255, green: 0x93/255, blue: 0xF9/255),
        type: Color(red: 0x8B/255, green: 0xE9/255, blue: 0xFD/255),
        function: Color(red: 0x50/255, green: 0xFA/255, blue: 0x7B/255),
        operator: Color(red: 0xFF/255, green: 0x79/255, blue: 0xC6/255),
        background: Color(red: 0x28/255, green: 0x2A/255, blue: 0x36/255),
        foreground: Color(red: 0xF8/255, green: 0xF8/255, blue: 0xF2/255)
    )

    static let githubDark = SyntaxTheme(
        name: "GitHub Dark",
        keyword: Color(red: 0xFF/255, green: 0x7B/255, blue: 0x72/255),
        string: Color(red: 0xA5/255, green: 0xD6/255, blue: 0xFF/255),
        comment: Color(red: 0x8B/255, green: 0x94/255, blue: 0x9E/255),
        number: Color(red: 0x79/255, green: 0xC0/255, blue: 0xFF/255),
        type: Color(red: 0xFF/255, green: 0xD7/255, blue: 0x00/255),
        function: Color(red: 0xD2/255, green: 0xA8/255, blue: 0xFF/255),
        operator: Color(red: 0xFF/255, green: 0x7B/255, blue: 0x72/255),
        background: Color(red: 0x0D/255, green: 0x11/255, blue: 0x17/255),
        foreground: Color(red: 0xE6/255, green: 0xED/255, blue: 0xF3/255)
    )

    static let solarizedDark = SyntaxTheme(
        name: "Solarized Dark",
        keyword: Color(red: 0x85/255, green: 0x99/255, blue: 0x00/255),
        string: Color(red: 0x2A/255, green: 0xA1/255, blue: 0x98/255),
        comment: Color(red: 0x58/255, green: 0x6E/255, blue: 0x75/255),
        number: Color(red: 0xD3/255, green: 0x36/255, blue: 0x82/255),
        type: Color(red: 0xB5/255, green: 0x89/255, blue: 0x00/255),
        function: Color(red: 0x26/255, green: 0x8B/255, blue: 0xD2/255),
        operator: Color(red: 0xCB/255, green: 0x4B/255, blue: 0x16/255),
        background: Color(red: 0x00/255, green: 0x2B/255, blue: 0x36/255),
        foreground: Color(red: 0x83/255, green: 0x94/255, blue: 0x96/255)
    )

    static let availableThemes: [String: SyntaxTheme] = [
        "Monokai": .monokai,
        "Dracula": .dracula,
        "GitHub Dark": .githubDark,
        "Solarized Dark": .solarizedDark
    ]

    static let themeNames: [String] = ["Monokai", "Dracula", "GitHub Dark", "Solarized Dark"]

    static func named(_ name: String) -> SyntaxTheme {
        availableThemes[name] ?? .monokai
    }
}

private struct SyntaxHighlighter {
    private static let swiftKeywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "import",
        "class", "struct", "enum", "protocol", "extension", "guard", "switch",
        "case", "break", "continue", "defer", "do", "catch", "throw", "throws",
        "try", "as", "is", "in", "where", "self", "Self", "super", "init",
        "deinit", "typealias", "associatedtype", "static", "override", "private",
        "public", "internal", "fileprivate", "open", "mutating", "nonmutating",
        "weak", "unowned", "lazy", "final", "required", "convenience", "optional",
        "some", "any", "async", "await", "actor", "nil", "true", "false",
        "inout", "operator", "precedencegroup", "subscript", "willSet", "didSet",
        "get", "set"
    ]

    private static let pythonKeywords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "return", "import",
        "from", "as", "try", "except", "finally", "raise", "with", "yield",
        "lambda", "pass", "break", "continue", "and", "or", "not", "in", "is",
        "True", "False", "None", "self", "async", "await", "global", "nonlocal",
        "del", "assert"
    ]

    private static let jsKeywords: Set<String> = [
        "function", "const", "let", "var", "if", "else", "for", "while", "return",
        "import", "export", "default", "from", "class", "extends", "new", "this",
        "super", "typeof", "instanceof", "try", "catch", "finally", "throw",
        "async", "await", "yield", "switch", "case", "break", "continue",
        "do", "of", "in", "delete", "void", "null", "undefined", "true", "false",
        "NaN", "Infinity", "interface", "type", "enum", "implements", "abstract",
        "static", "readonly", "public", "private", "protected"
    ]

    private static let genericKeywords: Set<String> = [
        "func", "function", "def", "let", "var", "const", "if", "else", "elif",
        "for", "while", "return", "import", "from", "class", "struct", "enum",
        "switch", "case", "break", "continue", "try", "catch", "except",
        "finally", "throw", "raise", "new", "this", "self", "super", "nil",
        "null", "None", "true", "false", "True", "False", "async", "await",
        "yield", "static", "public", "private", "protected", "override",
        "export", "default", "do", "in", "is", "as", "with", "lambda",
        "pass", "type", "interface", "protocol", "extension", "guard",
        "where", "select", "insert", "update", "delete", "create", "drop",
        "table", "index", "join", "on", "group", "order",
        "by", "having", "limit", "offset", "and", "or", "not"
    ]

    static func keywords(for language: String) -> Set<String> {
        switch language.lowercased() {
        case "swift": return swiftKeywords
        case "python", "py": return pythonKeywords
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": return jsKeywords
        default: return genericKeywords
        }
    }

    static func highlight(_ code: String, language: String, theme: SyntaxTheme = .monokai) -> AttributedString {
        var result = AttributedString(code)
        let fullNS = code as NSString
        let fullRange = NSRange(location: 0, length: fullNS.length)
        let kw = keywords(for: language)

        result.font = .system(size: 12, design: .monospaced)
        result.foregroundColor = theme.foreground

        var protectedRanges: [NSRange] = []

        // Block comments /* ... */
        if let regex = try? NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#, options: [.dotMatchesLineSeparators]) {
            for match in regex.matches(in: code, range: fullRange) {
                if let swiftRange = Range(match.range, in: code) {
                    applyColor(to: &result, in: code, swiftRange: swiftRange, color: theme.comment)
                    protectedRanges.append(match.range)
                }
            }
        }

        // Single-line comments
        let commentPatterns: [String]
        switch language.lowercased() {
        case "python", "py", "bash", "sh", "zsh", "shell", "ruby", "rb", "yaml", "yml":
            commentPatterns = [#"//.*$"#, #"#.*$"#]
        default:
            commentPatterns = [#"//.*$"#]
        }
        for pattern in commentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                for match in regex.matches(in: code, range: fullRange) {
                    if isProtected(match.range, by: protectedRanges) { continue }
                    if let swiftRange = Range(match.range, in: code) {
                        applyColor(to: &result, in: code, swiftRange: swiftRange, color: theme.comment)
                        protectedRanges.append(match.range)
                    }
                }
            }
        }

        // Strings
        for strPattern in [#""(?:[^"\\]|\\.)*""#, #"'(?:[^'\\]|\\.)*'"#] {
            if let regex = try? NSRegularExpression(pattern: strPattern, options: []) {
                for match in regex.matches(in: code, range: fullRange) {
                    if isProtected(match.range, by: protectedRanges) { continue }
                    if let swiftRange = Range(match.range, in: code) {
                        applyColor(to: &result, in: code, swiftRange: swiftRange, color: theme.string)
                        protectedRanges.append(match.range)
                    }
                }
            }
        }

        // Numbers
        if let regex = try? NSRegularExpression(pattern: #"\b(?:0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, options: []) {
            for match in regex.matches(in: code, range: fullRange) {
                if isProtected(match.range, by: protectedRanges) { continue }
                if let swiftRange = Range(match.range, in: code) {
                    applyColor(to: &result, in: code, swiftRange: swiftRange, color: theme.number)
                }
            }
        }

        // Keywords
        if !kw.isEmpty {
            let escaped = kw.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "(?<![\\w@])(" + escaped.joined(separator: "|") + ")(?!\\w)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                for match in regex.matches(in: code, range: fullRange) {
                    if isProtected(match.range, by: protectedRanges) { continue }
                    if let swiftRange = Range(match.range, in: code) {
                        applyColor(to: &result, in: code, swiftRange: swiftRange, color: theme.keyword)
                    }
                }
            }
        }

        // Types (PascalCase identifiers)
        if let regex = try? NSRegularExpression(pattern: #"\b[A-Z][a-zA-Z0-9]+\b"#, options: []) {
            for match in regex.matches(in: code, range: fullRange) {
                if isProtected(match.range, by: protectedRanges) { continue }
                if let swiftRange = Range(match.range, in: code) {
                    let word = String(code[swiftRange])
                    if !kw.contains(word) {
                        applyColor(to: &result, in: code, swiftRange: swiftRange, color: theme.type)
                    }
                }
            }
        }

        // Function calls: identifier followed by (
        if let regex = try? NSRegularExpression(pattern: #"\b([a-zA-Z_]\w*)\s*\("#, options: []) {
            for match in regex.matches(in: code, range: fullRange) {
                let nameRange = match.range(at: 1)
                if isProtected(nameRange, by: protectedRanges) { continue }
                if let swiftRange = Range(nameRange, in: code) {
                    let word = String(code[swiftRange])
                    if !kw.contains(word) {
                        applyColor(to: &result, in: code, swiftRange: swiftRange, color: theme.function)
                    }
                }
            }
        }

        return result
    }

    private static func applyColor(to result: inout AttributedString, in code: String, swiftRange: Range<String.Index>, color: Color) {
        let startOffset = code.distance(from: code.startIndex, to: swiftRange.lowerBound)
        let endOffset = code.distance(from: code.startIndex, to: swiftRange.upperBound)
        let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
        let attrEnd = result.index(result.startIndex, offsetByCharacters: endOffset)
        result[attrStart..<attrEnd].foregroundColor = color
    }

    private static func isProtected(_ range: NSRange, by protected: [NSRange]) -> Bool {
        for p in protected {
            if NSIntersectionRange(range, p).length > 0 { return true }
        }
        return false
    }

    static func languageColor(for language: String) -> Color {
        switch language.lowercased() {
        case "swift": return Color(red: 0xFF/255, green: 0x6B/255, blue: 0x35/255)
        case "python", "py": return Color(red: 0x30/255, green: 0x76/255, blue: 0xAB/255)
        case "javascript", "js": return Color(red: 0xF7/255, green: 0xDF/255, blue: 0x1E/255)
        case "typescript", "ts": return Color(red: 0x31/255, green: 0x78/255, blue: 0xC6/255)
        case "jsx", "tsx": return Color(red: 0x61/255, green: 0xDA/255, blue: 0xFB/255)
        case "rust", "rs": return Color(red: 0xDE/255, green: 0x56/255, blue: 0x16/255)
        case "go", "golang": return Color(red: 0x00/255, green: 0xAD/255, blue: 0xD8/255)
        case "ruby", "rb": return Color(red: 0xCC/255, green: 0x34/255, blue: 0x2D/255)
        case "bash", "sh", "zsh", "shell": return Color(red: 0x4E/255, green: 0xAA/255, blue: 0x25/255)
        case "html": return Color(red: 0xE3/255, green: 0x4C/255, blue: 0x26/255)
        case "css", "scss", "sass": return Color(red: 0x26/255, green: 0x65/255, blue: 0xF5/255)
        case "json": return Color(red: 0xA8/255, green: 0xA8/255, blue: 0xA8/255)
        case "yaml", "yml": return Color(red: 0xCB/255, green: 0x17/255, blue: 0x1E/255)
        case "sql": return Color(red: 0xE3/255, green: 0x8C/255, blue: 0x00/255)
        case "c": return Color(red: 0x55/255, green: 0x55/255, blue: 0xCC/255)
        case "cpp", "c++": return Color(red: 0x00/255, green: 0x59/255, blue: 0x9C/255)
        case "java": return Color(red: 0xB0/255, green: 0x72/255, blue: 0x19/255)
        case "kotlin", "kt": return Color(red: 0x7F/255, green: 0x52/255, blue: 0xFF/255)
        default: return AppTheme.textMuted
        }
    }
}

// MARK: - Code Block

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false
    @State private var isExpanded = true
    @AppStorage("syntaxTheme") private var syntaxThemeName: String = "Monokai"

    private var currentTheme: SyntaxTheme { SyntaxTheme.named(syntaxThemeName) }
    private var lines: [String] { code.components(separatedBy: "\n") }
    private var lineCount: Int { lines.count }
    private var lineNumberWidth: CGFloat {
        let digits = max(2, String(lines.count).count)
        return CGFloat(digits) * 8 + 12
    }
    private var langColor: Color { SyntaxHighlighter.languageColor(for: language) }
    private var displayLang: String { language.isEmpty ? "code" : language.lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top border accent line
            Rectangle()
                .fill(langColor.opacity(0.6))
                .frame(height: 2)

            // Header bar with language badge, line count, collapse toggle, and copy button
            HStack(spacing: 0) {
                // Language label (left)
                Text(displayLang)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                // Line count (center)
                Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)

                Spacer()

                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(copied ? AppTheme.success : AppTheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(copied ? AppTheme.success.opacity(0.12) : Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)

                // Collapse/expand toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.bgPrimary)

            if isExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                // Code area with line numbers
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                                Text("\(idx + 1)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color(red: 0x44/255, green: 0x44/255, blue: 0x55/255))
                                    .frame(height: 18, alignment: .trailing)
                            }
                        }
                        .frame(width: lineNumberWidth, alignment: .trailing)
                        .padding(.trailing, 8)

                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 1)
                            .padding(.trailing, 10)

                        Text(SyntaxHighlighter.highlight(code, language: language, theme: currentTheme))
                            .textSelection(.enabled)
                            .lineSpacing(0)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minHeight: CGFloat(lines.count) * 18, alignment: .topLeading)
                    }
                    .padding(.vertical, 10)
                    .padding(.trailing, 10)
                }
            } else {
                // Collapsed state: show hidden line count
                HStack {
                    Spacer()
                    Text("\(lineCount) line\(lineCount == 1 ? "" : "s") hidden")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted.opacity(0.7))
                        .padding(.vertical, 8)
                    Spacer()
                }
                .background(currentTheme.background)
            }
        }
        .background(currentTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipped()
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
            .transition(.opacity.animation(.easeOut(duration: 0.25)))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                TypingIndicator()
                Text("Agent is thinking...")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)
            }
            .transition(.opacity.animation(.easeOut(duration: 0.25)))
        }
    }
}

struct TypingIndicator: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .offset(y: animating ? -4 : 2)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.bgCard.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.borderGlass, lineWidth: 0.5))
        .onAppear {
            // Small delay so the staggered animation offsets take effect visually
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animating = true
            }
        }
    }
}

// MARK: - Streaming Status Bar

struct StreamingStatusBar: View {
    let activities: [ActivityItem]
    let startTime: Date?
    @State private var shimmerOffset: CGFloat = -200
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    private var statusText: String {
        if let active = activities.last(where: { !$0.isComplete }) {
            switch active.type {
            case .toolCall:
                return "Running tool: \(active.label)"
            case .mcpLoading:
                return "Loading: \(active.label)"
            case .thinking:
                return "Thinking..."
            case .agentRoute:
                return "Routing to \(active.label)..."
            case .status:
                return active.label
            }
        }
        if let last = activities.last {
            if last.type == .toolCall && last.isComplete {
                return "Analyzing results..."
            }
        }
        return "Thinking..."
    }

    private var elapsedString: String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textMuted)

            Spacer()

            Text(elapsedString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.bgCard.opacity(0.5))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            AppTheme.accent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 120)
                    .offset(x: shimmerOffset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.borderGlass, lineWidth: 0.5))
        .padding(.leading, 38)
        .onAppear {
            startTimers()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startTimers() {
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            shimmerOffset = 400
        }
        if let start = startTime {
            elapsed = Date().timeIntervalSince(start)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let start = startTime {
                elapsed = Date().timeIntervalSince(start)
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

// MARK: - Markdown Table Model & Helpers

enum ColumnAlignment {
    case left, center, right

    var swiftUIAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

struct MarkdownTable {
    let headers: [String]
    let alignments: [ColumnAlignment]
    let rows: [[String]]
}

/// Detects whether a block of text contains a markdown table.
func isMarkdownTable(_ text: String) -> Bool {
    let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    // Need at least 2 lines: header + separator
    guard lines.count >= 2 else { return false }
    // Find a pair of consecutive lines where the first is a table row and the second is a separator
    for i in 0..<(lines.count - 1) {
        let row = lines[i]
        let sep = lines[i + 1]
        if row.hasPrefix("|") && row.filter({ $0 == "|" }).count >= 2 {
            let inner = sep.replacingOccurrences(of: "|", with: "")
                          .replacingOccurrences(of: "-", with: "")
                          .replacingOccurrences(of: ":", with: "")
                          .trimmingCharacters(in: .whitespaces)
            if sep.hasPrefix("|") && inner.isEmpty {
                return true
            }
        }
    }
    return false
}

/// Parses a markdown table string into a structured MarkdownTable.
func parseMarkdownTable(from text: String) -> MarkdownTable? {
    let lines = text.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    guard lines.count >= 2 else { return nil }

    // Find header + separator pair
    var headerIdx = -1
    for i in 0..<(lines.count - 1) {
        let row = lines[i]
        let sep = lines[i + 1]
        if row.hasPrefix("|") && row.filter({ $0 == "|" }).count >= 2 {
            let inner = sep.replacingOccurrences(of: "|", with: "")
                          .replacingOccurrences(of: "-", with: "")
                          .replacingOccurrences(of: ":", with: "")
                          .trimmingCharacters(in: .whitespaces)
            if sep.hasPrefix("|") && inner.isEmpty {
                headerIdx = i
                break
            }
        }
    }

    guard headerIdx >= 0 else { return nil }

    func parseCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    let headers = parseCells(lines[headerIdx])
    let separatorCells = parseCells(lines[headerIdx + 1])

    // Parse alignments from separator row
    var alignments: [ColumnAlignment] = []
    for cell in separatorCells {
        let t = cell.trimmingCharacters(in: .whitespaces)
        let startsColon = t.hasPrefix(":")
        let endsColon = t.hasSuffix(":")
        if startsColon && endsColon {
            alignments.append(.center)
        } else if endsColon {
            alignments.append(.right)
        } else {
            alignments.append(.left)
        }
    }

    // Pad alignments to match header count
    while alignments.count < headers.count { alignments.append(.left) }

    // Parse data rows
    var rows: [[String]] = []
    for i in (headerIdx + 2)..<lines.count {
        let line = lines[i]
        guard line.hasPrefix("|") && line.filter({ $0 == "|" }).count >= 2 else { break }
        rows.append(parseCells(line))
    }

    return MarkdownTable(headers: headers, alignments: alignments, rows: rows)
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
    case table(headers: [String], alignments: [ColumnAlignment], rows: [[String]])
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
                    // Parse alignments from separator row
                    let hasSeparator = isTableSeparator(tableLines.count > 1 ? tableLines[1] : "")
                    var alignments: [ColumnAlignment] = []
                    if hasSeparator {
                        let sepCells = parseTableRow(tableLines[1])
                        for cell in sepCells {
                            let t = cell.trimmingCharacters(in: .whitespaces)
                            let startsColon = t.hasPrefix(":")
                            let endsColon = t.hasSuffix(":")
                            if startsColon && endsColon {
                                alignments.append(.center)
                            } else if endsColon {
                                alignments.append(.right)
                            } else {
                                alignments.append(.left)
                            }
                        }
                    }
                    // Pad alignments to match header count
                    while alignments.count < headerCells.count { alignments.append(.left) }
                    let startRow = hasSeparator ? 2 : 1
                    var dataRows: [[String]] = []
                    for r in startRow..<tableLines.count {
                        dataRows.append(parseTableRow(tableLines[r]))
                    }
                    sections.append(.table(headers: headerCells, alignments: alignments, rows: dataRows))
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
    @Environment(\.zenMode) private var zenMode

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

    private var bodyFontSize: CGFloat { zenMode ? 15 : 14 }
    private var codeInlineFontSize: CGFloat { zenMode ? 13.5 : 12.5 }
    private var lineSpacingValue: CGFloat { zenMode ? 5.5 : 4 }

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
                        attr.font = .system(size: bodyFontSize)
                        Self.styleLinks(&attr)
                        combined.append(attr)
                    } else {
                        var attr = AttributedString(t)
                        attr.font = .system(size: bodyFontSize)
                        attr.foregroundColor = AppTheme.textPrimary
                        combined.append(attr)
                    }
                case .code(let c):
                    var space = AttributedString("\u{200A}")
                    space.font = .system(size: 2)
                    combined.append(space)
                    var attr = AttributedString(c)
                    attr.font = .system(size: codeInlineFontSize, design: .monospaced)
                    attr.foregroundColor = AppTheme.accent
                    attr.backgroundColor = AppTheme.bgCard
                    combined.append(attr)
                    combined.append(space)
                }
                return combined
            }
            Text(combined)
                .lineSpacing(lineSpacingValue).textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    NSWorkspace.shared.open(url)
                    return .handled
                })
        } else {
            if var attributed = try? AttributedString(markdown: str, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let _ = Self.styleLinks(&attributed)
                Text(attributed)
                    .font(.system(size: bodyFontSize)).foregroundColor(AppTheme.textPrimary)
                    .lineSpacing(lineSpacingValue).textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
            } else {
                Text(str)
                    .font(.system(size: bodyFontSize)).foregroundColor(AppTheme.textPrimary)
                    .lineSpacing(lineSpacingValue).textSelection(.enabled)
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
