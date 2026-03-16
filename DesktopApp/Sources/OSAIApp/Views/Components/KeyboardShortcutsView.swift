import SwiftUI

// MARK: - Keyboard Shortcuts Reference Sheet

/// A full-screen overlay showing all keyboard shortcuts organized by category,
/// rendered with macOS-style key caps. Dismiss via Escape or click outside.
struct KeyboardShortcutsView: View {
    @Binding var isPresented: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 32),
        GridItem(.flexible(), spacing: 32),
        GridItem(.flexible(), spacing: 32)
    ]

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("Keyboard Shortcuts")
                        .font(AppTheme.fontHeadline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 20)

                Divider()
                    .background(AppTheme.borderGlass)

                // Shortcut grid
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ShortcutCategory(title: "Navigation", icon: "arrow.triangle.swap", shortcuts: [
                            ShortcutEntry(keys: [.cmd, .char("1")], label: "Dashboard"),
                            ShortcutEntry(keys: [.cmd, .char("2")], label: "Chat"),
                            ShortcutEntry(keys: [.cmd, .char("3")], label: "Agents"),
                            ShortcutEntry(keys: [.cmd, .char("4")], label: "Tasks"),
                            ShortcutEntry(keys: [.cmd, .char("5")], label: "Settings"),
                            ShortcutEntry(keys: [.cmd, .char("K")], label: "Command palette"),
                            ShortcutEntry(keys: [.cmd, .char("/")], label: "This shortcuts sheet"),
                        ])

                        ShortcutCategory(title: "Chat", icon: "bubble.left.and.bubble.right", shortcuts: [
                            ShortcutEntry(keys: [.cmd, .char("N")], label: "New conversation"),
                            ShortcutEntry(keys: [.cmd, .char("W")], label: "Close conversation"),
                            ShortcutEntry(keys: [.cmd, .shift, .char("C")], label: "Copy last message"),
                            ShortcutEntry(keys: [.cmd, .char("F")], label: "Search in conversation"),
                            ShortcutEntry(keys: [.cmd, .char("[")], label: "Previous conversation"),
                            ShortcutEntry(keys: [.cmd, .char("]")], label: "Next conversation"),
                            ShortcutEntry(keys: [.symbol("\u{2191}")], label: "Edit last message"),
                            ShortcutEntry(keys: [.symbol("\u{21A9}")], label: "Send message"),
                            ShortcutEntry(keys: [.shift, .symbol("\u{21A9}")], label: "New line"),
                        ])

                        ShortcutCategory(title: "View", icon: "rectangle.3.group", shortcuts: [
                            ShortcutEntry(keys: [.cmd, .shift, .char("F")], label: "Focus mode"),
                            ShortcutEntry(keys: [.cmd, .shift, .char("M")], label: "Compact mode"),
                            ShortcutEntry(keys: [.cmd, .shift, .char("T")], label: "Float on top"),
                        ])

                        ShortcutCategory(title: "General", icon: "star", shortcuts: [
                            ShortcutEntry(keys: [.symbol("esc")], label: "Close / clear"),
                            ShortcutEntry(keys: [.cmd, .char(",")], label: "Settings"),
                        ])
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
            }
            .frame(width: 720, height: 520)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AppTheme.borderGlass, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 16)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Data Types

/// Represents a single key in a shortcut.
enum KeyCapType: Hashable {
    case cmd
    case shift
    case option
    case control
    case char(String)
    case symbol(String)

    var label: String {
        switch self {
        case .cmd: return "\u{2318}"
        case .shift: return "\u{21E7}"
        case .option: return "\u{2325}"
        case .control: return "\u{2303}"
        case .char(let c): return c
        case .symbol(let s): return s
        }
    }
}

struct ShortcutEntry: Identifiable {
    let id = UUID()
    let keys: [KeyCapType]
    let label: String
}

// MARK: - Category View

struct ShortcutCategory: View {
    let title: String
    let icon: String
    let shortcuts: [ShortcutEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .textCase(.uppercase)
            }
            .padding(.bottom, 2)

            ForEach(shortcuts) { entry in
                ShortcutRow(entry: entry)
            }
        }
    }
}

// MARK: - Row View

struct ShortcutRow: View {
    let entry: ShortcutEntry

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(Array(entry.keys.enumerated()), id: \.offset) { _, key in
                    KeyCap(label: key.label)
                }
            }
            .frame(width: 90, alignment: .leading)

            Text(entry.label)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Key Cap

/// Renders a single keyboard key in macOS System Preferences style.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AppTheme.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(AppTheme.borderGlass.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
            )
    }
}
