import XCTest
@testable import Autopiloto

final class WorkoutSummaryTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    private func date(_ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    private func workout(_ activity: WorkoutActivity, day: Int, hour: Int = 18, minutes: Double = 30, meters: Double? = nil) -> WorkoutSummary {
        let start = date(day, hour)
        return WorkoutSummary(id: UUID(), activity: activity, start: start, end: start.addingTimeInterval(minutes * 60), distanceMeters: meters, kcal: nil, source: "Garmin Connect")
    }

    func testWeekTotalsOnlyCountThisWeek() {
        // Week of Mon 14 – Sun 20 Sep 2026; the 13th is the previous week.
        let workouts = [
            workout(.run, day: 15, minutes: 40, meters: 7000),
            workout(.strength, day: 15, hour: 20, minutes: 45),
            workout(.run, day: 13, minutes: 60, meters: 10000),
            workout(.walk, day: 16, minutes: 20),
        ]
        let totals = WeekTotals.make(workouts, weekOf: date(16, 12), calendar: calendar)
        XCTAssertEqual(totals, WeekTotals(runs: 1, runMeters: 7000, lifts: 1, minutes: 105))
        XCTAssertEqual(totals.runKilometers, 7.0)
    }

    func testAutoCompletionsPickTodaysMatchesOnly() {
        let run = Block(id: "run", label: "Run", kind: .window, start: .hm(18, 0), end: .hm(19, 0), autoComplete: .run)
        let gym = Block(id: "gym", label: "Gym", kind: .window, start: .hm(19, 15), end: .hm(20, 15), autoComplete: .strength)
        let plain = Block(id: "x", label: "X", kind: .fixed, start: .hm(9, 0), end: .hm(9, 5))
        let blocks = [run, gym, plain]
        let now = date(16, 21)

        XCTAssertEqual(DayLogic.autoCompletions(blocks, workouts: [workout(.run, day: 16)], now: now, completed: [], calendar: calendar), ["run"])
        XCTAssertEqual(DayLogic.autoCompletions(blocks, workouts: [workout(.run, day: 15)], now: now, completed: [], calendar: calendar), [])
        XCTAssertEqual(DayLogic.autoCompletions(blocks, workouts: [workout(.run, day: 16), workout(.strength, day: 16, hour: 19)], now: now, completed: ["run"], calendar: calendar), ["gym"])
        XCTAssertEqual(DayLogic.autoCompletions(blocks, workouts: [workout(.walk, day: 16)], now: now, completed: [], calendar: calendar), [])
    }

    func testPlanAutoCompleteWiring() {
        XCTAssertEqual(Plan.blocks.first { $0.id == "b14" }?.autoComplete, .run)
        XCTAssertEqual(Plan.blocks.first { $0.id == "b16" }?.autoComplete, .strength)
        XCTAssertEqual(Plan.blocks.first { $0.id == "b11" }?.autoComplete, .study)
        XCTAssertEqual(Plan.blocks.filter { $0.autoComplete != nil }.count, 3)
    }

    func testStudyBlockClosesAtTwentyMinutes() {
        let study = Block(id: "s", label: "Study", kind: .fixed, start: .hm(15, 45), end: .hm(17, 15), autoComplete: .study)
        let now = date(16, 18)
        XCTAssertEqual(DayLogic.autoCompletions([study], workouts: [], studyMinutesToday: 19, now: now, completed: [], calendar: calendar), [])
        XCTAssertEqual(DayLogic.autoCompletions([study], workouts: [], studyMinutesToday: 20, now: now, completed: [], calendar: calendar), ["s"])
        XCTAssertEqual(DayLogic.autoCompletions([study], workouts: [workout(.run, day: 16)], studyMinutesToday: 0, now: now, completed: [], calendar: calendar), [])
    }
}

