import UserNotifications
import XCTest
@testable import Autopiloto

/// Records what the scheduler asks the center to do.
@MainActor
final class FakeCenter {
    var pending: [String]
    var added: [UNNotificationRequest] = []
    var removed: [String] = []
    init(pending: [String] = []) { self.pending = pending }

    var client: NotificationCenterClient {
        NotificationCenterClient(
            add: { [self] r in added.append(r); pending.append(r.identifier) },
            pendingIdentifiers: { [self] in pending },
            removePending: { [self] ids in removed.append(contentsOf: ids); pending.removeAll { ids.contains($0) } },
            removeAllPending: { [self] in pending.removeAll() }
        )
    }
}

@MainActor
final class CheckInTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    // Wednesday 2026-09-16 at 12:00. Check-in blocks in the sample plan: b03 b04 b05 b09 b14 b16 b17.
    func testBuildsOneShotCheckInsForTodayAndTomorrowSkippingPastDoneAndSkipped() {
        let now = date(16, 12)
        let requests = NotificationScheduler.buildCheckIns(
            plan: { _ in Plan.blocks }, now: now,
            completed: { $0 == "2026-09-16" ? ["b09"] : [] },
            skipped: { $0 == "2026-09-17" ? ["b17"] : [] },
            brief: false, endNudges: false, calendar: calendar
        )
        let ids = requests.map(\.identifier)
        // Today: morning ones are past, lunch is done → b14 b16 b17. Tomorrow: all 7 minus skipped b17.
        XCTAssertEqual(ids, [
            "checkin-b14-2026-09-16", "checkin-b16-2026-09-16", "checkin-b17-2026-09-16",
            "checkin-b03-2026-09-17", "checkin-b04-2026-09-17", "checkin-b05-2026-09-17",
            "checkin-b09-2026-09-17", "checkin-b14-2026-09-17", "checkin-b16-2026-09-17",
        ])
        let first = requests[0]
        let trigger = first.trigger as! UNCalendarNotificationTrigger
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 19)
        XCTAssertEqual(trigger.dateComponents.minute, 5)      // Run ends 19:00 → 19:05
        XCTAssertEqual(trigger.dateComponents.day, 16)
        XCTAssertEqual(first.content.categoryIdentifier, "CHECK_IN")
        XCTAssertEqual(first.content.userInfo["blockId"] as? String, "b14")
        XCTAssertEqual(first.content.userInfo["dayKey"] as? String, "2026-09-16")
        XCTAssertEqual(first.content.title, "Run ended")
    }

    func testRearmReplacesOnlyCheckInsAndRespectsTheCap() async {
        let starts = (0..<30).map { "b\($0)-wd2" }
        let fake = FakeCenter(pending: starts + ["b13-snooze", "checkin-old-2026-09-15"])
        let added = await NotificationScheduler.rearmCheckIns(
            for: Plan.blocks, now: date(16, 12), completed: { _ in [] }, skipped: { _ in [] },
            endNudges: false, calendar: calendar, center: fake.client
        )
        XCTAssertEqual(fake.removed, ["checkin-old-2026-09-15"])
        XCTAssertEqual(added, 12)   // today b09 b14 b16 b17 + all 7 tomorrow + tomorrow's brief
        XCTAssertTrue(fake.pending.contains("b13-snooze"))
        XCTAssertEqual(fake.pending.filter { $0.hasPrefix("b") && $0.contains("-wd") }.count, 30)
        XCTAssertLessThanOrEqual(fake.pending.count, NotificationScheduler.maxPending)

        // Cap: 60 pending starts leave room for 4 check-ins, soonest first.
        let crowded = FakeCenter(pending: (0..<60).map { "s\($0)" })
        let addedCrowded = await NotificationScheduler.rearmCheckIns(
            for: Plan.blocks, now: date(16, 12), completed: { _ in [] }, skipped: { _ in [] },
            endNudges: false, calendar: calendar, center: crowded.client
        )
        XCTAssertEqual(addedCrowded, 4)
        XCTAssertEqual(crowded.added.map(\.identifier).first, "checkin-b09-2026-09-16")
        XCTAssertEqual(crowded.pending.count, 64)
    }

    func testDelegateActionsPersistOnTheNotificationsDay() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = CompletionStore(fileURL: dir.appendingPathComponent("completions.json"), calendar: calendar)
        let plan = PlanStore(fileURL: dir.appendingPathComponent("plan.json"))
        plan.replace(with: Plan.blocks)
        let fake = FakeCenter(pending: ["checkin-b21-2026-09-16"])
        let mutator = DayMutator(plan: plan, completions: store, days: DayStore(directory: dir), metrics: MetricsStore(fileURL: dir.appendingPathComponent("metrics.json"), calendar: calendar), calendar: calendar,
                                 now: { self.date(16, 12) }, center: fake.client)
        let delegate = NotificationDelegate(mutator: mutator, calendar: calendar)

        // A 23:15 block confirmed at 00:01 the next day lands on the 16th, not the 17th.
        let key = NotificationDelegate.dayKey(userInfo: ["blockId": "b21"], fireDate: date(16, 23, 15), calendar: calendar)
        XCTAssertEqual(key, "2026-09-16")
        XCTAssertEqual(NotificationDelegate.dayKey(userInfo: ["dayKey": "2026-09-16"], fireDate: date(17, 0, 1), calendar: calendar), "2026-09-16")

        await delegate.handle(.done, blockID: "b21", dayKey: "2026-09-16", center: fake.client)
        XCTAssertTrue(store.completed(dayKey: "2026-09-16").contains("b21"))
        XCTAssertTrue(fake.removed.contains("checkin-b21-2026-09-16"))

        await delegate.handle(.skipToday, blockID: "b17", dayKey: "2026-09-16", center: fake.client)
        XCTAssertTrue(store.skipped(dayKey: "2026-09-16").contains("b17"))
        // A skip from the lock screen posts an undoable confirmation; UNDO reverts it.
        XCTAssertEqual(fake.added.last?.content.categoryIdentifier, NotificationScheduler.undoCategoryID)
        await delegate.handle(.undo, blockID: nil, dayKey: "2026-09-16", center: fake.client)
        XCTAssertFalse(store.skipped(dayKey: "2026-09-16").contains("b17"))

        // REPLAN on a missed block moves it and arms a one-shot start at the new time.
        await delegate.handle(.replan, blockID: "b09", dayKey: "2026-09-16", center: fake.client)
        let moved = mutator.days.override(dayKey: "2026-09-16").moved["b09"]
        XCTAssertNotNil(moved)
        XCTAssertTrue(fake.pending.contains("moved-b09-2026-09-16"))
        
        await delegate.handle(.snooze, blockID: "b13", dayKey: "2026-09-16", center: fake.client)
        XCTAssertTrue(fake.pending.contains("b13-snooze"))
        XCTAssertEqual(NotificationDelegate.action(for: "SKIP_TODAY"), .skipToday)
        XCTAssertEqual(NotificationDelegate.action(for: "com.apple.UNNotificationDefaultActionIdentifier"), .open)
    }

    func testJSONFileReportsWriteFailures() {
        PersistenceState.shared.clear()
        JSONFile.save(["a": 1], to: URL(fileURLWithPath: "/dev/null/impossible/file.json"))
        XCTAssertNotNil(PersistenceState.shared.lastError)
        XCTAssertEqual(PersistenceState.shared.errorCount, 1)
        PersistenceState.shared.clear()
    }

    func testNoPersonalDataInTheBinarySeeds() {
        let labels = Plan.blocks.map(\.label).joined(separator: " ").lowercased()
        for word in ["minoxidil", "retatrutide", "garmin", "min-max", "hevy"] {
            XCTAssertFalse(labels.contains(word), word)
        }
        XCTAssertFalse(CoachProfile.template.lowercased().contains("alan"))
    }
}

