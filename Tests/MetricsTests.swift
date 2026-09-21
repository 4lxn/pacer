import XCTest
@testable import Autopiloto

@MainActor
final class MetricsTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    private func date(_ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    func testWeekTotalsAndKillCriterionPersist() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let m = MetricsStore(fileURL: url, calendar: calendar)
        m.record(.doneApp, on: date(16)); m.record(.doneHealth, on: date(15)); m.record(.doneApp, on: date(8))   // 8th is outside the window
        m.record(.checkInDone, on: date(16)); m.record(.checkInReplan, on: date(16)); m.record(.replanNotification, on: date(16))
        m.record(.replanApp, on: date(14)); m.record(.undo, on: date(14))
        let week = MetricsStore(fileURL: url, calendar: calendar).week(now: date(16))
        XCTAssertEqual(week.done, 2)
        XCTAssertEqual(week.healthClosed, 1)
        XCTAssertEqual(week.replans, 2)
        XCTAssertEqual(week.undone, 1)
        XCTAssertEqual(week.checkInsActed, 2)
        XCTAssertEqual(week.replanShare, 0.5)
        XCTAssertEqual(week.replanKept, 0.5)
        XCTAssertNil(MetricsStore.Week().replanShare)
    }

    func testCheckInsSwitchDropsCheckInsButKeepsMovedStarts() {
        let blocks = [Block(id: "b", label: "Gym", kind: .window, start: .hm(19, 0), end: .hm(20, 0))]
        let on = NotificationScheduler.buildCheckIns(plan: { _ in blocks }, now: date(16), completed: { _ in [] }, skipped: { _ in [] },
                                                    movedIDs: { _ in ["b"] }, checkIns: true, brief: false, endNudges: false, calendar: calendar)
        let off = NotificationScheduler.buildCheckIns(plan: { _ in blocks }, now: date(16), completed: { _ in [] }, skipped: { _ in [] },
                                                     movedIDs: { _ in ["b"] }, checkIns: false, brief: false, endNudges: false, calendar: calendar)
        XCTAssertEqual(on.map(\.identifier), ["moved-b-2026-09-16", "checkin-b-2026-09-16", "moved-b-2026-09-17", "checkin-b-2026-09-17"])
        XCTAssertEqual(off.map(\.identifier), ["moved-b-2026-09-16", "moved-b-2026-09-17"])
    }

    func testDiagnosticsReportCountsPendingByKind() {
        let report = Diagnostics.report(.init(
            now: date(16), version: "1.0 (4)", notificationStatus: "allowed",
            pending: ["b01", "b02-wd2", "b03-snooze", "checkin-b09-2026-09-16", "moved-b09-2026-09-16"],
            lastRearm: nil, healthAvailable: true, healthAuthorized: false, lastHealthDelivery: nil,
            persistenceErrors: 0, lastPersistenceError: nil, blocks: 21, checkInBlocks: 7, checkInsEnabled: true,
            dayEnd: .hm(23, 0), week: MetricsStore.Week(done: 3, replans: 1, checkInsActed: 2, checkInReplans: 1), files: [("plan", 1200)]
        ))
        XCTAssertTrue(report.contains("pending 5/64 (starts 2, check-ins 1, moved 1)"), report)
        XCTAssertTrue(report.contains("last re-arm never"))
        XCTAssertTrue(report.contains("replan share 50% (keep ≥ 30%), replans kept 100% (keep ≥ 70%)"), report)
        XCTAssertTrue(report.contains("plan 1200 B"))
    }
}
