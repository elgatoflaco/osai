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

// MARK: - Diff Helper

enum DiffType {
    case unchanged
    case added
    case removed
}

struct DiffLine: Identifiable {
    let id = UUID()
    let type: DiffType
    let content: String
}

/// Computes a line-by-line diff between two strings using a simple LCS algorithm.
func computeLineDiff(old: String, new: String) -> [DiffLine] {
    let oldLines = old.components(separatedBy: "\n")
    let newLines = new.components(separatedBy: "\n")
    let m = oldLines.count
    let n = newLines.count

    // Build LCS table
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in 1...max(m, 1) {
        guard i <= m else { break }
        for j in 1...max(n, 1) {
            guard j <= n else { break }
            if oldLines[i - 1] == newLines[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    // Backtrack to produce diff
    var result: [DiffLine] = []
    var i = m, j = n
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
            result.append(DiffLine(type: .unchanged, content: oldLines[i - 1]))
            i -= 1; j -= 1
        } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
            result.append(DiffLine(type: .added, content: newLines[j - 1]))
            j -= 1
        } else if i > 0 {
            result.append(DiffLine(type: .removed, content: oldLines[i - 1]))
            i -= 1
        }
    }

    return result.reversed()
}

// MARK: - Diff View

struct InlineDiffView: View {
    let diffLines: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(diffLines) { line in
                HStack(spacing: 4) {
                    Text(linePrefix(line.type))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(lineColor(line.type))
                        .frame(width: 12, alignment: .center)

                    Text(line.content.isEmpty ? " " : line.content)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(lineTextColor(line.type))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(lineBackground(line.type))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func linePrefix(_ type: DiffType) -> String {
        switch type {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private func lineColor(_ type: DiffType) -> Color {
        switch type {
        case .unchanged: return AppTheme.textMuted
        case .added: return AppTheme.success
        case .removed: return AppTheme.error
        }
    }

    private func lineTextColor(_ type: DiffType) -> Color {
        switch type {
        case .unchanged: return AppTheme.textSecondary
        case .added: return AppTheme.success
        case .removed: return AppTheme.error
        }
    }

    private func lineBackground(_ type: DiffType) -> Color {
        switch type {
        case .unchanged: return .clear
        case .added: return AppTheme.success.opacity(0.1)
        case .removed: return AppTheme.error.opacity(0.1)
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
    var onAnnotate: ((String?) -> Void)?
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
    @State private var isAnnotating = false
    @State private var annotationText = ""
    @State private var showEditHistory = false
    @State private var showDiff = false
    @State private var diffTargetRecordId: UUID?
    /// Pulse animation state for streaming border glow
    @State private var streamingPulse = false
    /// Hover state for timestamp (used in "hover" display mode)
    @State private var timestampHovered = false
    /// Timer-driven tick for relative timestamp updates
    @State private var relativeTick: Int = 0
    /// Timer for relative timestamp auto-refresh
    @State private var relativeTimer: Timer?

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
            updateRelativeTimer()
        }
        .onDisappear {
            relativeTimer?.invalidate()
            relativeTimer = nil
        }
        .onChange(of: appState.timestampDisplay) { _ in
            updateRelativeTimer()
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
        .accessibilityValue("\(message.isBookmarked ? "Bookmarked. " : "")at \(timeString(message.timestamp))\(message.reaction != nil ? ". Reaction: \(reactionAccessibilityName(message.reaction!))" : "")")
        .accessibilityAction(named: "Copy message") {
            copyToClipboard(message.content, label: "Message")
        }
        .accessibilityAction(named: "Bookmark") {
            onBookmark?()
        }
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
                .accessibilityHint("Double tap to quote and reply")
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
                .accessibilityHint(message.isBookmarked ? "Double tap to remove bookmark" : "Double tap to bookmark this message")
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
                .accessibilityHint("Double tap to share this message")

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
                    .accessibilityHint("Double tap to edit and resend")
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
                    .accessibilityHint("Double tap to create a new conversation branch")
                }

                replyActionButton

                if onAnnotate != nil && message.annotation == nil {
                    Button(action: {
                        annotationText = ""
                        withAnimation(.easeInOut(duration: 0.2)) { isAnnotating = true }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.system(size: 9))
                            Text("Add Note")
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
                    .accessibilityLabel("Add a note to this message")
                }
            }

            if showTimestamp && appState.timestampDisplay != "hidden" {
                HStack(spacing: 4) {
                    Text(formattedTimestamp(message.timestamp))
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
                .opacity(isTimestampVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isTimestampVisible)
            }

            annotationView
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
            .padding(.bottom, 6)

            // Show Diff toggle
            HStack {
                Toggle(isOn: $showDiff) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9))
                        Text("Show Diff")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider().opacity(0.3)

            // Diff view when a record is selected for comparison
            if showDiff, let targetId = diffTargetRecordId,
               let record = message.editHistory.first(where: { $0.id == targetId }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Comparing with current")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                        Spacer()
                        Button(action: { diffTargetRecordId = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ScrollView {
                        InlineDiffView(
                            diffLines: computeLineDiff(old: record.content, new: message.content)
                        )
                        .padding(.horizontal, 6)
                    }
                    .frame(maxHeight: 200)
                    .padding(.bottom, 4)
                }

                Divider().opacity(0.3)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(message.editHistory.reversed()) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(editHistoryTimeString(record.editedAt))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(AppTheme.textMuted)
                                Spacer()

                                if showDiff {
                                    Button(action: {
                                        diffTargetRecordId = record.id
                                    }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.left.arrow.right")
                                                .font(.system(size: 8))
                                            Text("Compare with current")
                                                .font(.system(size: 9, weight: .medium))
                                        }
                                        .foregroundColor(diffTargetRecordId == record.id ? .white : AppTheme.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            diffTargetRecordId == record.id
                                                ? AppTheme.accent
                                                : AppTheme.accent.opacity(0.1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                }

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
                                .lineLimit(showDiff && diffTargetRecordId == record.id ? nil : 4)
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
        .frame(width: showDiff && diffTargetRecordId != nil ? 420 : 300)
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
        .animation(.easeInOut(duration: 0.2), value: showDiff)
        .animation(.easeInOut(duration: 0.2), value: diffTargetRecordId)
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
                                ResponseView(text: message.content, isStreaming: message.isStreaming, zenMode: zenMode, messageId: message.id)
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
                            .accessibilityHint("Double tap to share this response")

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
                            .accessibilityHint("Double tap to copy message text")

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
                                .accessibilityHint("Double tap to regenerate this response")
                            }

                            replyActionButton

                            if onAnnotate != nil && message.annotation == nil {
                                Button(action: {
                                    annotationText = ""
                                    withAnimation(.easeInOut(duration: 0.2)) { isAnnotating = true }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "note.text").font(.system(size: 9))
                                        Text("Add Note").font(.system(size: 9))
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
                                .accessibilityLabel("Add a note to this message")
                            }
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

                // Annotation card
                annotationView

                // Footer
                HStack(spacing: 10) {
                    if showTimestamp && appState.timestampDisplay != "hidden" {
                        HStack(spacing: 10) {
                            Text(formattedTimestamp(message.timestamp))
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
                        .opacity(isTimestampVisible ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isTimestampVisible)
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
        .accessibilityLabel(message.isStreaming ? "Assistant is responding" : "Assistant said: \(String(message.content.prefix(200)))")
        .accessibilityValue("\(message.isBookmarked ? "Bookmarked. " : "")\(message.agentName != nil ? "Via \(message.agentName!) agent. " : "")at \(timeString(message.timestamp))\(message.reaction != nil ? ". Reaction: \(reactionAccessibilityName(message.reaction!))" : "")")
        .accessibilityAction(named: "Copy message") {
            copyToClipboard(message.content, label: "Message")
        }
        .accessibilityAction(named: "Bookmark") {
            onBookmark?()
        }
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

    // MARK: - Annotation View

    private var annotationView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Display saved annotation
            if let annotation = message.annotation, !annotation.isEmpty, !isAnnotating {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                        .foregroundColor(Color.yellow.opacity(0.8))
                    Text(annotation)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Spacer()
                    Button(action: {
                        annotationText = annotation
                        withAnimation(.easeInOut(duration: 0.2)) { isAnnotating = true }
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit note")
                    Button(action: {
                        onAnnotate?(nil)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete note")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.2), lineWidth: 0.5))
            }

            // Inline text field for adding/editing annotation
            if isAnnotating {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundColor(Color.yellow.opacity(0.8))
                        TextField("Add a note...", text: $annotationText)
                            .font(.system(size: 12))
                            .textFieldStyle(.plain)
                            .foregroundColor(AppTheme.textPrimary)
                            .onSubmit {
                                let trimmed = annotationText.trimmingCharacters(in: .whitespacesAndNewlines)
                                onAnnotate?(trimmed.isEmpty ? nil : trimmed)
                                withAnimation(.easeInOut(duration: 0.2)) { isAnnotating = false }
                            }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.3), lineWidth: 1))

                    HStack(spacing: 6) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) { isAnnotating = false }
                        }) {
                            Text("Cancel")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.bgCard.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            let trimmed = annotationText.trimmingCharacters(in: .whitespacesAndNewlines)
                            onAnnotate?(trimmed.isEmpty ? nil : trimmed)
                            withAnimation(.easeInOut(duration: 0.2)) { isAnnotating = false }
                        }) {
                            Text("Save")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
        .accessibilityLabel(message.reaction != nil ? "Change reaction, currently \(reactionAccessibilityName(message.reaction!))" : "Add reaction")
        .accessibilityHint("Double tap to open reaction picker")
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
                .accessibilityLabel("\(reactionAccessibilityName(reaction)) reaction\(isSelected ? ", selected" : "")")
                .accessibilityHint(isSelected ? "Double tap to remove reaction" : "Double tap to react")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func reactionAccessibilityName(_ reaction: MessageReaction) -> String {
        switch reaction {
        case .thumbsUp: return "thumbs up"
        case .thumbsDown: return "thumbs down"
        case .heart: return "heart"
        case .laugh: return "laughing"
        case .thinking: return "thinking"
        case .party: return "party"
        }
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
            .accessibilityLabel("Reaction: \(reactionAccessibilityName(reaction))")
            .accessibilityValue(reactionAccessibilityName(reaction))
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

    /// Returns a human-readable relative timestamp string.
    private func relativeTimeString(_ date: Date) -> String {
        // Reference relativeTick so SwiftUI re-evaluates when the timer fires
        _ = relativeTick
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(elapsed / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(elapsed / 86400)
        return "\(days)d ago"
    }

    /// Returns the appropriate timestamp text based on the current display setting.
    private func formattedTimestamp(_ date: Date) -> String {
        switch appState.timestampDisplay {
        case "always": return timeString(date)
        case "relative": return relativeTimeString(date)
        default: return timeString(date)
        }
    }

    /// Whether the timestamp should currently be visible based on display mode and hover state.
    private var isTimestampVisible: Bool {
        switch appState.timestampDisplay {
        case "hidden": return false
        case "hover": return isHovered
        case "always", "relative": return true
        default: return isHovered
        }
    }

    /// Starts the relative-time refresh timer if needed, and invalidates it on mode change.
    private func updateRelativeTimer() {
        relativeTimer?.invalidate()
        relativeTimer = nil
        if appState.timestampDisplay == "relative" {
            relativeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                relativeTick += 1
            }
        }
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
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Raw markdown, \(lines.count) line\(lines.count == 1 ? "" : "s")")
    }
}

// MARK: - Footnote Support

/// Represents a parsed footnote definition from markdown text.
struct FootnoteDefinition: Identifiable {
    let id: String        // The footnote key, e.g. "1", "note"
    let displayIndex: Int // 1-based display number
    let text: String      // The footnote body text
}

/// Parses footnote definitions from the full message text.
/// Matches lines like: [^1]: Some footnote text
private func parseFootnoteDefinitions(from text: String) -> [FootnoteDefinition] {
    let pattern = #"^\[\^([^\]]+)\]:\s*(.+)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    var defs: [FootnoteDefinition] = []
    var seen = Set<String>()
    for match in regex.matches(in: text, range: range) {
        guard match.numberOfRanges >= 3 else { continue }
        let key = nsText.substring(with: match.range(at: 1))
        let body = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        if !seen.contains(key) {
            seen.insert(key)
            defs.append(FootnoteDefinition(id: key, displayIndex: defs.count + 1, text: body))
        }
    }
    return defs
}

/// Removes footnote definition lines from text so they don't render inline.
private func stripFootnoteDefinitions(from text: String) -> String {
    let pattern = #"^\[\^[^\]]+\]:\s*.+$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return text }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
}

/// Collects footnote reference keys [^key] in the order they appear in text.
/// Returns an ordered mapping from key -> display index.
private func footnoteReferenceOrder(from text: String) -> [String: Int] {
    let pattern = #"\[\^([^\]]+)\](?!:)"# // Match [^key] but not [^key]: (definitions)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [:] }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    var order: [String: Int] = [:]
    var idx = 1
    for match in regex.matches(in: text, range: range) {
        guard match.numberOfRanges >= 2 else { continue }
        let key = nsText.substring(with: match.range(at: 1))
        if order[key] == nil {
            order[key] = idx
            idx += 1
        }
    }
    return order
}

/// View that renders the footnotes section at the bottom of a message.
struct FootnoteSectionView: View {
    let definitions: [FootnoteDefinition]
    @Binding var highlightedFootnoteId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Horizontal rule
            Rectangle()
                .fill(AppTheme.borderGlass)
                .frame(height: 1)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(definitions) { def in
                    HStack(alignment: .top, spacing: 6) {
                        // Clickable footnote number
                        Text("\(def.displayIndex).")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppTheme.accent)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    highlightedFootnoteId = "ref-\(def.id)"
                                }
                                // Clear highlight after a moment
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        if highlightedFootnoteId == "ref-\(def.id)" {
                                            highlightedFootnoteId = nil
                                        }
                                    }
                                }
                            }
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }

                        // Footnote text
                        if let attributed = try? AttributedString(
                            markdown: def.text,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                        ) {
                            Text(attributed)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                                .lineSpacing(3)
                        } else {
                            Text(def.text)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                                .lineSpacing(3)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlightedFootnoteId == "def-\(def.id)" ? AppTheme.accent.opacity(0.15) : Color.clear)
                    )
                    .id("footnote-def-\(def.id)")
                }
            }
        }
    }
}

// MARK: - Collapsible Section Model

/// Groups parsed response sections by heading for collapsible display.
private struct CollapsibleGroup: Identifiable {
    let id: Int // section index
    let headingText: String
    let headingLevel: Int
    let content: [IndexedSection]
}

/// A response section tagged with its original index for stable identity.
private struct IndexedSection: Identifiable {
    let id: Int
    let section: ResponseSection
}

/// Splits flat parsed sections into collapsible groups.
/// Each group starts with a heading (## or ###) and includes all content until the next heading.
/// Sections before the first heading are returned as ungrouped.
private func buildCollapsibleGroups(from sections: [ResponseSection]) -> (ungrouped: [IndexedSection], groups: [CollapsibleGroup]) {
    var ungrouped: [IndexedSection] = []
    var groups: [CollapsibleGroup] = []
    var currentHeading: (text: String, level: Int, startIdx: Int)?
    var currentContent: [IndexedSection] = []

    for (idx, section) in sections.enumerated() {
        if case .heading(let text, let level) = section, level >= 2 && level <= 3 {
            // Flush previous group
            if let heading = currentHeading {
                groups.append(CollapsibleGroup(
                    id: heading.startIdx,
                    headingText: heading.text,
                    headingLevel: heading.level,
                    content: currentContent
                ))
            }
            currentHeading = (text, level, idx)
            currentContent = []
        } else if currentHeading != nil {
            currentContent.append(IndexedSection(id: idx, section: section))
        } else {
            ungrouped.append(IndexedSection(id: idx, section: section))
        }
    }
    // Flush last group
    if let heading = currentHeading {
        groups.append(CollapsibleGroup(
            id: heading.startIdx,
            headingText: heading.text,
            headingLevel: heading.level,
            content: currentContent
        ))
    }

    return (ungrouped, groups)
}

/// Counts words in a string (simple whitespace split).
private func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
}

/// Truncates text to approximately the given word count, breaking at a word boundary.
private func truncateToWords(_ text: String, maxWords: Int) -> String {
    let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    guard words.count > maxWords else { return text }
    return words.prefix(maxWords).joined(separator: " ")
}

/// Checks whether parsed sections contain only plain text (no headings).
private func isPlainTextOnly(_ sections: [ResponseSection]) -> Bool {
    for section in sections {
        switch section {
        case .heading: return false
        case .sectionCard: return false
        case .stepProgress: return false
        case .codeBlock: return false
        case .table: return false
        case .mathBlock: return false
        default: break
        }
    }
    return true
}

// MARK: - Response View

struct ResponseView: View {
    let text: String
    let isStreaming: Bool
    var zenMode: Bool = false
    /// Optional message ID used to build stable keys for per-section collapsed state.
    var messageId: String = ""
    @State private var cursorVisible = true
    @State private var highlightedFootnoteId: String?
    /// Tracks which collapsible groups (by group id) are collapsed.
    @State private var collapsedSections: Set<Int> = []
    /// Whether the initial auto-collapse has been applied.
    @State private var didAutoCollapse = false
    /// Whether long plain text is truncated.
    @State private var isTextTruncated = true

    var body: some View {
        let footnoteDefs = parseFootnoteDefinitions(from: text)
        let refOrder = footnoteReferenceOrder(from: text)
        let orderedDefs = footnoteDefs.map { def in
            FootnoteDefinition(
                id: def.id,
                displayIndex: refOrder[def.id] ?? def.displayIndex,
                text: def.text
            )
        }.sorted { $0.displayIndex < $1.displayIndex }
        let strippedText = footnoteDefs.isEmpty ? text : stripFootnoteDefinitions(from: text)
        let sections = ResponseParser.parse(strippedText)
        let result = buildCollapsibleGroups(from: sections)
        let headingCount = result.groups.count
        let useCollapsible = headingCount > 5 && !isStreaming
        let useTruncation = !useCollapsible && isPlainTextOnly(sections) && wordCount(text) > 500 && !isStreaming

        VStack(alignment: .leading, spacing: zenMode ? 14 : 10) {
            // Expand All / Collapse All controls for collapsible mode
            if useCollapsible {
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            collapsedSections.removeAll()
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 9))
                            Text("Expand All")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(collapsedSections.isEmpty ? AppTheme.textMuted.opacity(0.5) : AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.bgCard.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(collapsedSections.isEmpty)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            collapsedSections = Set(result.groups.map(\.id))
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9))
                            Text("Collapse All")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(collapsedSections.count == result.groups.count ? AppTheme.textMuted.opacity(0.5) : AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.bgCard.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.borderGlass, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(collapsedSections.count == result.groups.count)

                    Spacer()

                    Text("\(headingCount) sections")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textMuted)
                }
                .padding(.bottom, 4)
            }

