import SwiftUI
import AppKit

// MARK: - Accent Color Presets

struct AccentColorPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let color: Color
    let nsColor: NSColor

    static func == (lhs: AccentColorPreset, rhs: AccentColorPreset) -> Bool {
        lhs.id == rhs.id
    }
}

let accentColorPresets: [AccentColorPreset] = [
    AccentColorPreset(id: "teal", name: "Teal",
                      color: Color(red: 80/255, green: 200/255, blue: 200/255),
                      nsColor: NSColor(red: 80/255, green: 200/255, blue: 200/255, alpha: 1)),
    AccentColorPreset(id: "purple", name: "Purple",
                      color: Color(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255),
                      nsColor: NSColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 1)),
    AccentColorPreset(id: "blue", name: "Blue",
                      color: Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255),
                      nsColor: NSColor(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255, alpha: 1)),
    AccentColorPreset(id: "green", name: "Green",
                      color: Color(red: 0x10/255, green: 0xB9/255, blue: 0x81/255),
                      nsColor: NSColor(red: 0x10/255, green: 0xB9/255, blue: 0x81/255, alpha: 1)),
    AccentColorPreset(id: "orange", name: "Orange",
                      color: Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255),
                      nsColor: NSColor(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255, alpha: 1)),
    AccentColorPreset(id: "pink", name: "Pink",
                      color: Color(red: 0xEC/255, green: 0x48/255, blue: 0x99/255),
                      nsColor: NSColor(red: 0xEC/255, green: 0x48/255, blue: 0x99/255, alpha: 1)),
    AccentColorPreset(id: "red", name: "Red",
                      color: Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255),
                      nsColor: NSColor(red: 0xEF/255, green: 0x44/255, blue: 0x44/255, alpha: 1)),
]

struct AppTheme {
    // MARK: - Adaptive color helper
    // Creates a Color that automatically switches between light and dark variants
    // based on the current system/app appearance (driven by .preferredColorScheme).
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return dark
            } else {
                return light
            }
        })
    }

    // MARK: - Configurable Accent

    /// The current accent NSColor backing the theme. Defaults to teal.
    private static var _accentNSColor: NSColor = NSColor(red: 80/255, green: 200/255, blue: 200/255, alpha: 1)

    /// Update the theme accent color at runtime. Call from the main thread.
    static func setAccentColor(_ presetId: String) {
        guard let preset = accentColorPresets.first(where: { $0.id == presetId }) else { return }
        _accentNSColor = preset.nsColor
    }

    /// Current accent color — reads from the mutable backing store so it always
    /// reflects the latest selection.  SwiftUI views that reference this will
    /// re-render when the owning @Published state changes.
    static var accent: Color {
        Color(nsColor: _accentNSColor)
    }

    static var accentGlow: Color {
        Color(nsColor: _accentNSColor).opacity(0.3)
    }

    // Backgrounds
    static let bgPrimary = adaptive(
        light: NSColor(red: 244/255, green: 244/255, blue: 247/255, alpha: 1),
        dark:  NSColor(red: 10/255,  green: 10/255,  blue: 15/255,  alpha: 1)
    )
    static let bgSecondary = adaptive(
        light: NSColor(red: 232/255, green: 232/255, blue: 237/255, alpha: 1),
        dark:  NSColor(red: 18/255,  green: 18/255,  blue: 26/255,  alpha: 1)
    )
    static let bgGlass = adaptive(
        light: NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.7),
        dark:  NSColor(red: 18/255,  green: 18/255,  blue: 26/255,  alpha: 0.7)
    )
    static let bgCard = adaptive(
        light: NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.85),
        dark:  NSColor(red: 24/255,  green: 24/255,  blue: 34/255,  alpha: 1)
    )

    /// Border glass uses the accent color for the dark-mode tint.
    static var borderGlass: Color {
        adaptive(
            light: NSColor(red: 0, green: 0, blue: 0, alpha: 0.1),
            dark:  _accentNSColor.withAlphaComponent(0.15)
        )
    }

    // Text
    static let textPrimary = adaptive(
        light: NSColor(red: 28/255,  green: 28/255,  blue: 30/255,  alpha: 1),
        dark:  NSColor(red: 232/255, green: 232/255, blue: 237/255, alpha: 1)
    )
    static let textSecondary = adaptive(
        light: NSColor(red: 100/255, green: 100/255, blue: 115/255, alpha: 1),
        dark:  NSColor(red: 136/255, green: 136/255, blue: 160/255, alpha: 1)
    )
    static let textMuted = adaptive(
        light: NSColor(red: 160/255, green: 160/255, blue: 175/255, alpha: 1),
        dark:  NSColor(red: 90/255,  green: 90/255,  blue: 110/255, alpha: 1)
    )

    // Semantic
    static let success = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let warning = Color(red: 255/255, green: 204/255, blue: 0/255)
    static let error = Color(red: 255/255, green: 69/255, blue: 58/255)

    // Typography
    static let fontTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let fontHeadline = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let fontBody = Font.system(size: 14, weight: .regular, design: .default)
    static let fontCaption = Font.system(size: 12, weight: .medium, design: .default)
    static let fontMono = Font.system(size: 13, weight: .regular, design: .monospaced)

    // Spacing
    static let paddingSm: CGFloat = 8
    static let paddingMd: CGFloat = 16
    static let paddingLg: CGFloat = 24
    static let paddingXl: CGFloat = 32
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSm: CGFloat = 10
}
