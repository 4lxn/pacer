import XCTest
@testable import Autopiloto

@MainActor
final class DayMutatorTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()
    private var dir: URL!
    private var store: CompletionStore!
    private var days: DayStore!
    private var fake: FakeCenter!
    private var mutator: DayMutator!
    private var clock = Date()

    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plan = PlanStore(fileURL: dir.appendingPathComponent("plan.json"))
        plan.replace(with: Plan.blocks)
        store = CompletionStore(fileURL: dir.appendingPathComponent("completions.json"), calendar: calendar)
        days = DayStore(directory: dir, fallbackDayEnd: .hm(23, 0))
        fake = FakeCenter()
        clock = date(16, 14)   // Wednesday, 14:00: Lunch (b09 13:00–13:40) is missed
        mutator = DayMutator(plan: plan, completions: store, days: days, metrics: MetricsStore(fileURL: dir.appendingPathComponent("metrics.json"), calendar: calendar), calendar: calendar, now: { [self] in clock }, center: fake.client)
    }

    func testReplanMovesRecordsUndoAndArmsStart() async {
        let outcome = mutator.replan("b09", on: clock)
        guard case .moved(let override, _, _) = outcome else { return XCTFail("\(outcome)") }
        await mutator.flush()
        XCTAssertEqual(days.override(dayKey: "2026-09-16"), override)
        XCTAssertEqual(mutator.effectivePlan(on: clock).first { $0.id == "b09" }?.start, override.moved["b09"]?.start)
        XCTAssertTrue(mutator.lastChange!.summary.hasPrefix("Moved Lunch → "))
        XCTAssertTrue(mutator.lastChange!.undoable)
        XCTAssertTrue(fake.pending.contains("moved-b09-2026-09-16"))
        XCTAssertNotNil(days.undo)

        // Persisted: a fresh store sees the same override and undo record.
        let reloaded = DayStore(directory: dir)
        XCTAssertEqual(reloaded.override(dayKey: "2026-09-16"), override)
        XCTAssertEqual(reloaded.undo?.summary, mutator.lastChange?.summary)

        XCTAssertTrue(mutator.undo()); await mutator.flush()
        XCTAssertTrue(days.override(dayKey: "2026-09-16").isEmpty)
        XCTAssertNil(days.undo)
        XCTAssertFalse(fake.pending.contains("moved-b09-2026-09-16"))
        XCTAssertFalse(mutator.undo())
    }

    func testNoRoomSkipsAndUndoRestores() async {
        clock = date(16, 22, 50)   // day ends 23:00; nothing fits
        let outcome = mutator.replan("b09", on: clock)
        guard case .noRoom = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(store.skipped(dayKey: "2026-09-16").contains("b09"))
        XCTAssertTrue(mutator.undo()); await mutator.flush()
        XCTAssertFalse(store.skipped(dayKey: "2026-09-16").contains("b09"))
    }

    func testSkipTodayIsUndoableAndUndoIsDayScoped() async {
        mutator.skipToday("b17", dayKey: "2026-09-16")
        XCTAssertEqual(mutator.lastChange?.summary, "Skipped Dinner today")
        clock = date(17, 9)   // next day: yesterday's undo is gone
        XCTAssertFalse(mutator.undo())
        XCTAssertTrue(store.skipped(dayKey: "2026-09-16").contains("b17"))
    }

    func testRejectedDoesNotTouchState() async {
        mutator.setDone("b09", true, dayKey: "2026-09-16")
        let outcome = mutator.replan("b09", on: clock)
        guard case .rejected = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(days.undo)
        XCTAssertEqual(mutator.lastChange?.undoable, false)
    }

    func testDayEndFromSleepClampsPastMidnight() {
        XCTAssertEqual(DayStore.dayEnd(fromSleep: .hm(0, 30), wake: .hm(6, 30)), .hm(23, 59))
        XCTAssertEqual(DayStore.dayEnd(fromSleep: .hm(22, 45), wake: .hm(6, 30)), .hm(22, 45))
    }
}