final class MorningBriefTests: XCTestCase {
    func testBriefSummarisesTheDayAtFirstBlockEnd() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let day = c.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 6))!
        let blocks = [
            Block(id: "w", label: "Wake up", kind: .fixed, start: .hm(7, 30), end: .hm(7, 40), isAnchor: true),
            Block(id: "o", label: "Work", kind: .fixed, start: .hm(10, 0), end: .hm(17, 0), place: "office"),
            Block(id: "g", label: "Gym", kind: .window, start: .hm(19, 15), end: .hm(20, 15), autoComplete: .strength, weekdayNotes: [5: "Arms"]),
        ]
        let r = NotificationScheduler.briefRequest(for: blocks, day: day, dayKey: "2026-09-17", now: day, legs: ["o": (30, "Home")], moved: ["g"], calendar: c)!
        XCTAssertEqual(r.1.identifier, "brief-2026-09-17")
        XCTAssertEqual(r.1.content.title, "Your Thursday")
        XCTAssertEqual(r.1.content.body, "3 blocks · Gym 19:15 (Arms) · leave for Work by 09:30 · moved: Gym")
        XCTAssertEqual((r.1.trigger as! UNCalendarNotificationTrigger).dateComponents.hour, 7)
        XCTAssertEqual((r.1.trigger as! UNCalendarNotificationTrigger).dateComponents.minute, 40)
        XCTAssertNil(NotificationScheduler.briefRequest(for: blocks, day: day, dayKey: "x", now: day.addingTimeInterval(3 * 3600), legs: [:], moved: [], calendar: c))
    }
}

