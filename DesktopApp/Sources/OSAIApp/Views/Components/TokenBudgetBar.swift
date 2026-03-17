import SwiftUI

/// A compact, always-visible progress bar showing daily budget consumption.
/// Sits below the chat header as a thin 3px bar with color-coded status.
struct TokenBudgetBar: View {
    @EnvironmentObject var appState: AppState

    var percentage: Double {
        guard appState.dailyBudget > 0 else { return 0 }
        return min(appState.costToday / appState.dailyBudget, 1.0)
    }

    var barColor: Color {
        if percentage < 0.5 { return AppTheme.success }
        if percentage < 0.8 { return AppTheme.warning }
        return AppTheme.error
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.bgCard.opacity(0.3))
                Rectangle()
                    .fill(barColor)
                    .frame(width: geo.size.width * percentage)
                    .animation(.easeInOut(duration: 0.5), value: percentage)
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
        .help("$\(String(format: "%.2f", appState.costToday)) / $\(String(format: "%.2f", appState.dailyBudget)) daily budget (\(Int(percentage * 100))%)")
    }
}
