import SwiftUI

struct AppTheme {
    // Accent
    static let accent = Color(red: 80/255, green: 200/255, blue: 200/255)
    static let accentGlow = Color(red: 80/255, green: 200/255, blue: 200/255).opacity(0.3)

    // Backgrounds
    static let bgPrimary = Color(red: 10/255, green: 10/255, blue: 15/255)
    static let bgSecondary = Color(red: 18/255, green: 18/255, blue: 26/255)
    static let bgGlass = Color(red: 18/255, green: 18/255, blue: 26/255).opacity(0.7)
    static let bgCard = Color(red: 24/255, green: 24/255, blue: 34/255)
    static let borderGlass = Color(red: 80/255, green: 200/255, blue: 200/255).opacity(0.15)

    // Text
    static let textPrimary = Color(red: 232/255, green: 232/255, blue: 237/255)
    static let textSecondary = Color(red: 136/255, green: 136/255, blue: 160/255)
    static let textMuted = Color(red: 90/255, green: 90/255, blue: 110/255)

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
