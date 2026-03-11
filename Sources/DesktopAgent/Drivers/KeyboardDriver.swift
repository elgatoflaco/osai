import Foundation
import CoreGraphics
import Carbon

// MARK: - Keyboard & Mouse Driver

final class KeyboardDriver {

    func typeText(_ text: String) -> ToolResult {
        let source = CGEventSource(stateID: .combinedSessionState)

        for char in text {
            let str = String(char)
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(string: str)
            event?.post(tap: .cghidEventTap)

            let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            eventUp?.keyboardSetUnicodeString(string: str)
            eventUp?.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.01)
        }

        return ToolResult(success: true, output: "Typed \(text.count) characters: \"\(String(text.prefix(50)))\"", screenshot: nil)
    }

    func pressKey(_ keyCombo: String) -> ToolResult {
        let parts = keyCombo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

        var flags: CGEventFlags = []
        var keyCode: CGKeyCode = 0
        var foundKey = false

        for part in parts {
            switch part {
            case "command", "cmd":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "option", "alt":
                flags.insert(.maskAlternate)
            case "control", "ctrl":
                flags.insert(.maskControl)
            default:
                if let code = keyCodeMap[part] {
                    keyCode = code
                    foundKey = true
                } else if part.count == 1, let ascii = part.first?.asciiValue {
                    keyCode = asciiToKeyCode(ascii)
                    foundKey = true
                }
            }
        }

        guard foundKey else {
            return ToolResult(success: false, output: "Unknown key: \(keyCombo). Valid keys: return, tab, space, delete, escape, up, down, left, right, f1-f12, or any single letter/number.", screenshot: nil)
        }

        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)

        return ToolResult(success: true, output: "Pressed: \(keyCombo)", screenshot: nil)
    }

    func mouseMove(x: Int, y: Int) -> ToolResult {
        let point = CGPoint(x: x, y: y)
        let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
        return ToolResult(success: true, output: "Mouse moved to (\(x), \(y))", screenshot: nil)
    }

    func mouseClick(x: Int, y: Int, button: String = "left", clickCount: Int = 1) -> ToolResult {
        let point = CGPoint(x: x, y: y)
        let mouseButton: CGMouseButton = button == "right" ? .right : .left
        let downType: CGEventType = button == "right" ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == "right" ? .rightMouseUp : .leftMouseUp

        // Move first
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)

        for i in 0..<clickCount {
            let downEvent = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton)
            downEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
            downEvent?.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.02)

            let upEvent = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton)
            upEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
            upEvent?.post(tap: .cghidEventTap)

            if i < clickCount - 1 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        let clickType = clickCount > 1 ? "double-clicked" : "clicked"
        return ToolResult(success: true, output: "\(button) \(clickType) at (\(x), \(y))", screenshot: nil)
    }

    func scroll(x: Int, y: Int, direction: String, amount: Int) -> ToolResult {
        let point = CGPoint(x: x, y: y)

        // Move mouse to scroll position
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)

        // Calculate scroll deltas
        var dy: Int32 = 0
        var dx: Int32 = 0
        switch direction.lowercased() {
        case "up":    dy = Int32(amount)
        case "down":  dy = -Int32(amount)
        case "left":  dx = Int32(amount)
        case "right": dx = -Int32(amount)
        default:      dy = -Int32(amount) // default: scroll down
        }

        // Post scroll events in small increments for smoother scrolling
        let steps = max(amount, 1)
        let stepDy = dy != 0 ? (dy > 0 ? Int32(1) : Int32(-1)) : Int32(0)
        let stepDx = dx != 0 ? (dx > 0 ? Int32(1) : Int32(-1)) : Int32(0)

        for _ in 0..<steps {
            if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: stepDy, wheel2: stepDx, wheel3: 0) {
                scrollEvent.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        return ToolResult(success: true, output: "Scrolled \(direction) by \(amount) at (\(x), \(y))", screenshot: nil)
    }

    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int, duration: Double) -> ToolResult {
        let fromPoint = CGPoint(x: fromX, y: fromY)
        let toPoint = CGPoint(x: toX, y: toY)
        let safeDuration = min(max(duration, 0.1), 5.0)

        // 1. Move to start
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: fromPoint, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)

        // 2. Mouse down
        let downEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: fromPoint, mouseButton: .left)
        downEvent?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)

        // 3. Interpolate drag
        let steps = max(Int(safeDuration * 60), 10)
        let sleepInterval = safeDuration / Double(steps)

        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let x = fromPoint.x + (toPoint.x - fromPoint.x) * t
            let y = fromPoint.y + (toPoint.y - fromPoint.y) * t
            let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
            dragEvent?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: sleepInterval)
        }

        // 4. Mouse up
        let upEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: toPoint, mouseButton: .left)
        upEvent?.post(tap: .cghidEventTap)

        return ToolResult(success: true, output: "Dragged from (\(fromX),\(fromY)) to (\(toX),\(toY)) over \(safeDuration)s", screenshot: nil)
    }

    func getScreenSize() -> (width: Int, height: Int) {
        let screen = CGMainDisplayID()
        let width = CGDisplayPixelsWide(screen)
        let height = CGDisplayPixelsHigh(screen)
        return (width, height)
    }

    // MARK: - Key Code Mapping

    private let keyCodeMap: [String: CGKeyCode] = [
        "return": 36, "enter": 36,
        "tab": 48,
        "space": 49,
        "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53,
        "up": 126, "down": 125, "left": 123, "right": 124,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121,
        "forwarddelete": 117,
        "minus": 27, "-": 27,
        "equal": 24, "=": 24, "+": 24,
        "leftbracket": 33, "[": 33,
        "rightbracket": 30, "]": 30,
        "semicolon": 41, ";": 41,
        "quote": 39, "'": 39,
        "comma": 43, ",": 43,
        "period": 47, ".": 47,
        "slash": 44, "/": 44,
        "backslash": 42, "\\": 42,
        "grave": 50, "`": 50,
    ]

    private func asciiToKeyCode(_ ascii: UInt8) -> CGKeyCode {
        let map: [UInt8: CGKeyCode] = [
            97: 0, 98: 11, 99: 8, 100: 2, 101: 14, 102: 3, 103: 5, 104: 4,
            105: 34, 106: 38, 107: 40, 108: 37, 109: 46, 110: 45, 111: 31,
            112: 35, 113: 12, 114: 15, 115: 1, 116: 17, 117: 32, 118: 9,
            119: 13, 120: 7, 121: 16, 122: 6,
            48: 29, 49: 18, 50: 19, 51: 20, 52: 21, 53: 23, 54: 22, 55: 26, 56: 28, 57: 25,
        ]
        return map[ascii] ?? 0
    }
}

// MARK: - CGEvent Unicode Helper

extension CGEvent {
    func keyboardSetUnicodeString(string: String) {
        let utf16 = Array(string.utf16)
        self.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    }
}
