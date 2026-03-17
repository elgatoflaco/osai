import SwiftUI

// MARK: - Ghost Emotion States

enum GhostEmotion: String, CaseIterable {
    case idle
    case thinking
    case working
    case success
    case error
}

struct GhostIcon: View {
    var size: CGFloat = 48
    var animate: Bool = true
    var isProcessing: Bool = false
    var tint: Color = AppTheme.accent
    var emotion: GhostEmotion = .idle

    @State private var floatOffset: CGFloat = 0
    @State private var breatheScale: CGFloat = 1.0
    @State private var glowRadius: CGFloat = 12
    @State private var glowOpacity: Double = 0.4
    @State private var shakeOffset: CGFloat = 0
    @State private var flashColor: Color? = nil
    @State private var sparkleOpacity: Double = 0

    // MARK: - Pixel grids for each emotion's eye style

    /// Default idle eyes (round)
    private let gridIdle: [[Int]] = [
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

    /// Thinking eyes — squinted (thinner eye rows)
    private let gridThinking: [[Int]] = [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,2,2,1,1,1,1,1,2,2,1,1,1,0],
        [0,1,1,2,3,1,1,1,1,1,2,3,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],
        [0,1,0,0,0,0,1,0,0,0,1,0,0,0,1,0],
    ]

    /// Working eyes — wide open (larger pupils)
    private let gridWorking: [[Int]] = [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,2,2,2,1,1,1,2,2,2,1,1,1,0],
        [0,1,2,2,3,3,1,1,1,2,3,3,2,1,1,0],
        [0,1,2,3,3,3,1,1,1,2,3,3,2,1,1,0],
        [0,1,2,2,3,3,1,1,1,2,3,3,2,1,1,0],
        [0,1,1,2,2,2,1,1,1,2,2,2,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],
        [0,1,0,0,0,0,1,0,0,0,1,0,0,0,1,0],
    ]

    /// Success eyes — happy arcs (^_^)
    private let gridSuccess: [[Int]] = [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,2,1,2,1,1,1,1,2,1,2,1,1,0],
        [0,1,1,1,2,1,1,1,1,1,1,2,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],
        [0,1,0,0,0,0,1,0,0,0,1,0,0,0,1,0],
    ]

    /// Error eyes — X_X pattern
    private let gridError: [[Int]] = [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0],
        [0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,2,1,1,2,1,1,1,2,1,1,2,1,1,0],
        [0,1,1,2,2,1,1,1,1,1,2,2,1,1,1,0],
        [0,1,2,1,1,2,1,1,1,2,1,1,2,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
        [0,1,1,0,0,1,1,0,0,1,1,0,0,1,1,0],
        [0,1,0,0,0,0,1,0,0,0,1,0,0,0,1,0],
    ]

    private let cols = 16
    private let rows = 14

    /// Resolve which emotion to display — `isProcessing` maps to legacy behavior
    private var resolvedEmotion: GhostEmotion {
        if emotion != .idle { return emotion }
        return isProcessing ? .working : .idle
    }

    private var activeGrid: [[Int]] {
        switch resolvedEmotion {
        case .idle:     return gridIdle
        case .thinking: return gridThinking
        case .working:  return gridWorking
        case .success:  return gridSuccess
        case .error:    return gridError
        }
    }

    private var activeTint: Color {
        if let flash = flashColor { return flash }
        switch resolvedEmotion {
        case .idle:     return tint
        case .thinking: return Color.purple.opacity(0.85)
        case .working:  return tint
        case .success:  return Color.green
        case .error:    return Color.red
        }
    }

    var body: some View {
        let pixelSize = size / CGFloat(cols)
        let grid = activeGrid
        let currentTint = activeTint

        ZStack {
            // Sparkle burst overlay for success
            if sparkleOpacity > 0 {
                sparkleOverlay
            }

            Canvas { context, canvasSize in
                for row in 0..<rows {
                    for col in 0..<cols {
                        let value = grid[row][col]
                        guard value != 0 else { continue }

                        let color: Color
                        switch value {
                        case 1: color = currentTint
                        case 2: color = .white
                        case 3: color = Color(red: 20/255, green: 30/255, blue: 60/255)
                        default: continue
                        }

                        let rect = CGRect(
                            x: CGFloat(col) * pixelSize,
                            y: CGFloat(row) * pixelSize,
                            width: pixelSize + 0.5,
                            height: pixelSize + 0.5
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(width: size, height: CGFloat(rows) / CGFloat(cols) * size)
        }
        .scaleEffect(breatheScale)
        .offset(x: shakeOffset, y: floatOffset)
        .shadow(color: currentTint.opacity(glowOpacity), radius: glowRadius, x: 0, y: 4)
        .onAppear {
            guard animate else { return }
            applyAnimation(for: resolvedEmotion)
        }
        .onChange(of: isProcessing) { _, processing in
            guard animate else { return }
            if emotion == .idle {
                applyAnimation(for: processing ? .working : .idle)
            }
        }
        .onChange(of: emotion) { _, newEmotion in
            guard animate else { return }
            applyAnimation(for: newEmotion)
        }
    }

    // MARK: - Sparkle overlay

    private var sparkleOverlay: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let angle = Double(i) * 60.0
                let rad = angle * .pi / 180
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.06, height: size * 0.06)
                    .offset(
                        x: cos(rad) * size * 0.55,
                        y: sin(rad) * size * 0.55
                    )
                    .opacity(sparkleOpacity)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Animation helpers

    private func applyAnimation(for state: GhostEmotion) {
        // Reset transient states
        shakeOffset = 0
        flashColor = nil
        sparkleOpacity = 0

        switch state {
        case .idle:
            startIdleAnimation()
        case .thinking:
            startThinkingAnimation()
        case .working:
            startWorkingAnimation()
        case .success:
            startSuccessAnimation()
        case .error:
            startErrorAnimation()
        }
    }

    private func startIdleAnimation() {
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            floatOffset = -3
        }
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            breatheScale = 1.02
        }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            glowRadius = 16
            glowOpacity = 0.5
        }
    }

    private func startThinkingAnimation() {
        // Slower, deeper pulse
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            floatOffset = -5
        }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            breatheScale = 1.04
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            glowRadius = 20
            glowOpacity = 0.6
        }
    }

    private func startWorkingAnimation() {
        // Faster bounce, brighter glow
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            floatOffset = -6
        }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            breatheScale = 1.06
        }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            glowRadius = 26
            glowOpacity = 0.75
        }
    }

    private func startSuccessAnimation() {
        // Brief green flash + sparkle burst, then return to idle
        flashColor = .green
        withAnimation(.easeOut(duration: 0.3)) {
            sparkleOpacity = 1.0
            breatheScale = 1.08
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.4)) {
                sparkleOpacity = 0
                flashColor = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            startIdleAnimation()
        }
    }

    private func startErrorAnimation() {
        // Red tint + shake
        flashColor = .red
        // Shake sequence
        withAnimation(.linear(duration: 0.06)) { shakeOffset = -4 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.linear(duration: 0.06)) { shakeOffset = 4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.linear(duration: 0.06)) { shakeOffset = -3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.linear(duration: 0.06)) { shakeOffset = 3 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.linear(duration: 0.06)) { shakeOffset = 0 }
        }
        // Return to idle after brief red flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.3)) {
                flashColor = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            startIdleAnimation()
        }
    }
}
