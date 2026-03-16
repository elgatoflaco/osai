import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = AppTheme.paddingMd
    var hoverEnabled: Bool = true

    @State private var isHovered = false

    init(padding: CGFloat = AppTheme.paddingMd, hoverEnabled: Bool = true, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.hoverEnabled = hoverEnabled
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial)
            .background(AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(
                        hoverEnabled && isHovered ? AppTheme.accent.opacity(0.25) : AppTheme.borderGlass,
                        lineWidth: hoverEnabled && isHovered ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(isHovered && hoverEnabled ? 0.3 : 0.2), radius: isHovered && hoverEnabled ? 20 : 16, x: 0, y: isHovered && hoverEnabled ? 10 : 8)
            .scaleEffect(isHovered && hoverEnabled ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct HoverGlassCard<Content: View>: View {
    let content: Content
    @State private var isHovered = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.paddingMd)
            .background(.ultraThinMaterial)
            .background(AppTheme.bgGlass)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(isHovered ? AppTheme.accent.opacity(0.3) : AppTheme.borderGlass, lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 24 : 16, x: 0, y: isHovered ? 12 : 8)
            .offset(y: isHovered ? -2 : 0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
