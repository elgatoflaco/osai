import Foundation

// MARK: - Input Result (text + optional images)

struct InputResult {
    let text: String
    let images: [ImageAttachment]
    let pastedLines: Int  // 0 if not a paste

    struct ImageAttachment {
        let path: String
        let base64: String
        let mediaType: String
    }

    var hasImages: Bool { !images.isEmpty }
}

// MARK: - Line Editor with Tab Completion & History

final class LineEditor {
    private var history: [String] = []
    private var historyIndex: Int = 0
    private let completions: [String]
    private let subCompletions: [String: [String]]
    private var originalTermios = termios()
    private var isRawMode = false
    /// Threshold: pastes with more than this many lines get collapsed display
    private let pasteCollapseThreshold = 3

    init() {
        self.completions = [
            "/help", "/quit", "/exit", "/clear", "/verbose",
            "/config", "/model", "/mcp", "/plugin", "/memory",
            "/program", "/improve", "/yolo", "/context", "/compact",
            "/skill", "/task",
            "/apps", "/windows", "/screen", "/perms"
        ]
        self.subCompletions = [
            "/config": ["set-key", "remove-key", "set-url", "import-openclaw", "list"],
            "/model": ["show", "list", "use"],
            "/mcp": ["list", "add", "remove", "start", "stop"],
            "/plugin": ["list", "run", "create", "delete"],
            "/memory": ["list", "read", "write", "delete"],
            "/program": ["show", "edit", "reset", "log", "prompt", "reset-prompt"],
            "/skill": ["list", "show", "delete"],
            "/task": ["list", "cancel"]
        ]
    }

    /// Strip ANSI escape sequences to get visible character count
    private func visibleLength(_ s: String) -> Int {
        var length = 0
        var inEscape = false
        for ch in s {
            if inEscape {
                if ch.isLetter || ch == "m" { inEscape = false }
            } else if ch == "\u{1B}" {
                inEscape = true
            } else {
                length += 1
            }
        }
        return length
    }