            if useCollapsible {
                // Render ungrouped content before first heading
                ForEach(result.ungrouped) { indexed in
                    sectionView(indexed.section, refOrder: refOrder)
                }

                // Render collapsible groups
                ForEach(result.groups) { group in
                    collapsibleGroupView(group: group, refOrder: refOrder, isLast: group.id == result.groups.last?.id)
                }
            } else if useTruncation {
                // Long plain text with show more/less
                truncatedContentView(sections: sections, refOrder: refOrder)
            } else {
                // Default rendering: flat list of sections
                ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                    if isStreaming && idx == sections.count - 1 {
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            sectionView(section, refOrder: refOrder)
                            if cursorVisible {
                                Text("\u{258C}")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.accent)
                            }
                        }
                    } else {
                        sectionView(section, refOrder: refOrder)
                    }
                }
            }

            // Render footnote definitions section at the bottom
            if !orderedDefs.isEmpty {
                FootnoteSectionView(
                    definitions: orderedDefs,
                    highlightedFootnoteId: $highlightedFootnoteId
                )
            }
        }
        .onAppear {
            startCursorTimer()
            // Auto-collapse sections after the first 2 on first appearance
            if !didAutoCollapse && headingCount > 5 {
                let groupsToCollapse = result.groups.dropFirst(2).map(\.id)
                collapsedSections = Set(groupsToCollapse)
                didAutoCollapse = true
            }
        }
        .onChange(of: isStreaming) { streaming in
            if streaming { cursorVisible = true; startCursorTimer() }
        }
    }

    // MARK: - Collapsible Group View

    @ViewBuilder
    private func collapsibleGroupView(group: CollapsibleGroup, refOrder: [String: Int], isLast: Bool) -> some View {
        let isCollapsed = collapsedSections.contains(group.id)

        VStack(alignment: .leading, spacing: 0) {
            // Clickable heading toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isCollapsed {
                        collapsedSections.remove(group.id)
                    } else {
                        collapsedSections.insert(group.id)
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                    Text(group.headingText)
                        .font(.system(
                            size: group.headingLevel == 2 ? 17 : 15,
                            weight: group.headingLevel == 2 ? .semibold : .medium,
                            design: .rounded
                        ))
                        .foregroundColor(AppTheme.textPrimary)

                    Spacer()

                    if isCollapsed {
                        Text("\(group.content.count) items")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textMuted)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, group.headingLevel == 2 ? 6 : 4)
            .accessibilityLabel("\(group.headingText), \(isCollapsed ? "collapsed" : "expanded")")
            .accessibilityHint("Double tap to \(isCollapsed ? "expand" : "collapse") this section")

            // Section content with animated height
            if !isCollapsed {
                VStack(alignment: .leading, spacing: zenMode ? 14 : 10) {
                    ForEach(group.content) { indexed in
                        sectionView(indexed.section, refOrder: refOrder)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Truncated Content View (plain text >500 words)

    @ViewBuilder
    private func truncatedContentView(sections: [ResponseSection], refOrder: [String: Int]) -> some View {
        if isTextTruncated {
            // Show truncated version: approximately first 200 words
            let truncated = truncateToWords(text, maxWords: 200)
            let truncSections = ResponseParser.parse(truncated + "...")
            ForEach(Array(truncSections.enumerated()), id: \.offset) { _, section in
                sectionView(section, refOrder: refOrder)
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isTextTruncated = false
                }
            }) {
                HStack(spacing: 4) {
                    Text("Show more...")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppTheme.accent)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        } else {
            // Show full content
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionView(section, refOrder: refOrder)
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isTextTruncated = true
                }
            }) {
                HStack(spacing: 4) {
                    Text("Show less")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppTheme.accent)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
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
    private func sectionView(_ section: ResponseSection, refOrder: [String: Int] = [:]) -> some View {
        switch section {
        case .paragraph(let text):
            RichTextView(text: text, footnoteRefOrder: refOrder, highlightedFootnoteId: $highlightedFootnoteId)

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
            if lang.lowercased() == "mermaid", let mermaidGraph = MermaidParser.parse(code) {
                MermaidDiagramView(graph: mermaidGraph, code: code)
            } else {
                CodeBlockView(code: code, language: lang)
            }

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

        case .mathBlock(let latex):
            MathBlockView(latex: latex)
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

// MARK: - Code Execution Runner

@MainActor
final class CodeRunner: ObservableObject {
    @Published var isRunning = false
    @Published var output: String?
    @Published var hasError = false

    private var runTask: Task<Void, Never>?

    private static let supportedLanguages: Set<String> = [
        "bash", "sh", "zsh", "shell",
        "python", "python3", "py",
        "javascript", "js", "node"
    ]

    static func isRunnable(_ language: String) -> Bool {
        supportedLanguages.contains(language.lowercased())
    }

    func run(code: String, language: String) {
        guard !isRunning else { return }
        isRunning = true
        output = nil
        hasError = false

        runTask = Task {
            let result = await Self.execute(code: code, language: language)
            if !Task.isCancelled {
                self.output = result.output
                self.hasError = result.isError
                self.isRunning = false
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        isRunning = false
    }

    func clearOutput() {
        output = nil
        hasError = false
    }

    private static func execute(code: String, language: String) async -> (output: String, isError: Bool) {
        let lang = language.lowercased()
        let executable: String
        let arguments: [String]

        switch lang {
        case "bash", "sh", "zsh", "shell":
            executable = "/bin/zsh"
            arguments = ["-c", code]
        case "python", "python3", "py":
            executable = "/usr/bin/env"
            arguments = ["python3", "-c", code]
        case "javascript", "js", "node":
            executable = "/usr/bin/env"
            arguments = ["node", "-e", code]
        default:
            return ("Unsupported language: \(language)", true)
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                // Minimal environment for safety
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = NSHomeDirectory()
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Timeout timer
                let timeoutItem = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeoutItem)

                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutItem.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

                    let timedOut = process.terminationReason == .uncaughtSignal
                    let isError = process.terminationStatus != 0 || timedOut

                    var combined = ""
                    if !stdoutStr.isEmpty { combined += stdoutStr }
                    if !stderrStr.isEmpty {
                        if !combined.isEmpty { combined += "\n" }
                        combined += stderrStr
                    }
                    if timedOut {
                        if !combined.isEmpty { combined += "\n" }
                        combined += "[Timed out after 10 seconds]"
                    }
                    if combined.isEmpty { combined = "(no output)" }

                    continuation.resume(returning: (combined.trimmingCharacters(in: .whitespacesAndNewlines), isError))
                } catch {
                    timeoutItem.cancel()
                    continuation.resume(returning: ("Failed to run: \(error.localizedDescription)", true))
                }
            }
        }
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false
    @State private var isExpanded = true
    @State private var showRunConfirmation = false
    @StateObject private var runner = CodeRunner()
    @AppStorage("syntaxTheme") private var syntaxThemeName: String = "Monokai"
    @AppStorage("codeWordWrap") private var codeWordWrap: Bool = false
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("confirmCodeExecution") private var confirmCodeExecution: Bool = true

    private var currentTheme: SyntaxTheme { SyntaxTheme.named(syntaxThemeName) }
    private var lines: [String] { code.components(separatedBy: "\n") }
    private var lineCount: Int { lines.count }
    private var lineNumberWidth: CGFloat {
        let digits = max(2, String(lines.count).count)
        return CGFloat(digits) * 8 + 12
    }
    private var langColor: Color { SyntaxHighlighter.languageColor(for: language) }
    private var displayLang: String { language.isEmpty ? "code" : language.lowercased() }
    private var isRunnable: Bool { CodeRunner.isRunnable(language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top border accent line
            Rectangle()
                .fill(langColor.opacity(0.6))
                .frame(height: 2)

            // Header bar with language badge, line count, run, collapse toggle, and copy button
            HStack(spacing: 0) {
                // Language label (left)
                Text(displayLang)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Run button (only for supported languages)
                if isRunnable {
                    Button(action: {
                        if confirmCodeExecution {
                            showRunConfirmation = true
                        } else {
                            runner.run(code: code, language: language)
                        }
                    }) {
                        if runner.isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppTheme.success)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(AppTheme.success.opacity(0.12))
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(runner.isRunning)
                    .help("Run code")
                    .padding(.leading, 6)
                    .popover(isPresented: $showRunConfirmation, arrowEdge: .bottom) {
                        VStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppTheme.warning)
                                    .font(.system(size: 14))
                                Text("Run this code?")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                            }

                            Text("This will execute the code on your machine.")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 8) {
                                Button("Cancel") {
                                    showRunConfirmation = false
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.08))
                                )

                                Button("Run") {
                                    showRunConfirmation = false
                                    runner.run(code: code, language: language)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(AppTheme.success)
                                )
                            }
                        }
                        .padding(14)
                        .background(AppTheme.bgCard)
                    }
                }

                Spacer()

                // Line count (center)
                Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)

                Spacer()

                // Word wrap toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        codeWordWrap.toggle()
                    }
                }) {
                    Image(systemName: codeWordWrap ? "text.word.spacing" : "arrow.left.and.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(codeWordWrap ? AppTheme.accent : AppTheme.textMuted)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(codeWordWrap ? AppTheme.accent.opacity(0.12) : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .help(codeWordWrap ? "Disable word wrap" : "Enable word wrap")
                .padding(.trailing, 4)

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
                codeContentView
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

            // Output section
            if runner.isRunning || runner.output != nil {
                codeOutputView
            }
        }
        .background(currentTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayLang) code block, \(lineCount) line\(lineCount == 1 ? "" : "s")")
        .accessibilityHint("Right-click or use actions to copy code")
        .accessibilityAction(named: "Copy code") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        }
    }

    // MARK: - Output View

    @ViewBuilder
    private var codeOutputView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Output header
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.textMuted)
                Text("Output")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.textMuted)

                if runner.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                }

                Spacer()

                if runner.output != nil {
                    // Copy output
                    Button(action: {
                        if let out = runner.output {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(out, forType: .string)
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Copy output")

                    // Clear output
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            runner.clearOutput()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.textMuted)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Clear output")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.25))

            // Output content
            if let output = runner.output {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(output)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(runner.hasError ? AppTheme.error : Color(red: 0.7, green: 0.9, blue: 0.7))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                .background(Color.black.opacity(0.35))
            } else if runner.isRunning {
                HStack(spacing: 6) {
                    Text("Running...")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.35))
            }
        }
    }

    // MARK: - Code Content (word wrap aware)

    @ViewBuilder
    private var codeContentView: some View {
        if codeWordWrap {
            // Word-wrapped mode: no horizontal scroll
            HStack(alignment: .top, spacing: 0) {
                if showLineNumbers {
                    lineNumbersColumn
                    lineNumberSeparator
                }

                Text(SyntaxHighlighter.highlight(code, language: language, theme: currentTheme))
                    .textSelection(.enabled)
                    .lineSpacing(0)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.trailing, 10)
            }
            .padding(.vertical, 10)
        } else {
            // Horizontal scroll mode (default)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    if showLineNumbers {
                        lineNumbersColumn
                        lineNumberSeparator
                    }

                    Text(SyntaxHighlighter.highlight(code, language: language, theme: currentTheme))
                        .textSelection(.enabled)
                        .lineSpacing(0)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: CGFloat(lines.count) * 18, alignment: .topLeading)
                }
                .padding(.vertical, 10)
                .padding(.trailing, 10)
            }
        }
    }

    private var lineNumbersColumn: some View {
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
    }

    private var lineNumberSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1)
            .padding(.trailing, 10)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Working on tasks")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                TypingIndicator()
                Text("Agent is thinking...")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textMuted)
            }
            .transition(.opacity.animation(.easeOut(duration: 0.25)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Agent is thinking")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool call: \(name)")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(expanded ? "collapse" : "expand") result")
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
    case mathBlock(String) // Display math: $$...$$ or \[...\]
}

