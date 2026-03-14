import Foundation

// MARK: - Terminal Display Coordinator
//
// All output must go through this coordinator. When the user is typing in the
// LineEditor, output would corrupt their input line. The coordinator:
// 1. Clears the current input line
// 2. Writes the output above
// 3. Redraws the input line at the new position
//
// The lock here is the MASTER lock for all terminal I/O. Both output writing
// (writeLine/writeInline) and LineEditor's redraw() must acquire this lock
// to prevent escape sequence interleaving.

final class TerminalDisplay {
    static let shared = TerminalDisplay()

    let lock = NSLock()
    private weak var activeEditor: LineEditor?

    /// Register the active line editor (set when user is typing)
    func setActiveEditor(_ editor: LineEditor?) {
        lock.lock()
        activeEditor = editor
        lock.unlock()
    }

    /// Execute a block with the terminal lock held.
    /// LineEditor's redraw() uses this to prevent interleaving with output.
    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Write output safely — saves/restores input line if user is typing
    func writeLine(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        if let editor = activeEditor, editor.isActive {
            editor.clearLine()
            var out = text + "\n"
            out.withUTF8 { buf in
                _ = write(STDOUT_FILENO, buf.baseAddress!, buf.count)
            }
            editor.redrawLine()
        } else {
            var out = text + "\n"
            out.withUTF8 { buf in
                _ = write(STDOUT_FILENO, buf.baseAddress!, buf.count)
            }
        }
        fflush(stdout)
    }

    /// Write without newline
    func writeInline(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        if let editor = activeEditor, editor.isActive {
            editor.clearLine()
            text.withCString { ptr in
                _ = write(STDOUT_FILENO, ptr, strlen(ptr))
            }
            editor.redrawLine()
        } else {
            text.withCString { ptr in
                _ = write(STDOUT_FILENO, ptr, strlen(ptr))
            }
        }
        fflush(stdout)
    }
}
