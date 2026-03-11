import Foundation

// MARK: - Interactive Terminal Picker

struct PickerItem {
    let label: String
    let value: String
    let isHeader: Bool
    let hasKey: Bool
    let isActive: Bool

    init(label: String, value: String = "", isHeader: Bool = false, hasKey: Bool = false, isActive: Bool = false) {
        self.label = label
        self.value = value
        self.isHeader = isHeader
        self.hasKey = hasKey
        self.isActive = isActive
    }
}

struct InteractivePicker {

    /// Show an interactive picker and return the selected value, or nil if cancelled
    static func pick(title: String, items: [PickerItem]) -> String? {
        guard !items.isEmpty else { return nil }

        // Find selectable indices (non-header items)
        let selectableIndices = items.indices.filter { !items[$0].isHeader }
        guard !selectableIndices.isEmpty else { return nil }

        var cursorIndex = 0  // index into selectableIndices

        // Find the currently active item to start cursor there
        for (i, idx) in selectableIndices.enumerated() {
            if items[idx].isActive {
                cursorIndex = i
                break
            }
        }

        // Enable raw mode
        var originalTermios = termios()
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        // Set VMIN=1, VTIME=0 using withUnsafeMutablePointer for tuple access
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            let buf = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: cc_t.self)
            buf[Int(VMIN)] = 1
            buf[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        defer {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
        }

        // Hide cursor
        print("\u{001B}[?25l", terminator: "")
        fflush(stdout)

        func render() {
            // Move to start and clear
            let totalLines = items.count + 2 // title + blank line + items
            // Clear previous render
            print("\u{001B}[\(totalLines + 1)A", terminator: "")  // move up
            for _ in 0...totalLines {
                print("\u{001B}[2K\u{001B}[1B", terminator: "")  // clear line, move down
            }
            print("\u{001B}[\(totalLines + 1)A", terminator: "")  // move back up

            // Print title
            print("\u{001B}[1m  \(title)\u{001B}[0m")
            print()

            let selectedIdx = selectableIndices[cursorIndex]

            for (i, item) in items.enumerated() {
                if item.isHeader {
                    let keyStatus = item.hasKey
                        ? "\u{001B}[32m● key set\u{001B}[0m"
                        : "\u{001B}[31m○ no key\u{001B}[0m"
                    print("  \u{001B}[1;36m\(item.label)\u{001B}[0m \(keyStatus)")
                } else {
                    let isSelected = (i == selectedIdx)
                    let cursor = isSelected ? "\u{001B}[36m❯\u{001B}[0m" : " "
                    let activeMarker = item.isActive ? " \u{001B}[32m✓\u{001B}[0m" : ""
                    let highlight = isSelected ? "\u{001B}[1m" : "\u{001B}[90m"
                    print("  \(cursor) \(highlight)\(item.label)\u{001B}[0m\(activeMarker)")
                }
            }

            print()
            print("\u{001B}[90m  ↑/↓ navigate  ⏎ select  q/esc cancel\u{001B}[0m")
            fflush(stdout)
        }

        // Print blank lines first to create space for initial render
        let totalLines = items.count + 2
        for _ in 0...totalLines + 1 {
            print()
        }
        fflush(stdout)

        render()

        while true {
            var c: UInt8 = 0
            let bytesRead = read(STDIN_FILENO, &c, 1)
            guard bytesRead == 1 else { continue }

            switch c {
            case 0x1B: // Escape sequence
                var seq1: UInt8 = 0
                var seq2: UInt8 = 0
                let r1 = read(STDIN_FILENO, &seq1, 1)
                let r2 = read(STDIN_FILENO, &seq2, 1)
                if r1 == 1 && r2 == 1 && seq1 == 0x5B { // [
                    switch seq2 {
                    case 0x41: // Up arrow
                        if cursorIndex > 0 { cursorIndex -= 1 }
                        render()
                    case 0x42: // Down arrow
                        if cursorIndex < selectableIndices.count - 1 { cursorIndex += 1 }
                        render()
                    default:
                        break
                    }
                } else if r1 == 0 || (r1 == 1 && seq1 != 0x5B) {
                    // Bare escape — cancel
                    print("\u{001B}[?25h", terminator: "") // show cursor
                    fflush(stdout)
                    return nil
                }

            case 0x0A, 0x0D: // Enter
                let selected = items[selectableIndices[cursorIndex]]
                print("\u{001B}[?25h", terminator: "") // show cursor
                fflush(stdout)
                return selected.value

            case 0x71, 0x51: // q/Q
                print("\u{001B}[?25h", terminator: "") // show cursor
                fflush(stdout)
                return nil

            case 0x6B, 0x10: // k or Ctrl+P (up)
                if cursorIndex > 0 { cursorIndex -= 1 }
                render()

            case 0x6A, 0x0E: // j or Ctrl+N (down)
                if cursorIndex < selectableIndices.count - 1 { cursorIndex += 1 }
                render()

            default:
                break
            }
        }
    }

    /// Build the model picker items from providers
    static func buildModelItems(currentProviderId: String, currentModel: String) -> [PickerItem] {
        let fileConfig = AgentConfigFile.load()
        var items: [PickerItem] = []

        for provider in AIProvider.known {
            let hasKey = fileConfig.getAPIKey(provider: provider.id) != nil
            items.append(PickerItem(
                label: "\(provider.name) (\(provider.id))",
                isHeader: true,
                hasKey: hasKey
            ))

            for model in provider.models {
                let isActive = (provider.id == currentProviderId && model == currentModel)
                items.append(PickerItem(
                    label: "\(provider.id)/\(model)",
                    value: "\(provider.id)/\(model)",
                    isActive: isActive
                ))
            }
        }

        return items
    }
}