    /// Read a line with tab completion and history support
    func readLine(prompt: String) -> String? {
        // Print prompt once
        write(STDOUT_FILENO, prompt, prompt.utf8.count)
        fflush(stdout)

        enableRawMode()
        defer { disableRawMode() }

        var buffer: [Character] = []
        var cursorPos = 0
        var savedBuffer: [Character]? = nil

        func redraw() {
            // Move to column 0, clear line, reprint prompt + buffer
            var out = "\r\u{001B}[2K\(prompt)\(String(buffer))"
            // Move cursor back if not at end
            let moveBack = buffer.count - cursorPos
            if moveBack > 0 {
                out += "\u{001B}[\(moveBack)D"
            }
            write(STDOUT_FILENO, out, out.utf8.count)
        }

        while true {
            guard let char = readChar() else { return nil }

            switch char {
            // Enter
            case "\r", "\n":
                write(STDOUT_FILENO, "\n", 1)
                let line = String(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { history.append(line) }
                historyIndex = history.count
                return line

            // Tab
            case "\t":
                if let completed = autocomplete(buffer: buffer, cursorPos: cursorPos) {
                    buffer = Array(completed)
                    cursorPos = buffer.count
                    redraw()
                }

            // Backspace
            case "\u{7F}", "\u{08}":
                if cursorPos > 0 {
                    buffer.remove(at: cursorPos - 1)
                    cursorPos -= 1
                    redraw()
                }

            // Ctrl+A
            case "\u{01}":
                cursorPos = 0
                redraw()

            // Ctrl+E
            case "\u{05}":
                cursorPos = buffer.count
                redraw()

            // Ctrl+K — kill to end
            case "\u{0B}":
                buffer = Array(buffer.prefix(cursorPos))
                redraw()

            // Ctrl+U — kill to start
            case "\u{15}":
                buffer = Array(buffer.suffix(from: cursorPos))
                cursorPos = 0
                redraw()

            // Ctrl+W — delete word back
            case "\u{17}":
                if cursorPos > 0 {
                    var p = cursorPos - 1
                    while p > 0 && buffer[p - 1] == " " { p -= 1 }
                    while p > 0 && buffer[p - 1] != " " { p -= 1 }
                    buffer.removeSubrange(p..<cursorPos)
                    cursorPos = p
                    redraw()
                }

            // Ctrl+C
            case "\u{03}":
                write(STDOUT_FILENO, "^C\n", 3)
                return ""

            // Ctrl+D
            case "\u{04}":
                if buffer.isEmpty {
                    write(STDOUT_FILENO, "\n", 1)
                    return nil
                }

            // Escape sequence
            case "\u{1B}":
                guard let s1 = readChar() else { continue }
                if s1 == "[" {
                    guard let s2 = readChar() else { continue }
                    switch s2 {
                    case "A": // Up
                        if !history.isEmpty && historyIndex > 0 {
                            if historyIndex == history.count { savedBuffer = buffer }
                            historyIndex -= 1
                            buffer = Array(history[historyIndex])
                            cursorPos = buffer.count
                            redraw()
                        }
                    case "B": // Down
                        if historyIndex < history.count {
                            historyIndex += 1
                            if historyIndex == history.count {
                                buffer = savedBuffer ?? []
                                savedBuffer = nil
                            } else {
                                buffer = Array(history[historyIndex])
                            }
                            cursorPos = buffer.count
                            redraw()
                        }
                    case "C": // Right
                        if cursorPos < buffer.count {
                            cursorPos += 1
                            write(STDOUT_FILENO, "\u{001B}[C", 3)
                        }
                    case "D": // Left
                        if cursorPos > 0 {
                            cursorPos -= 1
                            write(STDOUT_FILENO, "\u{001B}[D", 3)
                        }
                    case "H": // Home
                        cursorPos = 0; redraw()
                    case "F": // End
                        cursorPos = buffer.count; redraw()
                    case "3": // Delete
                        let _ = readChar() // consume ~
                        if cursorPos < buffer.count {
                            buffer.remove(at: cursorPos)
                            redraw()
                        }
                    default: break
                    }
                } else if s1 != "[" {
                    // Bare escape — ignore (don't cancel, might be alt key)
                }

            // Regular character
            default:
                if char.asciiValue ?? 0 >= 32 || !char.isASCII {
                    buffer.insert(char, at: cursorPos)
                    cursorPos += 1

                    // Detect paste: read all immediately available chars
                    let pasteChars = drainAvailable()
                    if !pasteChars.isEmpty {
                        for pc in pasteChars {
                            buffer.insert(pc, at: cursorPos)
                            cursorPos += 1
                        }
                        // Check if this is a big paste worth collapsing
                        let text = String(buffer)
                        let lineCount = text.components(separatedBy: "\n").count
                        if lineCount > pasteCollapseThreshold || buffer.count > 500 {
                            // Collapse display — show summary instead of full text
                            let charCount = buffer.count
                            let firstLine = text.components(separatedBy: "\n").first ?? ""
                            let preview = String(firstLine.prefix(60))
                            let summary = "\u{001B}[90m📋 Pasted \(lineCount) lines (\(charCount) chars)\u{001B}[0m \u{001B}[90m— \(preview)…\u{001B}[0m"
                            let out = "\r\u{001B}[2K\(prompt)\(summary)"
                            write(STDOUT_FILENO, out, out.utf8.count)
                        } else {
                            redraw()
                        }
                    } else if cursorPos == buffer.count {
                        // Single char append — just echo it
                        let s = String(char)
                        _ = s.withCString { write(STDOUT_FILENO, $0, s.utf8.count) }
                    } else {
                        redraw()
                    }
                }
            }
        }
    }

    /// Read an input line and process it into an InputResult with image detection
    func readInput(prompt: String) -> InputResult? {
        guard let raw = readLine(prompt: prompt) else { return nil }
        if raw.isEmpty { return InputResult(text: "", images: [], pastedLines: 0) }

        let lineCount = raw.components(separatedBy: "\n").count

        // Detect image file paths (dragged files into terminal)
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"]
        var images: [InputResult.ImageAttachment] = []
        var textParts: [String] = []

        // Split by whitespace and newlines to find paths
        let tokens = raw.components(separatedBy: .whitespacesAndNewlines)
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            let expanded = (cleaned as NSString).expandingTildeInPath

            // Check if it looks like a file path with image extension
            let ext = (expanded as NSString).pathExtension.lowercased()
            if imageExtensions.contains(ext) && FileManager.default.fileExists(atPath: expanded) {
                // Read and base64 encode the image
                if let data = FileManager.default.contents(atPath: expanded) {
                    let base64 = data.base64EncodedString()
                    let mediaType: String
                    switch ext {
                    case "png": mediaType = "image/png"
                    case "jpg", "jpeg": mediaType = "image/jpeg"
                    case "gif": mediaType = "image/gif"
                    case "webp": mediaType = "image/webp"
                    case "bmp": mediaType = "image/bmp"
                    case "tiff": mediaType = "image/tiff"
                    case "heic": mediaType = "image/jpeg" // API doesn't support heic, but we try
                    default: mediaType = "image/jpeg"
                    }

                    // Check size — limit to ~20MB base64 (roughly 15MB file)
                    if data.count < 15_000_000 {
                        images.append(InputResult.ImageAttachment(
                            path: expanded, base64: base64, mediaType: mediaType
                        ))
                    } else {
                        textParts.append(token)
                        textParts.append("[image too large: \(data.count / 1_000_000)MB]")
                    }
                } else {
                    textParts.append(token)
                }
            } else {
                textParts.append(token)
            }
        }

        // Rebuild text without image paths
        let text = images.isEmpty ? raw : textParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let pastedLines = lineCount > pasteCollapseThreshold ? lineCount : 0

        return InputResult(text: text, images: images, pastedLines: pastedLines)
    }

