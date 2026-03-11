import Foundation

// MARK: - Aside Monitor (talk to agent while it's working)
//
// While the agent loop is running, the user can type a message and hit Enter.
// The message gets injected into the next iteration as an "aside" — extra context
// or instructions without interrupting the workflow.
//
// No special command needed — just type while the agent works.

final class AsideMonitor {
    private var pendingAsides: [String] = []
    private let lock = NSLock()
    private var isMonitoring = false
    private var monitorThread: Thread?
    private var hasShownTip = false

    /// Start watching stdin for user input in a background thread.
    /// Call this when the agent loop starts processing.
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        if !hasShownTip {
            hasShownTip = true
            let tip = "  \u{001B}[90m💬 Type while I'm working to send me instructions mid-task\u{001B}[0m\n"
            write(STDOUT_FILENO, tip, tip.utf8.count)
        }

        let thread = Thread { [weak self] in
            self?.monitorLoop()
        }
        thread.name = "aside-monitor"
        thread.qualityOfService = .userInitiated
        self.monitorThread = thread
        thread.start()
    }

    /// Stop monitoring. Waits for the background thread to finish
    /// so it doesn't conflict with LineEditor's stdin reads.
    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        // Wait a bit for the poll() timeout to expire and thread to exit
        Thread.sleep(forTimeInterval: 0.15)
        monitorThread = nil
    }

    /// Check if there are pending asides. Returns all pending messages and clears them.
    func drain() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let messages = pendingAsides
        pendingAsides.removeAll()
        return messages
    }

    /// Check if any asides are pending (non-destructive).
    var hasPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pendingAsides.isEmpty
    }

    // MARK: - Internal

    private func monitorLoop() {
        while isMonitoring {
            // Non-blocking poll on stdin (100ms timeout)
            var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let result = poll(&pfd, 1, 100)

            guard isMonitoring else { break }

            if result > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                // Data available on stdin — read it
                var buf = [UInt8](repeating: 0, count: 4096)
                let n = read(STDIN_FILENO, &buf, buf.count)
                if n > 0 {
                    let str = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        lock.lock()
                        pendingAsides.append(trimmed)
                        lock.unlock()

                        // Visual feedback
                        let line = "\r\u{001B}[2K  \u{001B}[1;34m💬 \(trimmed)\u{001B}[0m\n"
                        write(STDOUT_FILENO, line, line.utf8.count)
                    }
                }
            }
        }
    }
}
