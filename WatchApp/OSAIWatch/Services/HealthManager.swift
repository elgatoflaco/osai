import Foundation
import HealthKit
import Combine

final class HealthManager: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published var isAuthorized: Bool = false
    @Published var currentHeartRate: Double = 0
    @Published var heartRateTrend: [Double] = []
    @Published var stepsToday: Int = 0
    @Published var movePercent: Double = 0
    @Published var exercisePercent: Double = 0
    @Published var standPercent: Double = 0
    @Published var lastUpdated: Date?
    @Published var authorizationError: String?

    // Enhanced health metrics
    @Published var restingHeartRate: Double = 0
    @Published var heartRateVariability: Double = 0
    @Published var sleepHoursLastNight: Double = 0
    @Published var sleepQuality: SleepQuality = .unknown
    @Published var activeCalories: Double = 0
    @Published var recentWorkouts: [WorkoutSummary] = []
    @Published var insights: [HealthInsight] = []
    @Published var weeklyStepTrend: [Int] = []
    @Published var weeklyHeartRateTrend: [Double] = []

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKObserverQuery?
    private var stepsQuery: HKObserverQuery?
    private var workoutQuery: HKObserverQuery?
    private var refreshTimer: Timer?

    // Health data types
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let standHoursType = HKCategoryType.categoryType(forIdentifier: .appleStandHour)!
    private let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
    private let workoutType = HKWorkoutType.workoutType()

    // Activity goals
    private var moveGoal: Double = 500
    private var exerciseGoal: Double = 30
    private var standGoal: Double = 12

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run { authorizationError = "HealthKit not available on this device" }
            return
        }

        let readTypes: Set<HKObjectType> = [
            heartRateType, stepCountType, activeEnergyType, exerciseTimeType,
            standHoursType, restingHRType, hrvType, sleepType, workoutType
        ]

        do {
            try await healthStore.requestAuthorization(toShare: Set(), read: readTypes)
            await MainActor.run {
                isAuthorized = true
                authorizationError = nil
            }
            await refreshAll()
            setupBackgroundObservers()
            startPeriodicRefresh()
        } catch {
            await MainActor.run {
                isAuthorized = false
                authorizationError = error.localizedDescription
            }
        }
    }

    // MARK: - Fetch Heart Rate

    func fetchHeartRate() async {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let now = Date()
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: oneHourAgo, end: now, options: .strictEndDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 60,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, error in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume()
                    return
                }

                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let rates = samples.map { $0.quantity.doubleValue(for: bpmUnit) }
                let latest = rates.first ?? 0

                Task { @MainActor in
                    self.currentHeartRate = latest
                    self.heartRateTrend = Array(rates.prefix(20).reversed())
                    self.lastUpdated = Date()
                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Resting Heart Rate

    func fetchRestingHeartRate() async {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: oneDayAgo, end: now, options: .strictEndDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHRType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, _ in
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let rhr = (samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: bpmUnit) ?? 0

                Task { @MainActor in
                    self?.restingHeartRate = rhr
                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch HRV

    func fetchHRV() async {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: oneDayAgo, end: now, options: .strictEndDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, _ in
                let msUnit = HKUnit.secondUnit(with: .milli)
                let hrv = (samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: msUnit) ?? 0

                Task { @MainActor in
                    self?.heartRateVariability = hrv
                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Sleep

    func fetchSleep() async {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let yesterday6PM = Calendar.current.date(byAdding: .hour, value: -30, to: startOfToday)!
        let predicate = HKQuery.predicateForSamples(withStart: yesterday6PM, end: now, options: .strictEndDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [weak self] _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume()
                    return
                }

                // Filter for asleep states (inBed, asleepCore, asleepDeep, asleepREM)
                let asleepSamples = samples.filter { sample in
                    let value = sample.value
                    return value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                           value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                           value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                           value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }

                var totalSleepSeconds: TimeInterval = 0
                var deepSleepSeconds: TimeInterval = 0
                var remSleepSeconds: TimeInterval = 0

                for sample in asleepSamples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    totalSleepSeconds += duration
                    if sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                        deepSleepSeconds += duration
                    } else if sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                        remSleepSeconds += duration
                    }
                }

                let totalHours = totalSleepSeconds / 3600
                let quality: SleepQuality
                if totalHours <= 0 {
                    quality = .unknown
                } else if totalHours < 5 {
                    quality = .poor
                } else if totalHours < 6.5 {
                    quality = .fair
                } else if totalHours < 8 {
                    quality = .good
                } else {
                    quality = .excellent
                }

                Task { @MainActor in
                    self?.sleepHoursLastNight = totalHours
                    self?.sleepQuality = quality
                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Steps

    func fetchSteps() async {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { [weak self] _, statistics, error in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0

                Task { @MainActor in
                    self.stepsToday = Int(steps)
                    self.lastUpdated = Date()
                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Activity Rings

    func fetchActivityRings() async {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let move = await fetchActiveEnergy(predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate))
        let exercise = await fetchExerciseMinutes(predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate))
        let stand = await fetchStandHours(predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate))

        await MainActor.run {
            movePercent = min(move / moveGoal, 1.5)
            exercisePercent = min(exercise / exerciseGoal, 1.5)
            standPercent = min(stand / standGoal, 1.5)
            activeCalories = move
            lastUpdated = Date()
        }
    }

    private func fetchActiveEnergy(predicate: NSPredicate) async -> Double {
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let kcal = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }
            healthStore.execute(query)
        }
    }

    private func fetchExerciseMinutes(predicate: NSPredicate) async -> Double {
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: exerciseTimeType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let minutes = statistics?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                continuation.resume(returning: minutes)
            }
            healthStore.execute(query)
        }
    }

    private func fetchStandHours(predicate: NSPredicate) async -> Double {
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: standHoursType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let standCount = samples?.filter { sample in
                    (sample as? HKCategorySample)?.value == HKCategoryValueAppleStandHour.stood.rawValue
                }.count ?? 0
                continuation.resume(returning: Double(standCount))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Recent Workouts

    func fetchRecentWorkouts() async {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let now = Date()
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: threeDaysAgo, end: now, options: .strictEndDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 10,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume()
                    return
                }

                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let summaries = workouts.map { workout -> WorkoutSummary in
                    let typeName = Self.workoutTypeName(workout.workoutActivityType)
                    let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0

                    // Get average heart rate from workout statistics if available
                    var avgHR: Double = 0
                    if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
                       let stats = workout.statistics(for: hrType),
                       let avg = stats.averageQuantity() {
                        avgHR = avg.doubleValue(for: bpmUnit)
                    }

                    return WorkoutSummary(
                        type: typeName,
                        duration: workout.duration,
                        calories: calories,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        averageHeartRate: avgHR
                    )
                }

                Task { @MainActor in
                    self?.recentWorkouts = summaries
                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Weekly Trends

    func fetchWeeklyStepTrend() async {
        let calendar = Calendar.current
        let now = Date()
        var dailySteps: [Int] = []

        for dayOffset in (0..<7).reversed() {
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: now)!)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)

            let steps: Int = await withCheckedContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: stepCountType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, _ in
                    let count = Int(statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                    continuation.resume(returning: count)
                }
                healthStore.execute(query)
            }
            dailySteps.append(steps)
        }

        await MainActor.run {
            weeklyStepTrend = dailySteps
        }
    }

    // MARK: - Health Insights

    func generateInsights() async {
        var newInsights: [HealthInsight] = []

        // Heart rate insights
        if currentHeartRate > 100 {
            newInsights.append(HealthInsight(
                title: "Elevated Heart Rate",
                detail: "Your heart rate is \(Int(currentHeartRate)) BPM, which is above resting. Consider taking a break if you're not exercising.",
                icon: "heart.fill",
                category: .heartRate,
                priority: .high
            ))
        } else if currentHeartRate > 0 && currentHeartRate < 50 {
            newInsights.append(HealthInsight(
                title: "Low Heart Rate",
                detail: "Your heart rate is \(Int(currentHeartRate)) BPM. This is normal if you're very fit, otherwise consult a doctor.",
                icon: "heart.fill",
                category: .heartRate,
                priority: .high
            ))
        }

        // HRV insight
        if heartRateVariability > 0 {
            if heartRateVariability > 50 {
                newInsights.append(HealthInsight(
                    title: "Good Recovery",
                    detail: "Your HRV is \(Int(heartRateVariability))ms, indicating good recovery and stress resilience.",
                    icon: "waveform.path.ecg",
                    category: .recovery,
                    priority: .low
                ))
            } else if heartRateVariability < 20 {
                newInsights.append(HealthInsight(
                    title: "Recovery Needed",
                    detail: "Your HRV is \(Int(heartRateVariability))ms. Consider rest and stress management today.",
                    icon: "waveform.path.ecg",
                    category: .recovery,
                    priority: .high
                ))
            }
        }

        // Sleep insights
        if sleepHoursLastNight > 0 {
            if sleepHoursLastNight < 6 {
                newInsights.append(HealthInsight(
                    title: "Low Sleep",
                    detail: "You slept \(String(format: "%.1f", sleepHoursLastNight))h last night. Aim for 7-9 hours for optimal health.",
                    icon: "moon.zzz",
                    category: .sleep,
                    priority: .high
                ))
            } else if sleepHoursLastNight >= 7 && sleepHoursLastNight <= 9 {
                newInsights.append(HealthInsight(
                    title: "Great Sleep",
                    detail: "You slept \(String(format: "%.1f", sleepHoursLastNight))h last night. Well within the recommended range!",
                    icon: "moon.stars.fill",
                    category: .sleep,
                    priority: .low
                ))
            }
        }

        // Activity insights
        let stepGoal = 10000
        let stepPercent = Double(stepsToday) / Double(stepGoal)
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= 14 && stepPercent < 0.3 {
            newInsights.append(HealthInsight(
                title: "Low Activity",
                detail: "You've only reached \(Int(stepPercent * 100))% of your step goal. Try taking a walk!",
                icon: "figure.walk",
                category: .activity,
                priority: .normal
            ))
        } else if stepPercent >= 1.0 {
            newInsights.append(HealthInsight(
                title: "Step Goal Reached!",
                detail: "You've hit \(stepsToday) steps today. Great job staying active!",
                icon: "figure.walk",
                category: .activity,
                priority: .low
            ))
        }

        // Move ring insight
        if movePercent >= 1.0 {
            newInsights.append(HealthInsight(
                title: "Move Ring Complete",
                detail: "You've closed your move ring with \(Int(activeCalories)) active calories!",
                icon: "flame.fill",
                category: .activity,
                priority: .low
            ))
        }

        // Workout insight
        if let lastWorkout = recentWorkouts.first {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let timeAgo = formatter.localizedString(for: lastWorkout.startDate, relativeTo: Date())
            newInsights.append(HealthInsight(
                title: "Last Workout",
                detail: "\(lastWorkout.type) for \(lastWorkout.formattedDuration) (\(Int(lastWorkout.calories)) cal) \(timeAgo)",
                icon: "figure.run",
                category: .activity
            ))
        }

        // Sort by priority (highest first)
        newInsights.sort { $0.priority > $1.priority }

        await MainActor.run {
            insights = newInsights
        }
    }

    // MARK: - Health Summary

    func generateHealthSummary() async -> String {
        await refreshAll()
        return currentSnapshot().summary
    }

    func currentSnapshot() -> HealthSnapshot {
        return HealthSnapshot(
            heartRate: currentHeartRate,
            steps: stepsToday,
            movePercent: movePercent,
            exercisePercent: exercisePercent,
            standPercent: standPercent,
            sleepHours: sleepHoursLastNight,
            sleepQuality: sleepQuality,
            activeCalories: activeCalories,
            restingHeartRate: restingHeartRate,
            heartRateVariability: heartRateVariability
        )
    }

    /// Generate a proactive health suggestion for the agent
    func generateProactiveSuggestion() -> String? {
        let hour = Calendar.current.component(.hour, from: Date())

        // Morning suggestion
        if hour >= 7 && hour <= 9 && sleepHoursLastNight > 0 && sleepHoursLastNight < 6 {
            return "[Health Alert] User slept only \(String(format: "%.1f", sleepHoursLastNight))h. Suggest lighter workload and hydration."
        }

        // Afternoon low activity
        if hour >= 14 && hour <= 16 && stepsToday < 3000 {
            return "[Health Suggestion] User has been sedentary (\(stepsToday) steps by afternoon). Suggest a walking break."
        }

        // High heart rate outside workout
        if currentHeartRate > 110 && recentWorkouts.first.map({ Date().timeIntervalSince($0.endDate) > 1800 }) ?? true {
            return "[Health Alert] Elevated resting heart rate (\(Int(currentHeartRate)) BPM). User may be stressed."
        }

        // Low HRV
        if heartRateVariability > 0 && heartRateVariability < 20 {
            return "[Health Suggestion] Low HRV (\(Int(heartRateVariability))ms) suggests poor recovery. Suggest stress reduction."
        }

        return nil
    }

    // MARK: - Background Observers

    private func setupBackgroundObservers() {
        // Heart rate observer
        heartRateQuery = HKObserverQuery(
            sampleType: heartRateType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task {
                await self?.fetchHeartRate()
            }
            completionHandler()
        }
        if let query = heartRateQuery {
            healthStore.execute(query)
        }

        // Steps observer
        stepsQuery = HKObserverQuery(
            sampleType: stepCountType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task {
                await self?.fetchSteps()
            }
            completionHandler()
        }
        if let query = stepsQuery {
            healthStore.execute(query)
        }

        // Workout observer
        workoutQuery = HKObserverQuery(
            sampleType: workoutType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task {
                await self?.fetchRecentWorkouts()
            }
            completionHandler()
        }
        if let query = workoutQuery {
            healthStore.execute(query)
        }
    }

    // MARK: - Periodic Refresh

    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }

    func refreshAll() async {
        guard isAuthorized else { return }
        async let hr: () = fetchHeartRate()
        async let steps: () = fetchSteps()
        async let rings: () = fetchActivityRings()
        async let rhr: () = fetchRestingHeartRate()
        async let hrv: () = fetchHRV()
        async let sleep: () = fetchSleep()
        async let workouts: () = fetchRecentWorkouts()

        _ = await (hr, steps, rings, rhr, hrv, sleep, workouts)
        await generateInsights()
    }

    // MARK: - Cleanup

    func stopObserving() {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
        if let query = stepsQuery {
            healthStore.stop(query)
        }
        if let query = workoutQuery {
            healthStore.stop(query)
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Workout Type Names

    static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .dance: return "Dance"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stairs"
        case .pilates: return "Pilates"
        case .crossTraining: return "Cross Training"
        default: return "Workout"
        }
    }
}
