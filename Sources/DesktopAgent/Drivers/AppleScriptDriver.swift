import Foundation
import AppKit

// MARK: - AppleScript Driver

final class AppleScriptDriver {

    func execute(_ script: String) -> ToolResult {
        // Use osascript subprocess instead of NSAppleScript
        // NSAppleScript requires an active RunLoop which doesn't work well with async/await CLI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ToolResult(success: false, output: "Failed to run osascript: \(error.localizedDescription)", screenshot: nil)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            return ToolResult(success: false, output: "AppleScript Error: \(errorOutput)", screenshot: nil)
        }

        return ToolResult(success: true, output: output.isEmpty ? "OK (no output)" : output, screenshot: nil)
    }

    func listRunningApps(includeAccessory: Bool = false) -> [AppInfo] {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications
            .filter { app in
                if includeAccessory {
                    return app.activationPolicy == .regular || app.activationPolicy == .accessory
                }
                return app.activationPolicy == .regular
            }
            .map { app in
                AppInfo(
                    name: app.localizedName ?? "Unknown",
                    pid: app.processIdentifier,
                    bundleId: app.bundleIdentifier,
                    isActive: app.isActive
                )
            }
    }

    func getFrontmostApp() -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AppInfo(
            name: app.localizedName ?? "Unknown",
            pid: app.processIdentifier,
            bundleId: app.bundleIdentifier,
            isActive: true
        )
    }

    func activateApp(name: String) -> ToolResult {
        let script = """
        tell application "\(name.replacingOccurrences(of: "\"", with: "\\\""))"
            activate
        end tell
        """
        return execute(script)
    }

    func openApp(name: String) -> ToolResult {
        let script = """
        tell application "\(name.replacingOccurrences(of: "\"", with: "\\\""))"
            launch
            activate
        end tell
        """
        return execute(script)
    }

    func openURL(_ urlString: String) -> ToolResult {
        let script = """
        open location "\(urlString.replacingOccurrences(of: "\"", with: "\\\""))"
        """
        return execute(script)
    }

    func getClipboard() -> ToolResult {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            return ToolResult(success: true, output: text, screenshot: nil)
        }
        return ToolResult(success: false, output: "Clipboard is empty or doesn't contain text", screenshot: nil)
    }

    func setClipboard(_ text: String) -> ToolResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return ToolResult(success: true, output: "Text copied to clipboard", screenshot: nil)
    }
}
