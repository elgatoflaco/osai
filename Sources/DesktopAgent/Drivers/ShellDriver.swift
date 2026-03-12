import Foundation

// MARK: - Shell Driver (Async I/O)

final class ShellDriver {

    /// Optional streaming callback — receives output chunks as they arrive.
    /// Set this before calling executeAsync() to get real-time output streaming.
    var onOutputStream: ((String) -> Void)?

    // MARK: - Async Execution (Non-blocking I/O)

    /// Execute a shell command with non-blocking I/O.
    /// Output is read incrementally via `availableData` on background queues,
    /// preventing pipe buffer deadlocks and enabling real-time streaming.
    func execute(command: String, timeout: Int = 30) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = ProcessInfo.processInfo.environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return ToolResult(success: false, output: "Failed to run command: \(error.localizedDescription)", screenshot: nil)
        }

        // Timeout handling
        let timeoutSeconds = min(max(timeout, 1), 120)
        var timedOut = false

        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .seconds(timeoutSeconds))
        timer.setEventHandler {
            timedOut = true
            process.terminate()
        }
        timer.resume()

        // Read stdout and stderr incrementally on background queues.
        // This prevents pipe buffer deadlocks that occur when a process writes
        // more than 64KB to a pipe before the reader drains it (the process blocks
        // on write, but we're waiting for exit before reading → deadlock).
        var stdoutChunks: [String] = []
        var stderrChunks: [String] = []
        let stdoutLock = NSLock()
        let stderrLock = NSLock()
        let readGroup = DispatchGroup()

        // Background stdout reader — streams chunks via callback
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let handle = outputPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF
                if let text = String(data: data, encoding: .utf8) {
                    stdoutLock.lock()
                    stdoutChunks.append(text)
                    stdoutLock.unlock()
                    self?.onOutputStream?(text)
                }
            }
            readGroup.leave()
        }

        // Background stderr reader
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = errorPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF
                if let text = String(data: data, encoding: .utf8) {
                    stderrLock.lock()
                    stderrChunks.append(text)
                    stderrLock.unlock()
                }
            }
            readGroup.leave()
        }

        // Wait for process to exit (readers continue draining in parallel)
        process.waitUntilExit()
        timer.cancel()

        // Wait for readers to finish draining any remaining buffered output
        readGroup.wait()

        let stdout = stdoutChunks.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = stderrChunks.joined().trimmingCharacters(in: .whitespacesAndNewlines)

        if timedOut {
            let partial = truncateOutput(stdout + "\n" + stderr)
            return ToolResult(success: false, output: "Command timed out after \(timeoutSeconds)s.\nPartial output:\n\(partial)", screenshot: nil)
        }

        let exitCode = process.terminationStatus
        var output = ""

        if !stdout.isEmpty {
            output += stdout
        }
        if !stderr.isEmpty {
            if !output.isEmpty { output += "\n--- stderr ---\n" }
            output += stderr
        }
        if output.isEmpty {
            output = "(no output)"
        }

        output = truncateOutput(output)

        let success = exitCode == 0
        if !success {
            output = "Exit code: \(exitCode)\n\(output)"
        }

        return ToolResult(success: success, output: output, screenshot: nil)
    }

    func spotlightSearch(query: String, kind: String? = nil) -> ToolResult {
        let safeQuery = query.replacingOccurrences(of: "\"", with: "\\\"")

        // Try simple name search first (most reliable)
        let nameResult = execute(command: "/usr/bin/mdfind -name \"\(safeQuery)\" | head -20", timeout: 10)
        if nameResult.success && !nameResult.output.isEmpty && nameResult.output != "(no output)" {
            // Filter by kind if specified
            if let kind = kind?.lowercased() {
                let lines = nameResult.output.split(separator: "\n").map(String.init)
                let filtered: [String]
                switch kind {
                case "application", "app":
                    filtered = lines.filter { $0.hasSuffix(".app") }
                case "folder", "directory":
                    // Check if path is a directory
                    filtered = lines.filter { path in
                        var isDir: ObjCBool = false
                        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                        return isDir.boolValue
                    }
                case "image":
                    filtered = lines.filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".gif") || $0.hasSuffix(".webp") }
                case "document", "doc":
                    filtered = lines.filter { $0.hasSuffix(".pdf") || $0.hasSuffix(".doc") || $0.hasSuffix(".docx") || $0.hasSuffix(".txt") || $0.hasSuffix(".md") }
                default:
                    filtered = lines
                }
                if !filtered.isEmpty {
                    return ToolResult(success: true, output: filtered.joined(separator: "\n"), screenshot: nil)
                }
            }
            return nameResult
        }

        return ToolResult(success: true, output: "No results found for '\(query)'", screenshot: nil)
    }

    // MARK: - Private

    private func truncateOutput(_ text: String, maxLength: Int = 10000) -> String {
        if text.count <= maxLength { return text }
        let half = maxLength / 2
        let start = text.prefix(half)
        let end = text.suffix(half)
        return "\(start)\n\n... [truncated \(text.count - maxLength) characters] ...\n\n\(end)"
    }
}
