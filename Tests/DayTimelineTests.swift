import XCTest
@testable import Autopiloto

final class DayTimelineTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    func testStatesAcrossADay() {
        let blocks = [
            Block(id: "a", label: "Wake", kind: .fixed, start: .hm(7, 0), end: .hm(7, 10), isAnchor: true),
            Block(id: "b", label: "Gym", kind: .window, start: .hm(19, 0), end: .hm(20, 0)),
        ]
        func snap(_ at: Date, done: Set<String> = [], skipped: Set<String> = []) -> DayTimeline.State {
            DayTimeline.snapshot(at: at, blocks: blocks, completed: done, skipped: skipped, hasPlan: true, calendar: calendar).state
        }
        XCTAssertEqual(snap(date(16, 6)), .next(blocks[0]))
        XCTAssertEqual(snap(date(16, 7, 5)), .now(blocks[0], missed: false))
        XCTAssertEqual(snap(date(16, 12)), .now(blocks[0], missed: true))            // missed wins over next
        XCTAssertEqual(snap(date(16, 12), done: ["a"]), .next(blocks[1]))
        XCTAssertEqual(snap(date(16, 21), done: ["a", "b"]), .allDone)
        XCTAssertEqual(snap(date(16, 21), done: ["a"], skipped: ["b"]), .allDone)      // skipped leaves the count
        XCTAssertEqual(DayTimeline.snapshot(at: date(16, 21), blocks: blocks, completed: ["a"], skipped: ["b"], hasPlan: true, calendar: calendar).total, 1)
        XCTAssertEqual(DayTimeline.snapshot(at: date(16, 12), blocks: [], completed: [], skipped: [], hasPlan: false, calendar: calendar).state, .noPlan)
    }

    func testSnapshotsChangeOnlyAtBoundariesAndCoverTomorrow() {
        let blocks = [
            Block(id: "a", label: "Wake", kind: .fixed, start: .hm(7, 0), end: .hm(7, 10), isAnchor: true),
            Block(id: "b", label: "Gym", kind: .window, start: .hm(19, 0), end: .hm(20, 0)),
        ]
        let snaps = DayTimeline.snapshots(
            now: date(16, 12), plan: { _ in blocks }, completed: { $0 == "2026-09-16" ? ["a"] : [] }, skipped: { _ in [] },
            hasPlan: true, calendar: calendar
        )
        XCTAssertEqual(snaps.map(\.state), [
            .next(blocks[1]),                 // 12:00 today, wake done
            .now(blocks[1], missed: false),   // 19:00
            .now(blocks[1], missed: true),    // 20:01
            .next(blocks[0]),                 // midnight: tomorrow, nothing done
            .now(blocks[0], missed: false),   // 07:00
            .now(blocks[0], missed: true),    // 07:11
            .now(blocks[1], missed: false),   // 19:00 tomorrow: current beats missed
            .now(blocks[0], missed: true),    // 20:01
        ])
        XCTAssertEqual(snaps[3].date, date(17, 0))
        XCTAssertEqual(snaps[2].date, date(16, 20, 1))
    }
}
