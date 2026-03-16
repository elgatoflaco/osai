import SwiftUI

struct GhostIcon: View {
    var size: CGFloat = 48
    var animate: Bool = true
    var isProcessing: Bool = false
    var tint: Color = AppTheme.accent

    @State private var floatOffset: CGFloat = 0
    @State private var breatheScale: CGFloat = 1.0
    @State private var glowRadius: CGFloat = 12
    @State private var glowOpacity: Double = 0.4

    private let ghostGrid: [[Int]] = [
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

    private let cols = 16
    private let rows = 14

    var body: some View {
        let pixelSize = size / CGFloat(cols)

        Canvas { context, canvasSize in
            for row in 0..<rows {
                for col in 0..<cols {
                    let value = ghostGrid[row][col]
                    guard value != 0 else { continue }

                    let color: Color
                    switch value {
                    case 1: color = tint
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
        .scaleEffect(breatheScale)
        .offset(y: floatOffset)
        .shadow(color: tint.opacity(glowOpacity), radius: glowRadius, x: 0, y: 4)
        .onAppear {
            guard animate else { return }
            startIdleAnimation()
        }
        .onChange(of: isProcessing) { _, processing in
            guard animate else { return }
            if processing {
                startProcessingAnimation()
            } else {
                startIdleAnimation()
            }
        }
    }

    private func startIdleAnimation() {
        // Gentle float
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            floatOffset = -3
        }
        // Subtle breathing scale
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            breatheScale = 1.02
        }
        // Calm glow
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            glowRadius = 16
            glowOpacity = 0.5
        }
    }

    private func startProcessingAnimation() {
        // Faster, more active float
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            floatOffset = -5
        }
        // More pronounced pulse
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            breatheScale = 1.06
        }
        // Active glow pulse
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            glowRadius = 24
            glowOpacity = 0.7
        }
    }
}