    // MARK: - Autocomplete

    private func autocomplete(buffer: [Character], cursorPos: Int) -> String? {
        let text = String(buffer.prefix(cursorPos))
        guard text.hasPrefix("/") else { return nil }

        let parts = text.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false).map(String.init)

        if parts.count == 1 {
            let prefix = parts[0].lowercased()
            let matches = completions.filter { $0.lowercased().hasPrefix(prefix) }
            if matches.count == 1 {
                return matches[0] + " "
            } else if matches.count > 1 {
                showOptions(matches)
                return commonPrefix(matches)
            }
        } else if parts.count == 2 {
            let cmd = parts[0].lowercased()
            let sub = parts[1].lowercased()

            if let subs = subCompletions[cmd] {
                let matches = subs.filter { $0.lowercased().hasPrefix(sub) }
                if matches.count == 1 {
                    return "\(cmd) \(matches[0]) "
                } else if matches.count > 1 {
                    showOptions(matches)
                    return "\(cmd) \(commonPrefix(matches))"
                }
            }
        } else if parts.count == 3 && parts[0].lowercased() == "/model" && ["use","switch","set"].contains(parts[1].lowercased()) {
            let prefix = parts[2].lowercased()
            var models: [String] = []
            for p in AIProvider.known { for m in p.models { models.append("\(p.id)/\(m)") } }
            let matches = models.filter { $0.lowercased().hasPrefix(prefix) }
            if matches.count == 1 { return "\(parts[0]) \(parts[1]) \(matches[0])" }
            else if matches.count > 1 {
                showOptions(Array(matches.prefix(10)))
                if matches.count > 10 { printAfterLine("  \u{001B}[90m... +\(matches.count - 10) more\u{001B}[0m") }
                return "\(parts[0]) \(parts[1]) \(commonPrefix(matches))"
            }
        } else if parts.count == 3 && parts[0].lowercased() == "/config" && parts[1].lowercased() == "set-key" {
            let prefix = parts[2].lowercased()
            let providers = AIProvider.known.map { $0.id }
            let matches = providers.filter { $0.hasPrefix(prefix) }
            if matches.count == 1 { return "\(parts[0]) \(parts[1]) \(matches[0]) " }
            else if matches.count > 1 {
                showOptions(matches)
                return "\(parts[0]) \(parts[1]) \(commonPrefix(matches))"
            }
        }

        return nil
    }

    private func showOptions(_ options: [String]) {
        let line = "\n  " + options.map { "\u{001B}[36m\($0)\u{001B}[0m" }.joined(separator: "  ") + "\n"
        write(STDOUT_FILENO, line, line.utf8.count)
    }

    private func printAfterLine(_ text: String) {
        let line = text + "\n"
        write(STDOUT_FILENO, line, line.utf8.count)
    }

    private func commonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first else { return "" }
        var prefix = first
        for s in strings.dropFirst() {
            while !s.lowercased().hasPrefix(prefix.lowercased()) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
        }
        return prefix
    }

    // MARK: - Terminal

    private func readChar() -> Character? {
        var c: UInt8 = 0
        let n = read(STDIN_FILENO, &c, 1)
        guard n == 1 else { return nil }
        return Character(UnicodeScalar(c))
    }

    /// Read all immediately available characters (paste detection)
    private func drainAvailable() -> [Character] {
        var chars: [Character] = []
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)

        while true {
            let ret = poll(&pfd, 1, 0) // 0ms timeout — non-blocking
            guard ret > 0, pfd.revents & Int16(POLLIN) != 0 else { break }
            var c: UInt8 = 0
            let n = read(STDIN_FILENO, &c, 1)
            guard n == 1 else { break }
            chars.append(Character(UnicodeScalar(c)))
        }
        return chars
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
        raw.c_iflag &= ~UInt(IXON | ICRNL)
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            let buf = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: cc_t.self)
            buf[Int(VMIN)] = 1
            buf[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isRawMode = true
    }

    private func disableRawMode() {
        if isRawMode {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
            isRawMode = false
        }
    }
}