// MARK: - LaTeX Math Rendering

/// Substitutes common LaTeX commands with Unicode equivalents.
struct LaTeXRenderer {

    /// All symbol replacements, applied in order.
    private static let symbolMap: [(String, String)] = [
        ("\\alpha", "\u{03B1}"),
        ("\\beta", "\u{03B2}"),
        ("\\gamma", "\u{03B3}"),
        ("\\delta", "\u{03B4}"),
        ("\\pi", "\u{03C0}"),
        ("\\theta", "\u{03B8}"),
        ("\\sum", "\u{03A3}"),
        ("\\prod", "\u{03A0}"),
        ("\\int", "\u{222B}"),
        ("\\infty", "\u{221E}"),
        ("\\sqrt", "\u{221A}"),
        ("\\pm", "\u{00B1}"),
        ("\\leq", "\u{2264}"),
        ("\\geq", "\u{2265}"),
        ("\\neq", "\u{2260}"),
        ("\\approx", "\u{2248}"),
        ("\\times", "\u{00D7}"),
        ("\\div", "\u{00F7}"),
        ("\\in", "\u{2208}"),
        ("\\subset", "\u{2282}"),
        ("\\cup", "\u{222A}"),
        ("\\cap", "\u{2229}"),
    ]

    /// Unicode superscript digit mapping
    private static let superscriptDigits: [Character: Character] = [
        "0": "\u{2070}", "1": "\u{00B9}", "2": "\u{00B2}", "3": "\u{00B3}",
        "4": "\u{2074}", "5": "\u{2075}", "6": "\u{2076}", "7": "\u{2077}",
        "8": "\u{2078}", "9": "\u{2079}", "+": "\u{207A}", "-": "\u{207B}",
        "=": "\u{207C}", "(": "\u{207D}", ")": "\u{207E}", "n": "\u{207F}",
        "i": "\u{2071}",
    ]

