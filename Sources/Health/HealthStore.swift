import Foundation
import HealthKit
import Observation
import OSLog

/// HKObserverQueryCompletionHandler isn't Sendable; it is safe to call from any thread once.
private final class Completion: @unchecked Sendable {
    private let handler: HKObserverQueryCompletionHandler
    init(_ handler: @escaping HKObserverQueryCompletionHandler) { self.handler = handler }
    func call() { handler() }
}

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
    private(set) var workouts: [WorkoutSummary] = []   // last 8 weeks, newest first
    private(set) var weights: [WeightSample] = []      // last 90 days, oldest first
    private(set) var stepsToday = 0
    private(set) var stepsByDay: [(date: Date, steps: Int)] = []   // last 7 days, oldest first
    private(set) var sleepLastNightMinutes: Int?
    private(set) var restingHeartRate: Int?
    private(set) var isAuthorized = false
    private(set) var lastError: String?

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    private let store = HKHealthStore()
    private let log = Logger(subsystem: "com.alan.autopiloto", category: "health")
    private var observer: HKObserverQuery?
    private var seeded = false

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.bodyMass), HKQuantityType(.stepCount),
         HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate), HKCategoryType(.sleepAnalysis)]
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

    /// Wakes the app when a workout lands in Health (Garmin sync, Watch) so the matching block
    /// closes without opening the app. `onUpdate` runs on the main actor; the HealthKit completion
    /// handler is always called, or iOS stops delivering.
    func startObserving(onUpdate: @escaping @MainActor () async -> Void) {
        guard isAvailable, observer == nil else { return }
        let type = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [log] _, completion, error in
            if let error { log.error("Workout observer: \(error.localizedDescription)") }
            // The handler isn't Sendable; hop to the main actor with it boxed.
            let done = Completion(completion)
            Task { @MainActor in
                await onUpdate()
                done.call()
            }
        }
        observer = query
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { [log] ok, error in
            if let error { log.error("Background delivery: \(error.localizedDescription)") } else if ok { log.info("Background delivery on") }
        }
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        guard isAvailable, !seeded else { return }
        do {
            let eightWeeks = calendar.date(byAdding: .day, value: -56, to: now)!
            let ninetyDays = calendar.date(byAdding: .day, value: -90, to: now)!
            workouts = try await fetchWorkouts(since: eightWeeks)
            weights = try await fetchWeights(since: ninetyDays)
            stepsToday = try await fetchSteps(on: now, calendar: calendar)
            stepsByDay = try await fetchStepsByDay(days: 7, now: now, calendar: calendar)
            sleepLastNightMinutes = try await fetchSleep(now: now, calendar: calendar)
            restingHeartRate = try await fetchRestingHR(now: now, calendar: calendar)
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
    /// Screenshot mode: fake eight weeks of training so the Train tab renders without Health access.
    func seedForScreenshots(now: Date = .now, calendar: Calendar = .current) {
        var ws: [WorkoutSummary] = []
        for day in 0..<56 where day % 2 == 0 {
            let start = calendar.date(byAdding: .day, value: -day, to: calendar.date(bySettingHour: 19, minute: 20, second: 0, of: now)!)!
            let isRun = day % 4 == 0
            ws.append(WorkoutSummary(id: UUID(), activity: isRun ? .run : .strength, start: start, end: start.addingTimeInterval(isRun ? 2100 : 3600),
                                     distanceMeters: isRun ? 5200 + Double(day) * 30 : nil, kcal: isRun ? 380 : 290, source: isRun ? "Garmin Connect" : "Hevy", avgHeartRate: isRun ? 152 : 121))
        }
        workouts = ws
        weights = (0..<60).reversed().map { WeightSample(date: calendar.date(byAdding: .day, value: -$0, to: now)!, kg: 74.0 + Double($0) * 0.045 + Double(($0 * 7) % 5) * 0.12) }
        stepsToday = 6420
        stepsByDay = (0..<7).reversed().map { (calendar.startOfDay(for: calendar.date(byAdding: .day, value: -$0, to: now)!), [8200, 11400, 6900, 9800, 12100, 7400, 6420][6 - $0]) }
        sleepLastNightMinutes = 7 * 60 + 12
        restingHeartRate = 54
        isAuthorized = true
        seeded = true
    }

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
        if let sleep = sleepLastNightMinutes { lines.append("Sleep last night: \(sleep / 60) h \(sleep % 60) min") }
        if let rhr = restingHeartRate { lines.append("Resting HR: \(rhr) bpm") }
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
                source: w.sourceRevision.source.name,
                avgHeartRate: w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            )
        }
    }

    private func fetchStepsByDay(days: Int, now: Date, calendar: Calendar) async throws -> [(date: Date, steps: Int)] {
        var out: [(Date, Int)] = []
        for offset in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: min(end, now))
            let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate), options: .cumulativeSum)
            let sum = try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            out.append((start, Int(sum)))
        }
        return out
    }

    /// Minutes asleep between yesterday 18:00 and now.
    private func fetchSleep(now: Date, calendar: Calendar) async throws -> Int? {
        let from = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -1, to: now)!)!
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)], sortDescriptors: [], limit: 200)
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM].map(\.rawValue).reduce(into: []) { $0.insert($1) }
        let samples = try await descriptor.result(for: store).filter { asleep.contains($0.value) }
        guard !samples.isEmpty else { return nil }
        return Int(samples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60)
    }

    private func fetchRestingHR(now: Date, calendar: Calendar) async throws -> Int? {
        let from = calendar.date(byAdding: .day, value: -3, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate), predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        return try await descriptor.result(for: store).first.map { Int($0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
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
