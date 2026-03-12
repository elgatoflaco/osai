import Foundation
import HealthKit
import Combine

final class HealthManager: ObservableObject {
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

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKObserverQuery?
    private var stepsQuery: HKObserverQuery?
    private var refreshTimer: Timer?

    // Health data types we need
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let standHoursType = HKCategoryType.categoryType(forIdentifier: .appleStandHour)!

    // Activity goals (defaults, will be updated from HealthKit)
    private var moveGoal: Double = 500 // kcal
    private var exerciseGoal: Double = 30 // minutes
    private var standGoal: Double = 12 // hours

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run { authorizationError = "HealthKit not available on this device" }
            return
        }

        let readTypes: Set<HKObjectType> = [
            heartRateType,
            stepCountType,
            activeEnergyType,
            exerciseTimeType,
            standHoursType
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
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        async let moveResult = fetchActiveEnergy(predicate: predicate)
        async let exerciseResult = fetchExerciseMinutes(predicate: predicate)
        async let standResult = fetchStandHours(predicate: predicate)

        let (move, exercise, stand) = await (moveResult, exerciseResult, standResult)

        await MainActor.run {
            movePercent = min(move / moveGoal, 1.5)
            exercisePercent = min(exercise / exerciseGoal, 1.5)
            standPercent = min(stand / standGoal, 1.5)
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

    // MARK: - Health Summary

    func generateHealthSummary() async -> String {
        await refreshAll()
        return HealthSnapshot(
            heartRate: currentHeartRate,
            steps: stepsToday,
            movePercent: movePercent,
            exercisePercent: exercisePercent,
            standPercent: standPercent
        ).summary
    }

    func currentSnapshot() -> HealthSnapshot {
        return HealthSnapshot(
            heartRate: currentHeartRate,
            steps: stepsToday,
            movePercent: movePercent,
            exercisePercent: exercisePercent,
            standPercent: standPercent
        )
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
        await fetchHeartRate()
        await fetchSteps()
        await fetchActivityRings()
    }

    // MARK: - Cleanup

    func stopObserving() {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
        if let query = stepsQuery {
            healthStore.stop(query)
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