@MainActor
final class TimeNudgeTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()
    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    func testLongBlocksGetAnEndsSoonNudgeAndQuietBlocksGetNothing() {
        let plan = [
            Block(id: "long", label: "Deep work", kind: .fixed, start: .hm(14, 0), end: .hm(16, 0)),
            Block(id: "short", label: "Snack", kind: .fixed, start: .hm(16, 0), end: .hm(16, 15)),
            Block(id: "hush", label: "Nap", kind: .window, start: .hm(17, 0), end: .hm(18, 0), checkIn: true, quiet: true),
        ]
        let now = date(16, 12)
        let requests = NotificationScheduler.buildCheckIns(plan: { _ in plan }, now: now, completed: { _ in [] }, skipped: { _ in [] }, brief: false, calendar: calendar)
        let ids = requests.map(\.identifier)
        XCTAssertTrue(ids.contains("ends-long-2026-09-16"))
        XCTAssertFalse(ids.contains("ends-short-2026-09-16"), "15 min blocks get no nudge")
        XCTAssertFalse(ids.contains { $0.contains("hush") }, "quiet: no check-in, no nudge")
        let nudge = requests.first { $0.identifier == "ends-long-2026-09-16" }!
        XCTAssertEqual((nudge.trigger as? UNCalendarNotificationTrigger)?.dateComponents.minute, 55)
        XCTAssertEqual(nudge.content.title, "Deep work ends in 5 min")
        XCTAssertTrue(NotificationScheduler.isOneShot("ends-long-2026-09-16"))

        let off = NotificationScheduler.buildCheckIns(plan: { _ in plan }, now: now, completed: { _ in [] }, skipped: { _ in [] }, brief: false, endNudges: false, calendar: calendar)
        XCTAssertFalse(off.map(\.identifier).contains { $0.hasPrefix("ends-") })
        XCTAssertTrue(NotificationScheduler.buildRequests(for: plan).map(\.identifier).contains("long"))
        XCTAssertFalse(NotificationScheduler.buildRequests(for: [Block(id: "q", label: "Q", kind: .fixed, start: .hm(9, 0), end: .hm(9, 5), quiet: true)]).contains { $0.identifier == "q" })
    }

    func testQuietSurvivesCoding() throws {
        let block = Block(id: "x", label: "X", kind: .fixed, start: .hm(9, 0), end: .hm(9, 5), quiet: true)
        let back = try JSONDecoder().decode(Block.self, from: JSONEncoder().encode(block))
        XCTAssertTrue(back.quiet)
        let legacy = try JSONDecoder().decode(Block.self, from: Data(#"{"id":"y","label":"Y","kind":"fixed","isAnchor":false}"#.utf8))
        XCTAssertFalse(legacy.quiet)
    }
}