    /// Unicode subscript digit mapping
    private static let subscriptDigits: [Character: Character] = [
        "0": "\u{2080}", "1": "\u{2081}", "2": "\u{2082}", "3": "\u{2083}",
        "4": "\u{2084}", "5": "\u{2085}", "6": "\u{2086}", "7": "\u{2087}",
        "8": "\u{2088}", "9": "\u{2089}", "+": "\u{208A}", "-": "\u{208B}",
        "=": "\u{208C}", "(": "\u{208D}", ")": "\u{208E}",
        "a": "\u{2090}", "e": "\u{2091}", "o": "\u{2092}", "x": "\u{2093}",
    ]

    /// Render a LaTeX math string into a displayable Unicode string.
    static func render(_ latex: String) -> String {
        var result = latex.trimmingCharacters(in: .whitespacesAndNewlines)

        // \frac{a}{b} -> a/b
        if let fracRegex = try? NSRegularExpression(pattern: #"\\frac\{([^}]*)\}\{([^}]*)\}"#, options: []) {
            var nsResult = result as NSString
            var offset = 0
            let matches = fracRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches {
                let num = nsResult.substring(with: NSRange(location: match.range(at: 1).location + offset, length: match.range(at: 1).length))
                let den = nsResult.substring(with: NSRange(location: match.range(at: 2).location + offset, length: match.range(at: 2).length))
                let replacement = "\(num)/\(den)"
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                nsResult = nsResult.replacingCharacters(in: adjustedRange, with: replacement) as NSString
                offset += replacement.count - match.range.length
            }
            result = nsResult as String
        }

        // Apply symbol substitutions
        for (cmd, symbol) in symbolMap {
            result = result.replacingOccurrences(of: cmd, with: symbol)
        }

        // ^{...} -> superscript
        if let supRegex = try? NSRegularExpression(pattern: #"\^\{([^}]*)\}"#, options: []) {
            var nsResult = result as NSString
            var offset = 0
            let matches = supRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches {
                let inner = nsResult.substring(with: NSRange(location: match.range(at: 1).location + offset, length: match.range(at: 1).length))
                let sup = String(inner.map { superscriptDigits[$0] ?? $0 })
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                nsResult = nsResult.replacingCharacters(in: adjustedRange, with: sup) as NSString
                offset += sup.count - match.range.length
            }
            result = nsResult as String
        }

        // Single char superscript: ^x where x is a single char (not {)
        if let supSingleRegex = try? NSRegularExpression(pattern: #"\^([^{\s])"#, options: []) {
            var nsResult = result as NSString
            var offset = 0
            let matches = supSingleRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches {
                let inner = nsResult.substring(with: NSRange(location: match.range(at: 1).location + offset, length: match.range(at: 1).length))
                let ch = inner.first ?? Character(" ")
                let sup = String(superscriptDigits[ch] ?? ch)
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                nsResult = nsResult.replacingCharacters(in: adjustedRange, with: sup) as NSString
                offset += sup.count - match.range.length
            }
            result = nsResult as String
        }

        // _{...} -> subscript
        if let subRegex = try? NSRegularExpression(pattern: #"_\{([^}]*)\}"#, options: []) {
            var nsResult = result as NSString
            var offset = 0
            let matches = subRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches {
                let inner = nsResult.substring(with: NSRange(location: match.range(at: 1).location + offset, length: match.range(at: 1).length))
                let sub = String(inner.map { subscriptDigits[$0] ?? $0 })
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                nsResult = nsResult.replacingCharacters(in: adjustedRange, with: sub) as NSString
                offset += sub.count - match.range.length
            }
            result = nsResult as String
        }

        // Single char subscript: _x where x is a single char (not {)
        if let subSingleRegex = try? NSRegularExpression(pattern: #"_([^{\s])"#, options: []) {
            var nsResult = result as NSString
            var offset = 0
            let matches = subSingleRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches {
                let inner = nsResult.substring(with: NSRange(location: match.range(at: 1).location + offset, length: match.range(at: 1).length))
                let ch = inner.first ?? Character(" ")
                let sub = String(subscriptDigits[ch] ?? ch)
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)
                nsResult = nsResult.replacingCharacters(in: adjustedRange, with: sub) as NSString
                offset += sub.count - match.range.length
            }
            result = nsResult as String
        }

