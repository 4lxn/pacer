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
        XCTAssertEqual(Plan.blocks.filter { $0.autoComplete != nil }.count, 2)
    }
}
