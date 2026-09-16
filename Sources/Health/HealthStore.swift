import Foundation
import HealthKit
import Observation
import OSLog

struct WeightSample: Identifiable, Hashable, Sendable {
    let date: Date
    let kg: Double
    var id: Date { date }
}

/// Thin wrapper over HealthKit. Garmin Connect and Strava write here when the user enables Apple
/// Health in their apps, so this is the only integration the app needs.
@Observable
@MainActor
final class HealthStore {
    private(set) var workouts: [WorkoutSummary] = []   // last 7 days, newest first
    private(set) var weights: [WeightSample] = []      // last 30 days, oldest first
    private(set) var stepsToday = 0
    private(set) var isAuthorized = false
    private(set) var lastError: String?

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    private let store = HKHealthStore()
    private let log = Logger(subsystem: "com.alan.autopiloto", category: "health")

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.bodyMass), HKQuantityType(.stepCount)]
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [HKQuantityType(.bodyMass)], read: readTypes)
            isAuthorized = true
        } catch {
            lastError = error.localizedDescription
            log.error("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        guard isAvailable else { return }
        do {
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            let monthAgo = calendar.date(byAdding: .day, value: -30, to: now)!
            workouts = try await fetchWorkouts(since: weekAgo)
            weights = try await fetchWeights(since: monthAgo)
            stepsToday = try await fetchSteps(on: now, calendar: calendar)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("HealthKit refresh failed: \(error.localizedDescription)")
        }
    }

    func saveWeight(kg: Double, at date: Date = .now) async {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: quantity, start: date, end: date)
        do {
            try await store.save(sample)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    #if DEBUG
    // ponytail: simulator-only seed so the pipeline is verifiable without a watch; Release builds drop it.
    func addTestRun(minutes: Double = 30, km: Double = 5) async {
        let end = Date.now
        let start = end.addingTimeInterval(-minutes * 60)
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            let distance = HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: km * 1000),
                start: start, end: end
            )
            try await builder.addSamples([distance])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }
    #endif

    /// Section for the Coach snapshot: today's workouts, week totals, latest weight.
    func coachSummary(now: Date, calendar: Calendar) -> String {
        guard isAvailable, isAuthorized else { return "" }
        var lines = ["## Training (Apple Health)"]
        let today = workouts.filter { calendar.isDate($0.start, inSameDayAs: now) }
        if today.isEmpty {
            lines.append("No workout logged today yet.")
        } else {
            lines.append("Today: " + today.map { w in
                var s = "\(w.activity.rawValue) \(Int(w.duration / 60)) min"
                if let m = w.distanceMeters, m > 0 { s += String(format: " %.1f km", m / 1000) }
                return s + " (\(w.source))"
            }.joined(separator: "; "))
        }
        let week = WeekTotals.make(workouts, weekOf: now, calendar: calendar)
        lines.append(String(format: "This week: %d runs, %.1f km, %d strength sessions, %d min", week.runs, week.runKilometers, week.lifts, week.minutes))
        if let last = weights.last {
            lines.append(String(format: "Latest weight: %.1f kg (%@)", last.kg, last.date.formatted(date: .abbreviated, time: .omitted)))
        }
        lines.append("Steps today: \(stepsToday)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Queries

    private func fetchWorkouts(since: Date) async throws -> [WorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100
        )
        let results = try await descriptor.result(for: store)
        return results.map { w in
            WorkoutSummary(
                id: w.uuid,
                activity: Self.activity(for: w.workoutActivityType),
                start: w.startDate,
                end: w.endDate,
                distanceMeters: w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                    ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter()),
                kcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                source: w.sourceRevision.source.name
            )
        }
    }

    private func fetchWeights(since: Date) async throws -> [WeightSample] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: 200
        )
        return try await descriptor.result(for: store).map {
            WeightSample(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    private func fetchSteps(on date: Date, calendar: Calendar) async throws -> Int {
        let start = calendar.startOfDay(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum
        )
        let sum = try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        return Int(sum)
    }

    static func activity(for type: HKWorkoutActivityType) -> WorkoutActivity {
        switch type {
        case .running: .run
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: .strength
        case .walking, .hiking: .walk
        case .cycling: .cycle
        default: .other
        }
    }
}