        // Clean up remaining braces
        result = result.replacingOccurrences(of: "\\left", with: "")
        result = result.replacingOccurrences(of: "\\right", with: "")
        result = result.replacingOccurrences(of: "\\,", with: " ")
        result = result.replacingOccurrences(of: "\\;", with: " ")
        result = result.replacingOccurrences(of: "\\quad", with: "  ")
        result = result.replacingOccurrences(of: "\\qquad", with: "    ")
        result = result.replacingOccurrences(of: "\\\\", with: "\n")
        result = result.replacingOccurrences(of: "\\text{", with: "").replacingOccurrences(of: "}", with: "")

        return result
    }

    /// Checks whether a string contains inline math delimiters.
    static func containsInlineMath(_ text: String) -> Bool {
        // $...$ (single dollar, not $$)
        if let regex = try? NSRegularExpression(pattern: #"(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil { return true }
        }
        // \(...\)
        if text.contains("\\(") && text.contains("\\)") { return true }
        return false
    }

    /// Splits text into segments of plain text and inline math.
    static func splitInlineMath(_ text: String) -> [InlineMathSegment] {
        var segments: [InlineMathSegment] = []
        let nsText = text as NSString

        // Combined pattern for $...$ and \(...\)
        // $...$ : single dollar not preceded/followed by $
        // \(...\) : literal backslash parens
        let patterns = [
            #"(?<!\$)\$(?!\$)((?:[^$\\]|\\.)+?)(?<!\$)\$(?!\$)"#,
            #"\\\((.+?)\\\)"#
        ]

        // Collect all math ranges
        struct MathRange {
            let fullRange: NSRange
            let innerRange: NSRange
        }
        var mathRanges: [MathRange] = []

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: nsText.length)
                for match in regex.matches(in: text, range: range) {
                    mathRanges.append(MathRange(fullRange: match.range, innerRange: match.range(at: 1)))
                }
            }
        }

        // Sort by location
        mathRanges.sort { $0.fullRange.location < $1.fullRange.location }

        // Remove overlapping ranges
        var filtered: [MathRange] = []
        var lastEnd = 0
        for mr in mathRanges {
            if mr.fullRange.location >= lastEnd {
                filtered.append(mr)
                lastEnd = mr.fullRange.location + mr.fullRange.length
            }
        }

        // Build segments
        var pos = 0
        for mr in filtered {
            if mr.fullRange.location > pos {
                let plain = nsText.substring(with: NSRange(location: pos, length: mr.fullRange.location - pos))
                if !plain.isEmpty { segments.append(.text(plain)) }
            }
            let inner = nsText.substring(with: mr.innerRange)
            segments.append(.math(inner))
            pos = mr.fullRange.location + mr.fullRange.length
        }
        if pos < nsText.length {
            let remaining = nsText.substring(from: pos)
            if !remaining.isEmpty { segments.append(.text(remaining)) }
        }

        return segments
    }
}

/// Segment type for inline math splitting.
enum InlineMathSegment {
    case text(String)
    case math(String)
}

// MARK: - Display Math Block View

struct MathBlockView: View {
    let latex: String
    @State private var copied = false

