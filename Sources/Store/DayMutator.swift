import Foundation
import Observation
import OSLog
import UserNotifications

/// The one place that changes a day: done / skip / replan / undo. Mutations are synchronous (the
/// stores are in-memory + JSON); the notification work they trigger is queued and awaited with
/// `flush()` where it matters (notification actions, tests).
@Observable
@MainActor
final class DayMutator {
    enum Source { case app, notification }

    struct Change: Equatable {
        var summary: String          // "Moved Study → 19:00"
        var undoable: Bool
    }

    let plan: PlanStore
    let completions: CompletionStore
    let days: DayStore
    var calendar: Calendar
    var now: () -> Date
    var center: NotificationCenterClient
    /// Last change, for the in-app Undo toast.
    private(set) var lastChange: Change?

    @ObservationIgnored private var queue: Task<Void, Never>?
    private let log = Logger(subsystem: "com.alan.autopiloto", category: "replan")

    init(plan: PlanStore, completions: CompletionStore, days: DayStore, calendar: Calendar = .current,
         now: @escaping () -> Date = { .now }, center: NotificationCenterClient = .live) {
        self.plan = plan
        self.completions = completions
        self.days = days
        self.calendar = calendar
        self.now = now
        self.center = center
    }

    // MARK: - Reads

    func dayKey(_ date: Date) -> String { DayLogic.dayKey(date, calendar: calendar) }

    func effectivePlan(on date: Date) -> [Block] {
        DayLogic.effectivePlan(plan.blocks, override: days.override(dayKey: dayKey(date)), on: date, calendar: calendar)
    }

    func block(id: String, on date: Date) -> Block? { effectivePlan(on: date).first { $0.id == id } }

