import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

// MARK: - Accessibility Driver

final class AccessibilityDriver {

    func checkPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Smart App Finder

    func findApp(query: String, runningApps: [AppInfo]) -> AppInfo? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)

        // 1. If query is a PID number
        if let pid = Int32(q) {
            return runningApps.first { $0.pid == pid }
        }

        // 2. Exact name match
        if let app = runningApps.first(where: { $0.name.lowercased() == q }) {
            return app
        }

        // 3. Case-insensitive contains on name
        if let app = runningApps.first(where: { $0.name.lowercased().contains(q) }) {
            return app
        }

        // 4. Bundle ID contains
        if let app = runningApps.first(where: { $0.bundleId?.lowercased().contains(q) == true }) {
            return app
        }

        // 5. Fuzzy: check if all words in query appear in name
        let queryWords = q.split(separator: " ")
        if let app = runningApps.first(where: { appInfo in
            let nameLower = appInfo.name.lowercased()
            return queryWords.allSatisfy { nameLower.contains($0) }
        }) {
            return app
        }

        return nil
    }

    // MARK: - UI Elements

    func getUIElements(pid: pid_t, maxDepth: Int = 3) -> [UIElement] {
        let appRef = AXUIElementCreateApplication(pid)
        var elements: [UIElement] = []

        // Try focused window first
        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        if windowResult == .success, let window = focusedWindow {
            let windowElement = window as! AXUIElement
            let parsed = parseElement(windowElement, depth: 0, maxDepth: maxDepth)
            elements.append(parsed)
        } else {
            // Fallback: get all windows
            var windowList: AnyObject?
            let listResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList)
            if listResult == .success, let windows = windowList as? [AXUIElement] {
                for window in windows.prefix(3) {
                    let parsed = parseElement(window, depth: 0, maxDepth: maxDepth)
                    elements.append(parsed)
                }
            }
        }

        if elements.isEmpty {
            let appElement = parseElement(appRef, depth: 0, maxDepth: maxDepth)
            elements.append(appElement)
        }

        return elements
    }

    func getElementAtPosition(x: Float, y: Float) -> UIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, x, y, &element)
        guard result == .success, let el = element else { return nil }
        return parseElement(el, depth: 0, maxDepth: 1)
    }

    // MARK: - Window Management

    func listWindows(appName: String? = nil) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [WindowInfo] = []
        for info in windowList {
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 // Only normal windows (layer 0), skip menu bar, dock, etc.
            else { continue }

            let name = info[kCGWindowName as String] as? String

            let x = boundsDict["X"] as? Double ?? 0
            let y = boundsDict["Y"] as? Double ?? 0
            let w = boundsDict["Width"] as? Double ?? 0
            let h = boundsDict["Height"] as? Double ?? 0
            let bounds = CGRect(x: x, y: y, width: w, height: h)

            // Filter by app name if specified
            if let filter = appName?.lowercased() {
                if !ownerName.lowercased().contains(filter) { continue }
            }

            windows.append(WindowInfo(
                ownerName: ownerName,
                name: name,
                pid: pid,
                bounds: bounds,
                windowID: windowID,
                isOnScreen: true
            ))
        }

        return windows
    }

    func setWindowPosition(pid: pid_t, x: Int, y: Int) -> ToolResult {
        let appRef = AXUIElementCreateApplication(pid)
        guard let window = getFirstWindow(appRef) else {
            return ToolResult(success: false, output: "No window found for pid \(pid)", screenshot: nil)
        }

        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else {
            return ToolResult(success: false, output: "Failed to create position value", screenshot: nil)
        }

        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result == .success {
            return ToolResult(success: true, output: "Window moved to (\(x), \(y))", screenshot: nil)
        }
        return ToolResult(success: false, output: "Failed to move window: error \(result.rawValue)", screenshot: nil)
    }

    func setWindowSize(pid: pid_t, width: Int, height: Int) -> ToolResult {
        let appRef = AXUIElementCreateApplication(pid)
        guard let window = getFirstWindow(appRef) else {
            return ToolResult(success: false, output: "No window found for pid \(pid)", screenshot: nil)
        }

        var size = CGSize(width: width, height: height)
        guard let value = AXValueCreate(.cgSize, &size) else {
            return ToolResult(success: false, output: "Failed to create size value", screenshot: nil)
        }

        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        if result == .success {
            return ToolResult(success: true, output: "Window resized to \(width)x\(height)", screenshot: nil)
        }
        return ToolResult(success: false, output: "Failed to resize window: error \(result.rawValue)", screenshot: nil)
    }

    // MARK: - Private

    private func getFirstWindow(_ appRef: AXUIElement) -> AXUIElement? {
        var focusedWindow: AnyObject?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            return (focusedWindow as! AXUIElement)
        }
        var windowList: AnyObject?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowList) == .success,
           let windows = windowList as? [AXUIElement], let first = windows.first {
            return first
        }
        return nil
    }

    private func parseElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> UIElement {
        let role = getAttribute(element, kAXRoleAttribute as CFString) as? String ?? "unknown"
        let title = getAttribute(element, kAXTitleAttribute as CFString) as? String
        let value = getValueAsString(element)
        let position = getPosition(element)
        let size = getSize(element)
        let actions = getActions(element)

        // Also get description and label as fallbacks
        let axDesc = getAttribute(element, kAXDescriptionAttribute as CFString) as? String
        let displayTitle = title ?? axDesc

        var children: [UIElement] = []
        if depth < maxDepth {
            if let childrenRef = getAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
                children = childrenRef.prefix(30).map { child in
                    parseElement(child, depth: depth + 1, maxDepth: maxDepth)
                }
            }
        }

        return UIElement(
            role: role,
            title: displayTitle,
            value: value,
            position: position,
            size: size,
            children: children,
            actions: actions
        )
    }

    private func getAttribute(_ element: AXUIElement, _ attribute: CFString) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }

    private func getValueAsString(_ element: AXUIElement) -> String? {
        guard let val = getAttribute(element, kAXValueAttribute as CFString) else { return nil }
        if let str = val as? String { return str }
        if let num = val as? NSNumber { return num.stringValue }
        return nil
    }

    private func getPosition(_ element: AXUIElement) -> CGPoint? {
        var posValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        guard result == .success, let val = posValue else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(val as! AXValue, .cgPoint, &point)
        return point
    }

    private func getSize(_ element: AXUIElement) -> CGSize? {
        var sizeValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard result == .success, let val = sizeValue else { return nil }
        var size = CGSize.zero
        AXValueGetValue(val as! AXValue, .cgSize, &size)
        return size
    }

    private func getActions(_ element: AXUIElement) -> [String] {
        var actionNames: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNames)
        guard result == .success, let names = actionNames as? [String] else { return [] }
        return names
    }
}