    private var rendered: String {
        LaTeXRenderer.render(latex)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // Rendered math content
            Text(rendered)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundColor(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)

            // Bottom bar with Copy LaTeX button
            HStack {
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(latex, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(copied ? "Copied" : "Copy LaTeX")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(copied ? AppTheme.success : AppTheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                .fill(AppTheme.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                .stroke(AppTheme.borderGlass, lineWidth: 0.5)
        )
    }
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

            // Display math blocks: $$ ... $$ (may span multiple lines)
            if trimmed.hasPrefix("$$") {
                // Check for single-line $$...$$ (content between $$ on same line)
                let afterOpen = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if afterOpen.hasSuffix("$$") && afterOpen.count > 2 {
                    let inner = String(afterOpen.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    if !inner.isEmpty {
                        sections.append(.mathBlock(inner))
                        i += 1
                        continue
                    }
                }
                // Multi-line $$...$$
                var mathLines: [String] = []
                if afterOpen.isEmpty || afterOpen == "$$" {
                    i += 1
                } else {
                    mathLines.append(afterOpen)
                    i += 1
                }
                var foundClose = false
                while i < lines.count {
                    let ml = lines[i]
                    let mlt = ml.trimmingCharacters(in: .whitespaces)
                    if mlt.hasSuffix("$$") {
                        let before = String(mlt.dropLast(2)).trimmingCharacters(in: .whitespaces)
                        if !before.isEmpty { mathLines.append(before) }
                        foundClose = true
                        i += 1
                        break
                    }
                    mathLines.append(ml)
                    i += 1
                }
                let mathContent = mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !mathContent.isEmpty {
                    sections.append(.mathBlock(mathContent))
                } else {
                    sections.append(.paragraph(trimmed))
                }
                if !foundClose && i < lines.count { /* unclosed, we consumed what we could */ }
                continue
            }

            // Display math blocks: \[ ... \]
            if trimmed.hasPrefix("\\[") {
                let afterOpen = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if afterOpen.hasSuffix("\\]") && afterOpen.count > 2 {
                    let inner = String(afterOpen.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    if !inner.isEmpty {
                        sections.append(.mathBlock(inner))
                        i += 1
                        continue
                    }
                }
                var mathLines: [String] = []
                if afterOpen.isEmpty {
                    i += 1
                } else {
                    mathLines.append(afterOpen)
                    i += 1
                }
                var foundClose = false
                while i < lines.count {
                    let ml = lines[i]
                    let mlt = ml.trimmingCharacters(in: .whitespaces)
                    if mlt.hasSuffix("\\]") {
                        let before = String(mlt.dropLast(2)).trimmingCharacters(in: .whitespaces)
                        if !before.isEmpty { mathLines.append(before) }
                        foundClose = true
                        i += 1
                        break
                    }
                    mathLines.append(ml)
                    i += 1
                }
                let mathContent = mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !mathContent.isEmpty {
                    sections.append(.mathBlock(mathContent))
                } else {
                    sections.append(.paragraph(trimmed))
                }
                if !foundClose && i < lines.count { /* unclosed */ }
                continue
            }

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
    var footnoteRefOrder: [String: Int] = [:]
    @Binding var highlightedFootnoteId: String?
    @Environment(\.zenMode) private var zenMode

    /// Convenience initializer without footnote support (backwards compatible)
    init(text: String) {
        self.text = text
        self.footnoteRefOrder = [:]
        self._highlightedFootnoteId = .constant(nil)
    }

    /// Initializer with footnote support
    init(text: String, footnoteRefOrder: [String: Int], highlightedFootnoteId: Binding<String?>) {
        self.text = text
        self.footnoteRefOrder = footnoteRefOrder
        self._highlightedFootnoteId = highlightedFootnoteId
    }

    var body: some View {
        let parts = splitByPaths(text)
        // Use a FlowLayout-like approach: if there are paths, render mixed
        if parts.count == 1, case .plain(let str) = parts[0] {
            // Simple text — render with inline code highlighting and footnotes
            footnoteAwareText(str)
        } else {
            // Has paths — render inline
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .plain(let str):
                        footnoteAwareText(str)
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

    /// Splits text on footnote references [^key] and renders them as superscript numbers.
    /// Falls through to inlineMarkdownText for non-footnote segments.
    @ViewBuilder
    private func footnoteAwareText(_ str: String) -> some View {
        if footnoteRefOrder.isEmpty || !str.contains("[^") {
            inlineMarkdownText(str)
        } else {
            let segments = splitFootnoteReferences(str)
            if segments.count == 1, case .text(let t) = segments[0] {
                inlineMarkdownText(t)
            } else {
                // Build a single AttributedString with footnote superscripts inline
                let combined = segments.reduce(AttributedString()) { result, segment in
                    var combined = result
                    switch segment {
                    case .text(let t):
                        let attributed = Self.buildAttributedText(t, bodySize: bodyFontSize, codeSize: codeInlineFontSize)
                        combined.append(attributed)
                    case .footnoteRef(let key):
                        let displayNum = footnoteRefOrder[key] ?? 0
                        if displayNum > 0 {
                            var sup = AttributedString("\u{200A}\(displayNum)")
                            sup.font = .system(size: 9, weight: .bold, design: .monospaced)
                            sup.foregroundColor = AppTheme.accent
                            sup.baselineOffset = 6
                            combined.append(sup)
                        } else {
                            var raw = AttributedString("[^\(key)]")
                            raw.font = .system(size: bodyFontSize)
                            raw.foregroundColor = AppTheme.textSecondary
                            combined.append(raw)
                        }
                    }
                    return combined
                }
                Text(combined)
                    .lineSpacing(lineSpacingValue)
                    .textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
            }
        }
    }

    /// Segment type for footnote-aware text splitting
    private enum FootnoteSegment {
        case text(String)
        case footnoteRef(String) // The key, e.g. "1", "note"
    }

    /// Splits text into alternating plain text and footnote reference segments.
    private func splitFootnoteReferences(_ text: String) -> [FootnoteSegment] {
        let pattern = #"\[\^([^\]]+)\](?!:)"# // Match [^key] but not [^key]: (definitions)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.text(text)]
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)
        if matches.isEmpty { return [.text(text)] }

        var segments: [FootnoteSegment] = []
        var lastEnd = 0
        for match in matches {
            if match.range.location > lastEnd {
                let before = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                if !before.isEmpty { segments.append(.text(before)) }
            }
            if match.numberOfRanges >= 2 {
                let key = nsText.substring(with: match.range(at: 1))
                segments.append(.footnoteRef(key))
            }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd)
            if !remaining.isEmpty { segments.append(.text(remaining)) }
        }
        return segments
    }

    /// Renders text with AttributedString markdown, inline code highlighting, and inline math.
    @ViewBuilder
    private func inlineMarkdownText(_ str: String) -> some View {
        if LaTeXRenderer.containsInlineMath(str) {
            // Render with inline math support
            let mathSegments = LaTeXRenderer.splitInlineMath(str)
            let combined = mathSegments.reduce(AttributedString()) { result, segment in
                var combined = result
                switch segment {
                case .text(let t):
                    // Process the text part normally (with inline code if present)
                    let attributed = Self.buildAttributedText(t, bodySize: bodyFontSize, codeSize: codeInlineFontSize)
                    combined.append(attributed)
                case .math(let m):
                    let rendered = LaTeXRenderer.render(m)
                    var space = AttributedString("\u{200A}")
                    space.font = .system(size: 2)
                    combined.append(space)
                    var attr = AttributedString(rendered)
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
        } else if str.contains("`") {
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

    /// Builds an AttributedString from text that may contain inline code backticks.
    private static func buildAttributedText(_ str: String, bodySize: CGFloat, codeSize: CGFloat) -> AttributedString {
        if str.contains("`") {
            var result = AttributedString()
            var current = ""
            var inCode = false
            var i = str.startIndex
            while i < str.endIndex {
                let ch = str[i]
                if ch == "`" {
                    if inCode {
                        if !current.isEmpty {
                            var attr = AttributedString(current)
                            attr.font = .system(size: codeSize, design: .monospaced)
                            attr.foregroundColor = AppTheme.accent
                            attr.backgroundColor = AppTheme.bgCard
                            var space = AttributedString("\u{200A}")
                            space.font = .system(size: 2)
                            result.append(space)
                            result.append(attr)
                            result.append(space)
                        }
                        current = ""
                        inCode = false
                    } else {
                        if !current.isEmpty {
                            if var attr = try? AttributedString(markdown: current, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                                attr.font = .system(size: bodySize)
                                styleLinks(&attr)
                                result.append(attr)
                            } else {
                                var attr = AttributedString(current)
                                attr.font = .system(size: bodySize)
                                attr.foregroundColor = AppTheme.textPrimary
                                result.append(attr)
                            }
                        }
                        current = ""
                        inCode = true
                    }
                } else {
                    current.append(ch)
                }
                i = str.index(after: i)
            }
            if !current.isEmpty {
                if inCode {
                    // Unclosed backtick
                    if var attr = try? AttributedString(markdown: "`" + current, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        attr.font = .system(size: bodySize)
                        styleLinks(&attr)
                        result.append(attr)
                    } else {
                        var attr = AttributedString("`" + current)
                        attr.font = .system(size: bodySize)
                        attr.foregroundColor = AppTheme.textPrimary
                        result.append(attr)
                    }
                } else {
                    if var attr = try? AttributedString(markdown: current, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        attr.font = .system(size: bodySize)
                        styleLinks(&attr)
                        result.append(attr)
                    } else {
                        var attr = AttributedString(current)
                        attr.font = .system(size: bodySize)
                        attr.foregroundColor = AppTheme.textPrimary
                        result.append(attr)
                    }
                }
            }
            return result
        } else {
            if var attr = try? AttributedString(markdown: str, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                attr.font = .system(size: bodySize)
                styleLinks(&attr)
                return attr
            } else {
                var attr = AttributedString(str)
                attr.font = .system(size: bodySize)
                attr.foregroundColor = AppTheme.textPrimary
                return attr
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

// MARK: - Mermaid Diagram Support

/// Shape classification for Mermaid flowchart nodes.
enum MermaidNodeShape {
    case rectangle   // A[label]
    case decision    // A{label}
    case rounded     // A(label)
    case stadium     // A([label])
    case defaultRect // bare A
}

/// A single node in a Mermaid flowchart.
struct MermaidNode: Identifiable {
    let id: String
    var label: String
    var shape: MermaidNodeShape
}

/// A directed edge between two Mermaid nodes.
struct MermaidEdge: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    var label: String?
}

/// Direction of the flowchart layout.
enum MermaidDirection {
    case topDown  // TD / TB
    case leftRight // LR
}

/// Parsed Mermaid flowchart graph.
struct MermaidGraph {
    var direction: MermaidDirection = .topDown
    var nodes: [MermaidNode] = []
    var edges: [MermaidEdge] = []

    /// Look up a node by id.
    func node(by id: String) -> MermaidNode? {
        nodes.first { $0.id == id }
    }
}

/// Parses a subset of Mermaid flowchart syntax into a `MermaidGraph`.
struct MermaidParser {
    /// Attempt to parse a mermaid code string. Returns nil if not a flowchart or parsing fails.
    static func parse(_ code: String) -> MermaidGraph? {
        let lines = code.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

        guard let firstLine = lines.first else { return nil }

        // Must start with graph or flowchart
        let header = firstLine.lowercased()
        guard header.hasPrefix("graph") || header.hasPrefix("flowchart") else { return nil }

        var graph = MermaidGraph()

        // Parse direction
        let parts = firstLine.split(separator: " ", maxSplits: 2).map { String($0) }
        if parts.count >= 2 {
            let dir = parts[1].uppercased()
            switch dir {
            case "LR", "RL": graph.direction = .leftRight
            default: graph.direction = .topDown
            }
        }

        var nodeMap: [String: MermaidNode] = [:]

        /// Ensures a node exists in the map and returns it.
        func ensureNode(_ id: String, label: String? = nil, shape: MermaidNodeShape? = nil) {
            if var existing = nodeMap[id] {
                if let label = label { existing.label = label }
                if let shape = shape { existing.shape = shape }
                nodeMap[id] = existing
            } else {
                nodeMap[id] = MermaidNode(
                    id: id,
                    label: label ?? id,
                    shape: shape ?? .defaultRect
                )
            }
        }

        /// Parse a node reference like A, A[text], A{text}, A(text), A([text])
        func parseNodeRef(_ raw: String) -> (id: String, label: String?, shape: MermaidNodeShape?)? {
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }

            // A{label} - decision
            if let openIdx = s.firstIndex(of: "{"), s.last == "}" {
                let id = String(s[s.startIndex..<openIdx])
                let label = String(s[s.index(after: openIdx)..<s.index(before: s.endIndex)])
                return (id, label, .decision)
            }
            // A([label]) - stadium
            if let openIdx = s.firstIndex(of: "("), s.hasSuffix(")") {
                let id = String(s[s.startIndex..<openIdx])
                var inner = String(s[s.index(after: openIdx)..<s.index(before: s.endIndex)])
                var shape: MermaidNodeShape = .rounded
                if inner.hasPrefix("[") && inner.hasSuffix("]") {
                    inner = String(inner.dropFirst().dropLast())
                    shape = .stadium
                }
                return (id, inner, shape)
            }
            // A[label] - rectangle
            if let openIdx = s.firstIndex(of: "["), s.last == "]" {
                let id = String(s[s.startIndex..<openIdx])
                let label = String(s[s.index(after: openIdx)..<s.index(before: s.endIndex)])
                return (id, label, .rectangle)
            }
            // Bare id
            let id = s.components(separatedBy: .whitespaces).first ?? s
            guard !id.isEmpty else { return nil }
            return (id, nil, nil)
        }

        // Edge patterns: -->, --->, --, ---|text|, -->|text|
        // We split lines by common arrow patterns
        let arrowPattern = #"(-->|---|-\.-?>?|==>)"#
        let labelOnArrow = #"\|([^|]*)\|"#

        for lineIdx in 1..<lines.count {
            let line = lines[lineIdx]
            // Skip subgraph, end, style, class directives
            let lower = line.lowercased()
            if lower.hasPrefix("subgraph") || lower == "end" || lower.hasPrefix("style") ||
               lower.hasPrefix("class ") || lower.hasPrefix("click ") { continue }

            // Try to split by arrow
            guard let arrowRegex = try? NSRegularExpression(pattern: arrowPattern, options: []) else { continue }
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let arrowMatches = arrowRegex.matches(in: line, range: range)

            if arrowMatches.isEmpty {
                // Standalone node definition
                if let ref = parseNodeRef(line) {
                    ensureNode(ref.id, label: ref.label, shape: ref.shape)
                }
                continue
            }

            // Split the line around arrows
            var segments: [String] = []
            var arrowLabels: [String?] = []
            var lastEnd = 0
            for match in arrowMatches {
                let seg = nsLine.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                segments.append(seg.trimmingCharacters(in: .whitespaces))
                lastEnd = match.range.location + match.range.length

                // Check for label on arrow: -->|text| or ---|text|
                let afterArrow = nsLine.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
                if let labelRegex = try? NSRegularExpression(pattern: #"^\|([^|]*)\|"#, options: []),
                   let labelMatch = labelRegex.firstMatch(in: afterArrow, range: NSRange(location: 0, length: (afterArrow as NSString).length)) {
                    let lbl = (afterArrow as NSString).substring(with: labelMatch.range(at: 1))
                    arrowLabels.append(lbl)
                    lastEnd += labelMatch.range.length
                } else {
                    arrowLabels.append(nil)
                }
            }
            // Remaining text after last arrow
            let remaining = nsLine.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
            if !remaining.isEmpty {
                segments.append(remaining)
            }

            // Build nodes and edges from segments
            var nodeIds: [String] = []
            for seg in segments {
                if let ref = parseNodeRef(seg) {
                    ensureNode(ref.id, label: ref.label, shape: ref.shape)
                    nodeIds.append(ref.id)
                }
            }

            for j in 0..<(nodeIds.count - 1) {
                let edgeLabel = j < arrowLabels.count ? arrowLabels[j] : nil
                graph.edges.append(MermaidEdge(from: nodeIds[j], to: nodeIds[j + 1], label: edgeLabel))
            }
        }

        // Preserve insertion order
        graph.nodes = Array(nodeMap.values).sorted { a, b in
            let aIdx = lines.joined().range(of: a.id)?.lowerBound ?? lines.joined().endIndex
            let bIdx = lines.joined().range(of: b.id)?.lowerBound ?? lines.joined().endIndex
            return aIdx < bIdx
        }

        guard !graph.nodes.isEmpty else { return nil }
        return graph
    }
}

/// Renders a parsed MermaidGraph as a SwiftUI diagram.
struct MermaidDiagramView: View {
    let graph: MermaidGraph
    let code: String
    @State private var showCode = false

    private let nodeWidth: CGFloat = 120
    private let nodeHeight: CGFloat = 44
    private let decisionSize: CGFloat = 60
    private let hSpacing: CGFloat = 40
    private let vSpacing: CGFloat = 36

    /// Compute position for each node based on graph direction and simple sequential layout.
    private var nodePositions: [String: CGPoint] {
        var positions: [String: CGPoint] = [:]

        // Build a simple layered layout using topological ordering
        // Layer 0 = nodes with no incoming edges, etc.
        var inDegree: [String: Int] = [:]
        var outNeighbors: [String: [String]] = [:]
        for node in graph.nodes {
            inDegree[node.id] = 0
            outNeighbors[node.id] = []
        }
        for edge in graph.edges {
            inDegree[edge.to, default: 0] += 1
            outNeighbors[edge.from, default: []].append(edge.to)
        }

        // BFS layering
        var layers: [[String]] = []
        var assigned = Set<String>()
        var queue = graph.nodes.filter { inDegree[$0.id, default: 0] == 0 }.map { $0.id }
        if queue.isEmpty {
            // Fallback: just use first node
            queue = [graph.nodes[0].id]
        }

        while !queue.isEmpty {
            layers.append(queue)
            assigned.formUnion(queue)
            var next: [String] = []
            for nodeId in queue {
                for neighbor in outNeighbors[nodeId, default: []] {
                    if !assigned.contains(neighbor) && !next.contains(neighbor) {
                        // Check all incoming edges are from assigned nodes
                        let allIncoming = graph.edges.filter { $0.to == neighbor }.map { $0.from }
                        if allIncoming.allSatisfy({ assigned.contains($0) || queue.contains($0) }) {
                            next.append(neighbor)
                        }
                    }
                }
            }
            // If no progress, add remaining unassigned nodes
            if next.isEmpty {
                let remaining = graph.nodes.filter { !assigned.contains($0.id) }.map { $0.id }
                if remaining.isEmpty { break }
                next = [remaining[0]]
            }
            queue = next
        }

        // Add any remaining nodes
        let unassigned = graph.nodes.filter { !assigned.contains($0.id) }.map { $0.id }
        if !unassigned.isEmpty { layers.append(unassigned) }

        let isHorizontal = graph.direction == .leftRight

        for (layerIdx, layer) in layers.enumerated() {
            for (nodeIdx, nodeId) in layer.enumerated() {
                let layerOffset = CGFloat(layerIdx) * (isHorizontal ? (nodeWidth + hSpacing) : (nodeHeight + vSpacing))
                let nodeOffset = CGFloat(nodeIdx) * (isHorizontal ? (nodeHeight + vSpacing) : (nodeWidth + hSpacing))

                // Center the layer
                let layerWidth = CGFloat(layer.count) * (isHorizontal ? (nodeHeight + vSpacing) : (nodeWidth + hSpacing)) - (isHorizontal ? vSpacing : hSpacing)
                let centering = -layerWidth / 2 + (isHorizontal ? (nodeHeight + vSpacing) : (nodeWidth + hSpacing)) / 2

                if isHorizontal {
                    positions[nodeId] = CGPoint(
                        x: layerOffset + nodeWidth / 2,
                        y: nodeOffset + centering
                    )
                } else {
                    positions[nodeId] = CGPoint(
                        x: nodeOffset + centering,
                        y: layerOffset + nodeHeight / 2
                    )
                }
            }
        }

        return positions
    }

    /// Canvas size needed to contain all nodes.
    private var canvasSize: CGSize {
        let positions = nodePositions
        guard !positions.isEmpty else { return CGSize(width: 200, height: 100) }
        let xs = positions.values.map { $0.x }
        let ys = positions.values.map { $0.y }
        let minX = (xs.min() ?? 0) - nodeWidth / 2
        let maxX = (xs.max() ?? 0) + nodeWidth / 2
        let minY = (ys.min() ?? 0) - nodeHeight / 2
        let maxY = (ys.max() ?? 0) + nodeHeight / 2
        return CGSize(
            width: maxX - minX + 40,
            height: maxY - minY + 40
        )
    }

    /// Offset to apply so all positions are positive with padding.
    private var canvasOffset: CGPoint {
        let positions = nodePositions
        let xs = positions.values.map { $0.x }
        let ys = positions.values.map { $0.y }
        return CGPoint(
            x: -(xs.min() ?? 0) + nodeWidth / 2 + 20,
            y: -(ys.min() ?? 0) + nodeHeight / 2 + 20
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with toggle
            HStack {
                Image(systemName: "flowchart")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                Text("Flowchart")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Button(action: { showCode.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showCode ? "eye" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10, weight: .medium))
                        Text(showCode ? "View Diagram" : "View as Code")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.bgSecondary.opacity(0.5))

            if showCode {
                // Raw code view
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(AppTheme.fontMono)
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(12)
                }
            } else {
                // Diagram view
                let positions = nodePositions
                let offset = canvasOffset
                let size = canvasSize

                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Draw edges first (below nodes)
                        ForEach(graph.edges) { edge in
                            if let fromPos = positions[edge.from],
                               let toPos = positions[edge.to] {
                                MermaidEdgeView(
                                    from: CGPoint(x: fromPos.x + offset.x, y: fromPos.y + offset.y),
                                    to: CGPoint(x: toPos.x + offset.x, y: toPos.y + offset.y),
                                    label: edge.label,
                                    nodeWidth: nodeWidth,
                                    nodeHeight: nodeHeight,
                                    direction: graph.direction
                                )
                            }
                        }
                        // Draw nodes
                        ForEach(graph.nodes) { node in
                            if let pos = positions[node.id] {
                                MermaidNodeView(node: node, width: nodeWidth, height: nodeHeight)
                                    .position(x: pos.x + offset.x, y: pos.y + offset.y)
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
                .frame(maxHeight: min(size.height, 400))
            }
        }
        .background(AppTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSm)
                .stroke(AppTheme.borderGlass, lineWidth: 0.5)
        )
    }
}

/// Renders a single Mermaid node as a SwiftUI shape.
private struct MermaidNodeView: View {
    let node: MermaidNode
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            switch node.shape {
            case .decision:
                // Diamond shape
                Diamond()
                    .fill(AppTheme.bgCard)
                Diamond()
                    .stroke(AppTheme.accent, lineWidth: 1.5)
            case .rounded, .stadium:
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(AppTheme.bgCard)
                RoundedRectangle(cornerRadius: height / 2)
                    .stroke(AppTheme.accent, lineWidth: 1.5)
            default:
                // Rectangle with rounded corners
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.bgCard)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.accent, lineWidth: 1.5)
            }

            Text(node.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(width: node.shape == .decision ? width : width, height: height)
    }
}

/// Diamond shape for decision nodes.
private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Renders an edge (arrow) between two node positions.
private struct MermaidEdgeView: View {
    let from: CGPoint
    let to: CGPoint
    let label: String?
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let direction: MermaidDirection

    var body: some View {
        ZStack {
            // Arrow line with arrowhead
            ArrowLine(from: adjustedFrom, to: adjustedTo)
                .stroke(AppTheme.accent.opacity(0.6), lineWidth: 1.2)

            // Arrowhead
            ArrowHead(at: adjustedTo, from: adjustedFrom)
                .fill(AppTheme.accent.opacity(0.6))

            // Edge label
            if let label = label, !label.isEmpty {
                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(AppTheme.bgCard.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: mid.x, y: mid.y)
            }
        }
    }

    /// Adjust start point to edge of source node.
    private var adjustedFrom: CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return from }
        let offsetX = (dx / len) * (nodeWidth / 2)
        let offsetY = (dy / len) * (nodeHeight / 2)
        return CGPoint(x: from.x + offsetX, y: from.y + offsetY)
    }

    /// Adjust end point to edge of target node.
    private var adjustedTo: CGPoint {
        let dx = from.x - to.x
        let dy = from.y - to.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return to }
        let offsetX = (dx / len) * (nodeWidth / 2)
        let offsetY = (dy / len) * (nodeHeight / 2)
        return CGPoint(x: to.x + offsetX, y: to.y + offsetY)
    }
}

/// A simple line shape between two points.
private struct ArrowLine: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

/// Arrowhead triangle at the end of an edge.
private struct ArrowHead: Shape {
    let at: CGPoint
    let from: CGPoint
    private let size: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let dx = at.x - from.x
        let dy = at.y - from.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return Path() }

        let ux = dx / len
        let uy = dy / len
        // Perpendicular
        let px = -uy
        let py = ux

        let tip = at
        let left = CGPoint(x: tip.x - ux * size + px * size * 0.4,
                           y: tip.y - uy * size + py * size * 0.4)
        let right = CGPoint(x: tip.x - ux * size - px * size * 0.4,
                            y: tip.y - uy * size - py * size * 0.4)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
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
        .accessibilityLabel("Agent: \(name)")
    }
}