final class TrainDepthTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()
    private func date(_ d: Int, _ h: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))! }
    private func run(_ d: Int, minutes: Double, km: Double) -> WorkoutSummary {
        WorkoutSummary(id: UUID(), activity: .run, start: date(d), end: date(d).addingTimeInterval(minutes * 60), distanceMeters: km * 1000, kcal: nil, source: "Garmin")
    }

    func testWeekBarsCoverEightWeeksOldestFirst() {
        let lift = WorkoutSummary(id: UUID(), activity: .strength, start: date(15), end: date(15).addingTimeInterval(3600), distanceMeters: nil, kcal: nil, source: "Hevy")
        let bars = WeekBar.make([run(16, minutes: 30, km: 5), run(9, minutes: 40, km: 7), lift], weeks: 8, now: date(16), calendar: calendar)
        XCTAssertEqual(bars.count, 8)
        XCTAssertEqual(bars.last?.runMinutes, 30)
        XCTAssertEqual(bars.last?.lifts, 1)
        XCTAssertEqual(bars.last?.strengthMinutes, 60)
        XCTAssertEqual(bars[6].runKilometers, 7)
        XCTAssertEqual(bars.first?.runMinutes, 0)
        XCTAssertLessThan(bars[0].weekStart, bars[1].weekStart)
    }

    func testPaceAndWeightStats() {
        let r = run(16, minutes: 30, km: 6)
        XCTAssertEqual(r.paceMinPerKm!, 5, accuracy: 0.001)
        XCTAssertEqual(WorkoutSummary.pace(5.5), "5:30 /km")
        XCTAssertNil(WorkoutSummary(id: UUID(), activity: .strength, start: date(1), end: date(1), distanceMeters: nil, kcal: nil, source: "").paceMinPerKm)

        let samples = (1...16).map { WeightSample(date: date($0, 8), kg: 75 - Double($0) * 0.1) }   // -0.1 kg/day
        let avg = WeightStats.movingAverage(samples, calendar: calendar)
        XCTAssertEqual(avg.count, 16)
        XCTAssertEqual(avg[0].kg, 74.9, accuracy: 0.001)                          // one sample in the window
        XCTAssertEqual(avg[6].kg, (74.9 + 74.3) / 2, accuracy: 0.001)             // days 1…7
        XCTAssertEqual(WeightStats.weeklyChange(samples, now: date(16), calendar: calendar)!, -0.7, accuracy: 0.001)
        XCTAssertNil(WeightStats.weeklyChange([], now: date(16), calendar: calendar))
    }
}

final class BestsAndReadinessTests: XCTestCase {
    func testBestsAndReadiness() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        func run(_ day: Int, min: Double, km: Double) -> WorkoutSummary {
            let s = c.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 7))!
            return WorkoutSummary(id: UUID(), activity: .run, start: s, end: s.addingTimeInterval(min * 60), distanceMeters: km * 1000, kcal: nil, source: "")
        }
        let b = TrainingBests.make([run(1, min: 30, km: 6), run(3, min: 26, km: 5), run(10, min: 20, km: 4.5)], calendar: c)
        XCTAssertEqual(b.fastest5kPace!, 5.0, accuracy: 0.01)   // the 4.5 km run doesn't count
        XCTAssertEqual(b.longestRunKm, 6)
        XCTAssertEqual(b.longestSessionMinutes, 30)
        XCTAssertEqual(b.biggestWeekMinutes, 56)
        XCTAssertFalse(Readiness.line(sleepMinutes: 5 * 60 + 20, restingHR: 54).good)
        XCTAssertTrue(Readiness.line(sleepMinutes: 7 * 60 + 10, restingHR: 54).good)
        XCTAssertFalse(Readiness.line(sleepMinutes: nil, restingHR: 62, typicalRestingHR: 54).good)
        XCTAssertEqual(Readiness.line(sleepMinutes: nil, restingHR: nil).text, "No sleep or heart data yet.")
    }
}

final class DayStreakTests: XCTestCase {
    func testStreakCountsBackFromTodayOrYesterday() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let now = c.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 20))!
        let scores: [Int: Double] = [16: 0.5, 15: 0.9, 14: 1.0, 13: 0.85, 12: 0.2, 11: 1.0]
        func score(_ d: Date) -> Double? { scores[c.component(.day, from: d)] }
        XCTAssertEqual(DayLogic.dayStreak(now: now, calendar: c, score: score), 3)      // today not there yet → 15, 14, 13
        XCTAssertEqual(DayLogic.dayStreak(now: now, calendar: c, score: { d in c.component(.day, from: d) == 16 ? 0.9 : score(d) }), 4)
        XCTAssertEqual(DayLogic.dayStreak(now: now, calendar: c, score: { _ in 0.1 }), 0)
    }
}