    func date(_ dayKey: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dayKey).flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
    }

    // MARK: - Writes

    func setDone(_ id: String, _ done: Bool, dayKey: String) {
        let isDone = completions.completed(dayKey: dayKey).contains(id)
        guard done != isDone else { return }
        if done { completions.markDone(id, dayKey: dayKey) } else { completions.toggle(id, on: date(dayKey) ?? now()) }
        if done { NotificationScheduler.cancelCheckIn(id, dayKey: dayKey, center: center) }
        enqueueRearm()
    }

    func toggleDone(_ id: String, on date: Date) {
        let key = dayKey(date)
        setDone(id, !completions.completed(dayKey: key).contains(id), dayKey: key)
    }

    func skipToday(_ id: String, dayKey: String, source: Source = .app) {
        guard let label = plan.block(id: id)?.label else { return }
        recordUndo(dayKey: dayKey, summary: "Skipped \(label) today")
        completions.skip(id, dayKey: dayKey)
        NotificationScheduler.cancelCheckIn(id, dayKey: dayKey, center: center)
        finish(Change(summary: "Skipped \(label) today", undoable: true), source: source, dayKey: dayKey)
    }

    func unskip(_ id: String, on date: Date) {
        completions.unskip(id, on: date)
        enqueueRearm()
    }

    /// Replan a missed block into free time later today. The change is applied; the outcome is
    /// returned for callers that want to show it (tools, tests).
    @discardableResult
    func replan(_ id: String, on date: Date, source: Source = .app) -> Replanner.Outcome {
        guard let block = block(id: id, on: date) else { return .rejected("No block with that id today.") }
        let outcome = Replanner.replan(block, in: context(on: date))
        apply(outcome, block: block, dayKey: dayKey(date), source: source)
        return outcome
    }

    @discardableResult
    func move(_ id: String, to start: DateComponents, on date: Date, source: Source = .app) -> Replanner.Outcome {
        guard let block = block(id: id, on: date) else { return .rejected("No block with that id today.") }
        let outcome = Replanner.place(block, at: start, in: context(on: date))
        apply(outcome, block: block, dayKey: dayKey(date), source: source)
        return outcome
    }

    /// Restores the previous override + skipped set. False when nothing from today is there to undo.
    @discardableResult
    func undo(source: Source = .app) -> Bool {
        guard let record = days.undo, record.dayKey == dayKey(now()) else {
            days.setUndo(nil)
            lastChange = nil
            if source == .notification { enqueue { await self.post(title: "Nothing to undo", body: "", category: nil, dayKey: nil) } }
            return false
        }
        days.setOverride(record.previousOverride, dayKey: record.dayKey)
        let currentSkipped = completions.skipped(dayKey: record.dayKey)
        for id in currentSkipped.subtracting(record.previousSkipped) { completions.unskip(id, on: date(record.dayKey) ?? now()) }
        for id in record.previousSkipped.subtracting(currentSkipped) { completions.skip(id, dayKey: record.dayKey) }
        days.setUndo(nil)
        lastChange = nil
        enqueueRearm()
        if source == .notification { enqueue { await self.post(title: "Undone", body: record.summary, category: nil, dayKey: nil) } }
        return true
    }

    func clearLastChange() { lastChange = nil }

    // MARK: - Notifications

    /// Re-arms check-ins and the one-shot starts for moved blocks (today + tomorrow).
    func rearm() async {
        _ = await NotificationScheduler.rearmCheckIns(
            plan: { [self] day in effectivePlan(on: day) }, now: now(),
            completed: { [self] in completions.completed(dayKey: $0) }, skipped: { [self] in completions.skipped(dayKey: $0) },
            movedIDs: { [self] key in Set(days.override(dayKey: key).moved.keys) },
            calendar: calendar, center: center
        )
    }

    /// Waits for the queued notification work. Notification actions call this before returning so
    /// the system doesn't suspend the process mid-way.
    func flush() async { await queue?.value }

    private func enqueueRearm() { enqueue { await self.rearm() } }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func post(title: String, body: String, category: String?, dayKey: String?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "autopiloto-replan"
        if let category { content.categoryIdentifier = category }
        if let dayKey { content.userInfo = [NotificationScheduler.dayKeyKey: dayKey] }
        try? await center.add(UNNotificationRequest(identifier: "replan-\(UUID().uuidString)", content: content, trigger: nil))
    }

    // MARK: - Internals

    private func context(on date: Date) -> Replanner.Context {
        let key = dayKey(date)
        return Replanner.Context(
            plan: effectivePlan(on: date), override: days.override(dayKey: key), now: now(), dayEnd: days.dayEnd,
            completed: completions.completed(dayKey: key), skipped: completions.skipped(dayKey: key), calendar: calendar
        )
    }

    private func apply(_ outcome: Replanner.Outcome, block: Block, dayKey: String, source: Source) {
        switch outcome {
        case let .moved(override, pushed, out), let .shrunk(override, _, pushed, out):
            guard let moved = override.moved[block.id] else { return }
            var summary = "Moved \(block.label) → \(DayLogic.clock(moved.start))"
            if case .shrunk(_, let minutes, _, _) = outcome { summary += " (\(minutes) min)" }
            if !pushed.isEmpty { summary += ", pushed \(pushed.count) block\(pushed.count == 1 ? "" : "s")" }
            if !out.isEmpty {
                let names = out.compactMap { id in plan.block(id: id)?.label }.joined(separator: ", ")
                summary += "; no room today for \(names)"
            }
            recordUndo(dayKey: dayKey, summary: summary)
            days.setOverride(override, dayKey: dayKey)
            for id in out { completions.skip(id, dayKey: dayKey) }
            log.info("\(summary)")
            finish(Change(summary: summary, undoable: true), source: source, dayKey: dayKey)
        case .noRoom:
            recordUndo(dayKey: dayKey, summary: "Skipped \(block.label) today")
            completions.skip(block.id, dayKey: dayKey)
            NotificationScheduler.cancelCheckIn(block.id, dayKey: dayKey, center: center)
            log.info("No room for \(block.label)")
            finish(Change(summary: "No room for \(block.label) today — it's back tomorrow", undoable: true), source: source, dayKey: dayKey)
        case .rejected(let reason):
            log.info("Replan rejected: \(reason)")
            lastChange = Change(summary: reason, undoable: false)
        }
    }

    private func recordUndo(dayKey: String, summary: String) {
        days.setUndo(UndoRecord(dayKey: dayKey, previousOverride: days.override(dayKey: dayKey),
                                previousSkipped: completions.skipped(dayKey: dayKey), summary: summary))
    }

    private func finish(_ change: Change, source: Source, dayKey: String) {
        lastChange = change
        enqueueRearm()
        if source == .notification {
            enqueue { [self] in
                await post(title: change.summary, body: change.undoable ? "Tap and hold to undo" : "",
                           category: change.undoable ? NotificationScheduler.undoCategoryID : nil, dayKey: dayKey)
            }
        }
    }
}
