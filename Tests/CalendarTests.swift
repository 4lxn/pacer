import XCTest
@testable import Autopiloto

@MainActor
final class CalendarTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        c.firstWeekday = 2   // Monday
        return c
    }()
    private func date(_ d: Int, _ h: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))! }

    func testMonthGridRespectsFirstWeekday() {
        let weeks = CalendarMonth.weeks(of: date(1), calendar: calendar)   // September 2026 starts on a Tuesday
        XCTAssertEqual(weeks.count, 5)
        XCTAssertNil(weeks[0][0])
        XCTAssertEqual(weeks[0][1].map { calendar.component(.day, from: $0) }, 1)
        XCTAssertEqual(weeks[4][2].map { calendar.component(.day, from: $0) }, 30)
        XCTAssertNil(weeks[4][3])
        XCTAssertEqual(CalendarMonth.weekdaySymbols(calendar: calendar).first, calendar.veryShortStandaloneWeekdaySymbols[1])
    }

    func testTomorrowCanBeRearrangedTodayAndUndone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plan = PlanStore(fileURL: dir.appendingPathComponent("plan.json")); plan.replace(with: Plan.blocks)
        let store = CompletionStore(fileURL: dir.appendingPathComponent("completions.json"), calendar: calendar)
        let mutator = DayMutator(plan: plan, completions: store, days: DayStore(directory: dir),
                                 metrics: MetricsStore(fileURL: dir.appendingPathComponent("metrics.json"), calendar: calendar),
                                 calendar: calendar, now: { self.date(16, 21) }, center: .noop)
        let tomorrow = date(17)
        // At 21:00 today, 06:15 tomorrow is not "past": the day's clock is its start.
        XCTAssertEqual(mutator.clock(for: tomorrow), calendar.startOfDay(for: tomorrow))
        guard case .moved = mutator.move("b14", to: .hm(6, 15), on: tomorrow) else { return XCTFail("run should move to 06:15 tomorrow") }
        XCTAssertEqual(mutator.effectivePlan(on: tomorrow).first { $0.id == "b14" }?.start, .hm(6, 15))
        XCTAssertEqual(mutator.effectivePlan(on: date(16)).first { $0.id == "b14" }?.start, Plan.blocks.first { $0.id == "b14" }?.start)   // today untouched
        XCTAssertTrue(mutator.undo())   // undo works for a future day too
        XCTAssertTrue(mutator.days.override(dayKey: "2026-09-17").isEmpty)

        // Yesterday is read-only for moves.
        if case .rejected = mutator.move("b14", to: .hm(6, 15), on: date(15)) {} else { XCTFail("past day must reject") }
        XCTAssertFalse(mutator.isEditable(date(15)))

        // Reset drops moves and one-offs together, undoable.
        _ = mutator.move("b14", to: .hm(6, 15), on: tomorrow)
        mutator.addExtra(Block(id: "x", label: "Dentist", kind: .fixed, start: .hm(9, 0), end: .hm(9, 30)), dayKey: "2026-09-17")
        mutator.resetDay(tomorrow)
        XCTAssertTrue(mutator.days.override(dayKey: "2026-09-17").isEmpty)
        XCTAssertTrue(mutator.undo())
        XCTAssertEqual(mutator.days.override(dayKey: "2026-09-17").extras.count, 1)
    }

    func testCoachToolsTakeADate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plan = PlanStore(fileURL: dir.appendingPathComponent("plan.json")); plan.replace(with: Plan.blocks)
        let completions = CompletionStore(fileURL: dir.appendingPathComponent("completions.json"), calendar: calendar)
        let now = { self.date(16, 21) }
        let mutator = DayMutator(plan: plan, completions: completions, days: DayStore(directory: dir),
                                 metrics: MetricsStore(fileURL: dir.appendingPathComponent("metrics.json"), calendar: calendar), calendar: calendar, now: now, center: .noop)
        let tools = CoachTools(plan: plan, completions: completions, food: FoodStore(fileURL: dir.appendingPathComponent("food.json"), calendar: calendar),
                               wardrobe: WardrobeStore(fileURL: dir.appendingPathComponent("wardrobe.json")), health: HealthStore(),
                               track: TrackStore(fileURL: dir.appendingPathComponent("track.json"), calendar: calendar), mutator: mutator, calendar: calendar, now: now)
        XCTAssertTrue(tools.run(name: "get_plan", input: ["date": "tomorrow"]).output.hasPrefix("2026-09-17"))
        XCTAssertFalse(tools.run(name: "move_today", input: ["id": "b14", "start": "06:15", "date": "tomorrow"]).isError)
        XCTAssertTrue(tools.run(name: "get_plan", input: ["date": "2026-09-17"]).output.contains("b14 | 06:15"))
        XCTAssertTrue(tools.run(name: "move_today", input: ["id": "b14", "start": "06:15", "date": "2026-09-15"]).isError)
        XCTAssertTrue(tools.run(name: "get_plan", input: ["date": "nope"]).isError)
        XCTAssertEqual(tools.run(name: "add_block", input: ["label": "Dentist", "kind": "fixed", "start": "09:00", "end": "09:30", "date": "tomorrow"]).summary, "Added Dentist for 2026-09-17")
        XCTAssertEqual(tools.run(name: "reset_day", input: ["date": "tomorrow"]).summary, "Reset 2026-09-17")
        XCTAssertTrue(mutator.days.override(dayKey: "2026-09-17").isEmpty)
    }
}
