import SwiftUI
import AppKit

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

    // Accent — same teal/cyan in both modes
    static let accent = Color(red: 80/255, green: 200/255, blue: 200/255)
    static let accentGlow = Color(red: 80/255, green: 200/255, blue: 200/255).opacity(0.3)

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
    static let borderGlass = adaptive(
        light: NSColor(red: 0, green: 0, blue: 0, alpha: 0.1),
        dark:  NSColor(red: 80/255, green: 200/255, blue: 200/255, alpha: 0.15)
    )

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
