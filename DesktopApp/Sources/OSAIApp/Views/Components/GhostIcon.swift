import SwiftUI

struct GhostIcon: View {
    var size: CGFloat = 48
    var animate: Bool = true
    var tint: Color = AppTheme.accent

    @State private var floatOffset: CGFloat = 0

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
        .offset(y: floatOffset)
        .shadow(color: tint.opacity(0.4), radius: 12, x: 0, y: 4)
        .onAppear {
            guard animate else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                floatOffset = -3
            }
        }
    }
}
