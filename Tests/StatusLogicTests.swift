import XCTest
@testable import Autopiloto

final class StatusLogicTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    private let block = Block(id: "x", label: "X", kind: .window, start: .hm(10, 0), end: .hm(10, 30))
    private let free = Block(id: "f", label: "F", kind: .free)

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func testDone() {
        XCTAssertEqual(block.status(now: date(2026, 9, 16, 12, 0), completed: ["x"], calendar: calendar), .done)
    }

    func testFree() {
        XCTAssertEqual(free.status(now: date(2026, 9, 16, 12, 0), completed: [], calendar: calendar), .free)
        XCTAssertEqual(free.status(now: date(2026, 9, 16, 12, 0), completed: ["f"], calendar: calendar), .done)
    }

    func testUpcoming() {
        XCTAssertEqual(block.status(now: date(2026, 9, 16, 9, 59, 59), completed: [], calendar: calendar), .upcoming)
    }

    func testCurrentAtExactStartAndEnd() {
        XCTAssertEqual(block.status(now: date(2026, 9, 16, 10, 0), completed: [], calendar: calendar), .current)
        XCTAssertEqual(block.status(now: date(2026, 9, 16, 10, 15), completed: [], calendar: calendar), .current)
        XCTAssertEqual(block.status(now: date(2026, 9, 16, 10, 30), completed: [], calendar: calendar), .current)
    }

    func testMissedOneSecondAfterEnd() {
        XCTAssertEqual(block.status(now: date(2026, 9, 16, 10, 30, 1), completed: [], calendar: calendar), .missed)
    }

    func testDayKeyRollsOverAtMidnight() {
        XCTAssertEqual(DayLogic.dayKey(date(2026, 9, 16, 23, 59, 59), calendar: calendar), "2026-09-16")
        XCTAssertEqual(DayLogic.dayKey(date(2026, 9, 17, 0, 0, 0), calendar: calendar), "2026-09-17")
    }

    func testStatusUsesTheNewDayAfterMidnight() {
        // Yesterday's "done" set does not apply: a fresh day starts upcoming.
        let lateYesterday = date(2026, 9, 16, 23, 59)
        let earlyToday = date(2026, 9, 17, 0, 1)
        XCTAssertEqual(block.status(now: lateYesterday, completed: [], calendar: calendar), .missed)
        XCTAssertEqual(block.status(now: earlyToday, completed: [], calendar: calendar), .upcoming)
    }

    func testDSTTransitionUsesWallClock() {
        // Mexico City has no DST since 2022; use New York's spring-forward day (2026-03-08) instead.
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let now = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 10, minute: 10))!
        XCTAssertEqual(block.status(now: now, completed: [], calendar: ny), .current)
        let hour = ny.component(.hour, from: block.startDate(on: now, calendar: ny)!)
        XCTAssertEqual(hour, 10)
    }

    func testSortedPutsFreeLast() {
        let a = Block(id: "a", label: "A", kind: .fixed, start: .hm(9, 0), end: .hm(9, 5))
        let b = Block(id: "b", label: "B", kind: .window, start: .hm(8, 0), end: .hm(8, 30))
        XCTAssertEqual(DayLogic.sorted([free, a, b]).map(\.id), ["b", "a", "f"])
    }

    func testCurrentBlockFallsBackToFirstMissed() {
        let a = Block(id: "a", label: "A", kind: .fixed, start: .hm(8, 0), end: .hm(8, 5))
        let b = Block(id: "b", label: "B", kind: .window, start: .hm(9, 0), end: .hm(9, 30))
        let later = Block(id: "c", label: "C", kind: .fixed, start: .hm(12, 0), end: .hm(12, 5))
        let now = date(2026, 9, 16, 11, 0)
        XCTAssertEqual(DayLogic.currentBlock([later, b, a], now: now, completed: [], calendar: calendar)?.id, "a")
        XCTAssertEqual(DayLogic.currentBlock([later, b, a], now: now, completed: ["a"], calendar: calendar)?.id, "b")
        XCTAssertEqual(DayLogic.nextUp([later, b, a], now: now, completed: [], calendar: calendar)?.id, "c")
        XCTAssertEqual(DayLogic.currentBlock([later], now: now, completed: [], calendar: calendar), nil)
    }

    func testCurrentBlockPrefersCurrentOverEarlierMissed() {
        let missed = Block(id: "m", label: "M", kind: .fixed, start: .hm(8, 0), end: .hm(8, 5))
        let current = Block(id: "c", label: "C", kind: .window, start: .hm(10, 0), end: .hm(11, 0))
        XCTAssertEqual(DayLogic.currentBlock([missed, current], now: date(2026, 9, 16, 10, 30), completed: [], calendar: calendar)?.id, "c")
    }

    func testPlanIsWellFormed() {
        XCTAssertEqual(Plan.blocks.filter(\.isAnchor).count, 1)
        XCTAssertEqual(Set(Plan.blocks.map(\.id)).count, Plan.blocks.count)
        for b in Plan.blocks where b.kind != .free {
            XCTAssertNotNil(b.start, b.id)
            XCTAssertNotNil(b.end, b.id)
        }
        // Wednesday 2026-09-16: everything occurs; Sunday 2026-09-20: no work, no gym, no shake.
        XCTAssertEqual(Plan.blocks.filter { $0.occurs(on: date(2026, 9, 16, 12, 0), calendar: calendar) }.count, 21)
        let sunday = Plan.blocks.filter { $0.occurs(on: date(2026, 9, 20, 12, 0), calendar: calendar) }.map(\.id)
        XCTAssertFalse(sunday.contains("b07"))
        XCTAssertFalse(sunday.contains("b16"))
        XCTAssertTrue(sunday.contains("b14"))
        let gym = Plan.blocks.first { $0.id == "b16" }!
        XCTAssertEqual(gym.note(on: date(2026, 9, 16, 12, 0), calendar: calendar), "Upper 2")
        XCTAssertNil(gym.note(on: date(2026, 9, 20, 12, 0), calendar: calendar))
    }
}
