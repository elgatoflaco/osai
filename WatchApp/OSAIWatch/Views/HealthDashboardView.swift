import SwiftUI
import WatchKit

struct HealthDashboardView: View {
    @EnvironmentObject var healthManager: HealthManager
    @EnvironmentObject var connection: AgentConnection
    @EnvironmentObject var settings: WatchSettings
    @State private var crownValue: Double = 0
    @State private var isSendingSummary: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !healthManager.isAuthorized {
                    authorizationCard
                } else {
                    // Heart Rate
                    heartRateCard

                    // Steps
                    stepsCard

                    // Activity Rings
                    activityRingsCard

                    // Send Summary
                    sendSummaryButton
                }
            }
            .padding(.horizontal, 4)
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: 4,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: settings.hapticFeedbackEnabled
        )
        .navigationTitle("Health")
        .onAppear {
            if healthManager.isAuthorized {
                Task { await healthManager.refreshAll() }
            }
        }
    }

    // MARK: - Authorization Card

    private var authorizationCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text("Health Access Required")
                .font(.callout)
                .fontWeight(.semibold)

            Text("Grant access to view heart rate, steps, and activity data.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = healthManager.authorizationError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await healthManager.requestAuthorization() }
            } label: {
                Label("Authorize", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Heart Rate Card

    private var heartRateCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: healthManager.currentHeartRate > 0)

                Text("Heart Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Int(healthManager.currentHeartRate))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)

                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Trend indicator
                if healthManager.heartRateTrend.count >= 2 {
                    trendIndicator
                }
            }

            // Trend sparkline
            if !healthManager.heartRateTrend.isEmpty {
                heartRateSparkline
                    .frame(height: 30)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button {
                Task {
                    await connection.sendMessage(text: "My current heart rate is \(Int(healthManager.currentHeartRate)) BPM")
                }
            } label: {
                Label("Send to Agent", systemImage: "paperplane")
            }
        }
    }

    private var trendIndicator: some View {
        Group {
            let trend = healthManager.heartRateTrend
            let recent = trend.suffix(5).reduce(0, +) / Double(min(trend.count, 5))
            let older = trend.prefix(5).reduce(0, +) / Double(min(trend.count, 5))
            let diff = recent - older

            if abs(diff) < 3 {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if diff > 0 {
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
    }

    private var heartRateSparkline: some View {
        GeometryReader { geometry in
            let data = healthManager.heartRateTrend
            let minVal = (data.min() ?? 0) - 5
            let maxVal = (data.max() ?? 100) + 5
            let range = maxVal - minVal
            let stepX = geometry.size.width / Double(max(data.count - 1, 1))

            Path { path in
                for (index, value) in data.enumerated() {
                    let x = Double(index) * stepX
                    let y = geometry.size.height - ((value - minVal) / range * geometry.size.height)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
        }
    }

    // MARK: - Steps Card

    private var stepsCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.green)

                Text("Steps Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            let stepGoal: Double = 10000
            let progress = min(Double(healthManager.stepsToday) / stepGoal, 1.0)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(healthManager.stepsToday)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)

                Text("/ \(Int(stepGoal))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .frame(width: 50, height: 50)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Activity Rings Card

    private var activityRingsCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)

                Text("Activity Rings")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Activity rings visualization
            ZStack {
                // Stand ring (outer)
                activityRing(
                    progress: healthManager.standPercent,
                    color: .cyan,
                    lineWidth: 8,
                    size: 70
                )

                // Exercise ring (middle)
                activityRing(
                    progress: healthManager.exercisePercent,
                    color: .green,
                    lineWidth: 8,
                    size: 52
                )

                // Move ring (inner)
                activityRing(
                    progress: healthManager.movePercent,
                    color: .red,
                    lineWidth: 8,
                    size: 34
                )
            }
            .frame(height: 80)

            // Legend
            HStack(spacing: 12) {
                ringLabel(color: .red, text: "Move", percent: healthManager.movePercent)
                ringLabel(color: .green, text: "Exercise", percent: healthManager.exercisePercent)
                ringLabel(color: .cyan, text: "Stand", percent: healthManager.standPercent)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func activityRing(progress: Double, color: Color, lineWidth: CGFloat, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: min(progress, 1.5))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: progress)
        }
    }

    private func ringLabel(color: Color, text: String, percent: Double) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(Int(percent * 100))%")
                .font(.system(size: 9, weight: .bold))

            Text(text)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Send Summary

    private var sendSummaryButton: some View {
        Button {
            isSendingSummary = true
            Task {
                let summary = await healthManager.generateHealthSummary()
                await connection.sendMessage(text: "[Health Summary]\n\(summary)")
                await MainActor.run {
                    isSendingSummary = false
                    if settings.hapticFeedbackEnabled {
                        WKInterfaceDevice.current().play(.success)
                    }
                }
            }
        } label: {
            HStack {
                if isSendingSummary {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text("Send Summary to Agent")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(isSendingSummary || connection.connectionState != .connected)
    }
}

#Preview {
    NavigationStack {
        HealthDashboardView()
            .environmentObject(HealthManager())
            .environmentObject(AgentConnection())
            .environmentObject(WatchSettings())
    }
}
