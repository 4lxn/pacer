import XCTest
@testable import Autopiloto

final class ReplannerTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    private func at(_ h: Int, _ m: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: h, minute: m))! }

    private let study = Block(id: "study", label: "Study", kind: .fixed, start: .hm(15, 45), end: .hm(17, 15))
    private let run = Block(id: "run", label: "Run", kind: .window, start: .hm(18, 0), end: .hm(19, 0))
    private let gym = Block(id: "gym", label: "Gym", kind: .window, start: .hm(19, 15), end: .hm(20, 15))
    private let dinner = Block(id: "dinner", label: "Dinner", kind: .window, start: .hm(20, 30), end: .hm(21, 0))
    private let screens = Block(id: "screens", label: "Screens off", kind: .fixed, start: .hm(22, 30), end: .hm(22, 40))
    private let wake = Block(id: "wake", label: "Wake up", kind: .fixed, start: .hm(7, 30), end: .hm(7, 35), isAnchor: true)

    private func ctx(_ plan: [Block], now: Date, dayEnd: DateComponents = .hm(23, 15), completed: Set<String> = [], skipped: Set<String> = []) -> Replanner.Context {
        Replanner.Context(plan: plan, override: DayOverride(), now: now, dayEnd: dayEnd, completed: completed, skipped: skipped, calendar: calendar)
    }

    func testMovesIntoTheFirstGapAndPushesWindowsForward() {
        // Miss Study at 17:20; nothing fixed until 22:30 → Study 17:20–18:50, Run pushed to 18:50–19:50, Gym 19:50–20:50, Dinner 20:50–21:20.
        let outcome = Replanner.replan(study, in: ctx([wake, study, run, gym, dinner, screens], now: at(17, 20)))
        guard case let .moved(o, pushed, out) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(o.moved["study"], MovedTime(start: .hm(17, 20), end: .hm(18, 50)))
        XCTAssertEqual(pushed, ["run", "gym", "dinner"])
        XCTAssertEqual(o.moved["run"], MovedTime(start: .hm(18, 50), end: .hm(19, 50)))
        XCTAssertEqual(o.moved["dinner"], MovedTime(start: .hm(20, 50), end: .hm(21, 20)))
        XCTAssertTrue(out.isEmpty)
    }

    func testFixedBlocksAreObstaclesAndTheSearchStartsAfterNowRoundedUp() {
        let work = Block(id: "work", label: "Work", kind: .fixed, start: .hm(17, 30), end: .hm(19, 0))
        let outcome = Replanner.replan(study, in: ctx([study, work, dinner, screens], now: at(17, 22)))
        guard case let .moved(o, _, _) = outcome else { return XCTFail("\(outcome)") }
        // 17:25 → only 5 min before Work; next gap after Work at 19:00 fits 90 min before Screens off.
        XCTAssertEqual(o.moved["study"], MovedTime(start: .hm(19, 0), end: .hm(20, 30)))
    }

    func testShrinksToTheLargestGapWhenNothingFits() {
        let a = Block(id: "a", label: "A", kind: .fixed, start: .hm(18, 0), end: .hm(21, 0))
        let b = Block(id: "b", label: "B", kind: .fixed, start: .hm(21, 30), end: .hm(23, 0))
        let outcome = Replanner.replan(study, in: ctx([study, a, b], now: at(17, 20), dayEnd: .hm(23, 15)))
        guard case let .shrunk(o, minutes, _, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(minutes, 40)   // 17:20–18:00 is the largest gap (21:00–21:30 = 30, 23:00–23:15 = 15)
        XCTAssertEqual(o.moved["study"], MovedTime(start: .hm(17, 20), end: .hm(18, 0)))
    }

    func testNoRoomWhenEveryGapIsUnderTwentyMinutes() {
        let a = Block(id: "a", label: "A", kind: .fixed, start: .hm(17, 30), end: .hm(23, 0))
        XCTAssertEqual(Replanner.replan(study, in: ctx([study, a], now: at(17, 20), dayEnd: .hm(23, 15))), .noRoom)
        XCTAssertEqual(Replanner.replan(study, in: ctx([study], now: at(23, 20))), .noRoom)
    }

    func testCurrentWindowIsAnObstacleAndDoneOrSkippedBlocksAreNot() {
        // 18:30: the run is in progress → obstacle; gym is skipped → not one.
        let outcome = Replanner.replan(study, in: ctx([study, run, gym, dinner, screens], now: at(18, 30), skipped: ["gym"]))
        guard case let .moved(o, pushed, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(o.moved["study"], MovedTime(start: .hm(19, 0), end: .hm(20, 30)))
        XCTAssertEqual(pushed, [])           // dinner starts exactly when study ends: no overlap
        XCTAssertNil(o.moved["gym"])
    }

    func testPushedWindowPastDayEndIsDroppedAndReported() {
        let outcome = Replanner.replan(study, in: ctx([study, gym, dinner], now: at(19, 0), dayEnd: .hm(21, 0)))
        guard case let .moved(o, pushed, out) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(o.moved["study"], MovedTime(start: .hm(19, 0), end: .hm(20, 30)))
        XCTAssertEqual(pushed, [])
        XCTAssertEqual(out, ["gym"])          // dinner (20:30–21:00) still fits before day end
    }

    func testRefusals() {
        XCTAssertEqual(Replanner.replan(wake, in: ctx([wake], now: at(8))), .rejected("The anchor block stays where it is."))
        XCTAssertEqual(Replanner.replan(study, in: ctx([study], now: at(18), completed: ["study"])), .rejected("Already done."))
        let free = Block(id: "f", label: "Free", kind: .free)
        XCTAssertEqual(Replanner.replan(free, in: ctx([free], now: at(18))), .rejected("This block has no time."))
    }

    func testPlaceValidatesPastObstaclesAndDayEnd() {
        let c = ctx([study, run, gym, dinner, screens], now: at(17, 20))
        XCTAssertEqual(Replanner.place(study, at: .hm(17, 0), in: c), .rejected("That time already passed."))
        XCTAssertEqual(Replanner.place(study, at: .hm(22, 0), in: c), .rejected("That runs past the end of your day."))
        XCTAssertEqual(Replanner.place(study, at: .hm(22, 0), in: ctx([study, screens], now: at(17), dayEnd: .hm(23, 59))), .rejected("That overlaps Screens off."))
        guard case let .moved(o, pushed, _) = Replanner.place(study, at: .hm(18, 30), in: c) else { return XCTFail() }
        XCTAssertEqual(o.moved["study"], MovedTime(start: .hm(18, 30), end: .hm(20, 0)))
        XCTAssertEqual(pushed, ["run", "gym", "dinner"])   // run 18:00–19:00 intersects → pushed to 20:00
        XCTAssertEqual(o.moved["run"], MovedTime(start: .hm(20, 0), end: .hm(21, 0)))
    }

    func testEffectivePlanAppliesOverridesAndIgnoresOrphans() {
        var o = DayOverride()
        o.moved["study"] = MovedTime(start: .hm(19, 0), end: .hm(20, 30))
        o.moved["ghost"] = MovedTime(start: .hm(1, 0), end: .hm(2, 0))
        let plan = DayLogic.effectivePlan([study, run], override: o, on: at(12), calendar: calendar)
        XCTAssertEqual(plan.first { $0.id == "study" }?.start, .hm(19, 0))
        XCTAssertEqual(plan.first { $0.id == "run" }?.start, .hm(18, 0))
        XCTAssertEqual(plan.count, 2)
    }
}
