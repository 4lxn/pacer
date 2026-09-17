import XCTest
@testable import Autopiloto

@MainActor
final class DayDepthTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()
    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    func testHistoryMarksAndDayScore() {
        let gym = Block(id: "g", label: "Gym", kind: .window, start: .hm(19, 0), end: .hm(20, 0), weekdays: [2, 4, 6])   // Mon Wed Fri
        let now = date(16, 12)   // Wednesday noon
        let history = DayLogic.history(of: gym, days: 7, now: now,
                                       completed: { $0 == "2026-09-14" ? ["g"] : [] }, skipped: { $0 == "2026-09-11" ? ["g"] : [] }, calendar: calendar)
        XCTAssertEqual(history.map(\.mark), [.off, .skipped, .off, .off, .done, .off, .pending])   // Thu 10 … Wed 16
        XCTAssertEqual(history.map(\.dayKey).last, "2026-09-16")

        let blocks = [gym, Block(id: "w", label: "Wake", kind: .fixed, start: .hm(7, 0), end: .hm(7, 10), isAnchor: true)]
        XCTAssertEqual(DayLogic.dayScore(blocks, completed: ["w"], skipped: []), 0.5)
        XCTAssertEqual(DayLogic.dayScore(blocks, completed: ["w"], skipped: ["g"]), 1)
        XCTAssertNil(DayLogic.dayScore([], completed: [], skipped: []))
    }

    func testExtrasAndNotesLiveOnlyOnTheirDay() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plan = PlanStore(fileURL: dir.appendingPathComponent("plan.json")); plan.replace(with: Plan.blocks)
        let store = CompletionStore(fileURL: dir.appendingPathComponent("completions.json"), calendar: calendar)
        let fake = FakeCenter()
        let mutator = DayMutator(plan: plan, completions: store, days: DayStore(directory: dir),
                                 metrics: MetricsStore(fileURL: dir.appendingPathComponent("metrics.json"), calendar: calendar),
                                 calendar: calendar, now: { self.date(16, 12) }, center: fake.client)
        let extra = Block(id: "today-1", label: "Dentist", kind: .fixed, start: .hm(16, 0), end: .hm(16, 30))
        mutator.addExtra(extra, dayKey: "2026-09-16")
        await mutator.flush()
        XCTAssertTrue(mutator.effectivePlan(on: date(16, 12)).contains { $0.id == "today-1" })
        XCTAssertFalse(mutator.effectivePlan(on: date(17, 12)).contains { $0.id == "today-1" })
        XCTAssertTrue(fake.pending.contains("moved-today-1-2026-09-16"))   // one-shot start for a one-off block

        mutator.days.setNote("bring the x-rays", blockID: "today-1", dayKey: "2026-09-16")
        XCTAssertEqual(DayStore(directory: dir).override(dayKey: "2026-09-16").notes["today-1"], "bring the x-rays")

        // The extra can be moved like any block and removed with its note.
        guard case .moved = mutator.move("today-1", to: .hm(18, 0), on: date(16, 12)) else { return XCTFail() }
        mutator.removeExtra("today-1", dayKey: "2026-09-16")
        await mutator.flush()
        let o = mutator.days.override(dayKey: "2026-09-16")
        XCTAssertTrue(o.extras.isEmpty && o.notes.isEmpty && o.moved["today-1"] == nil)
        XCTAssertFalse(fake.pending.contains("moved-today-1-2026-09-16"))
    }
}
