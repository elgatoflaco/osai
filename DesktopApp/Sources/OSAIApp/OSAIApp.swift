import SwiftUI
import AppKit

@main
struct OSAIApp: App {
    @StateObject var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        setAppIcon()
    }

    private func setAppIcon() {
        let size: CGFloat = 512
        let pixelSize = size / 16
        let ghostGrid: [[Int]] = [
            [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
            [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
            [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
            [0,1,1,2,2,1,1,1,1,1,2,2,1,1,1,0],
            [0,1,2,2,3,3,1,1,1,2,2,3,3,1,1,0],
            [0,1,2,2,3,3,1,1,1,2,2,3,3,1,1,0],
            [0,1,1,2,2,1,1,1,1,1,2,2,1,1,1,0],
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
            [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
            [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],
            [0,1,0,0,0,0,1,0,0,0,1,0,0,0,1,0],
        ]

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let teal = NSColor(red: 80/255, green: 200/255, blue: 200/255, alpha: 1)
        let white = NSColor.white
        let darkBlue = NSColor(red: 20/255, green: 30/255, blue: 60/255, alpha: 1)

        // Background with rounded rect
        NSColor(red: 15/255, green: 15/255, blue: 20/255, alpha: 1).setFill()
        let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: size * 0.2, yRadius: size * 0.2)
        bgPath.fill()

        // Ghost centered with padding
        let ghostWidth: CGFloat = 16 * pixelSize * 0.7
        let ghostHeight: CGFloat = 14 * pixelSize * 0.7
        let pSize = ghostWidth / 16
        let offsetX = (size - ghostWidth) / 2
        let offsetY = (size - ghostHeight) / 2

        for row in 0..<14 {
            for col in 0..<16 {
                let value = ghostGrid[row][col]
                guard value != 0 else { continue }

                let color: NSColor
                switch value {
                case 1: color = teal
                case 2: color = white
                case 3: color = darkBlue
                default: continue
                }

                color.setFill()
                // Flip Y for AppKit coordinate system
                let rect = NSRect(
                    x: offsetX + CGFloat(col) * pSize,
                    y: offsetY + ghostHeight - CGFloat(row + 1) * pSize,
                    width: pSize + 0.5,
                    height: pSize + 0.5
                )
                rect.fill()
            }
        }

        image.unlockFocus()
        NSApplication.shared.applicationIconImage = image
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 480, minHeight: 400)
                .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // File menu additions
            CommandGroup(after: .newItem) {
                Button("New Chat") {
                    appState.startNewChat()
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()
            }

            // View menu
            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    if appState.sidebarHidden {
                        withAnimation(.easeOut(duration: 0.25)) {
                            appState.showSidebarOverlay.toggle()
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.sidebarCollapsed.toggle()
                        }
                    }
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Focus Mode") {
                    appState.selectedTab = .chat
                    appState.shouldFocusInput = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.sidebarCollapsed = true
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button(appState.compactMode ? "Exit Compact Mode" : "Compact Mode") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.toggleCompactMode()
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button(appState.floatOnTop ? "Disable Float on Top" : "Float on Top") {
                    appState.toggleFloatOnTop()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Keyboard Shortcuts") {
                    appState.showShortcutsOverlay.toggle()
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            // Chat menu
            CommandMenu("Chat") {
                Button("Send Message") {
                    appState.shouldFocusInput = true
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Cancel") {
                    appState.cancelProcessing()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!appState.isProcessing)
            }
        }

        // MARK: - Menu Bar Extra

        MenuBarExtra("OSAI", systemImage: appState.gatewayRunning
                     ? "bubble.left.and.bubble.right.fill"
                     : "bubble.left.and.bubble.right") {
            MenuBarChatView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
