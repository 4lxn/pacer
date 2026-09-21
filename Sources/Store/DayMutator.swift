import Foundation
import Observation
import OSLog
import UserNotifications
import WidgetKit

/// The one place that changes a day: done / skip / replan / undo. Mutations are synchronous (the
/// stores are in-memory + JSON); the notification work they trigger is queued and awaited with
/// `flush()` where it matters (notification actions, tests).
@Observable
@MainActor
final class DayMutator {
    enum Source { case app, notification, health }

    struct Change: Equatable {
        var summary: String          // "Moved Study → 19:00"
        var undoable: Bool
    }

    let plan: PlanStore
    let completions: CompletionStore
    let days: DayStore
    let metrics: MetricsStore
    var calendar: Calendar
    var now: () -> Date
    var center: NotificationCenterClient
    /// Last change, for the in-app Undo toast.
    private(set) var lastChange: Change?

    @ObservationIgnored private var queue: Task<Void, Never>?
    private let log = Logger(subsystem: "com.alan.autopiloto", category: "replan")

    init(plan: PlanStore, completions: CompletionStore, days: DayStore, metrics: MetricsStore, calendar: Calendar = .current,
         now: @escaping () -> Date = { .now }, center: NotificationCenterClient = .live) {
        self.plan = plan
        self.completions = completions
        self.days = days
        self.metrics = metrics
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

    /// The "now" used to judge a day: real time today, start of day for future days (nothing has
    /// passed yet), end of day for past days (everything has).
    func clock(for date: Date) -> Date {
        let current = now()
        if calendar.isDate(date, inSameDayAs: current) { return current }
        let start = calendar.startOfDay(for: date)
        return date > current ? start : (calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-60) ?? date)
    }

    /// Share of the day's counted blocks that are done; nil when nothing was planned.
    func score(on day: Date) -> Double? {
        let key = dayKey(day)
        return DayLogic.dayScore(effectivePlan(on: day), completed: completions.completed(dayKey: key), skipped: completions.skipped(dayKey: key))
    }

    func isEditable(_ date: Date) -> Bool { dayKey(date) >= dayKey(now()) }

    /// Drops every override on a day (moves, one-offs, notes). Skips stay.
    func resetDay(_ date: Date) {
        let key = dayKey(date)
        let o = days.override(dayKey: key)
        guard !o.isEmpty else { return }
        for extra in o.extras { center.removePending([NotificationScheduler.movedIdentifier(extra.id, dayKey: key)]) }
        days.setUndo(UndoRecord(dayKey: key, previousOverride: o, previousSkipped: completions.skipped(dayKey: key), summary: "Reset \(key)"))
        days.setOverride(DayOverride(), dayKey: key)
        lastChange = Change(summary: "Day reset to the weekly plan", undoable: true)
        enqueueRearm()
    }

    func date(_ dayKey: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dayKey).flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
    }

    // MARK: - Writes

    func setDone(_ id: String, _ done: Bool, dayKey: String, source: Source = .app) {
        let isDone = completions.completed(dayKey: dayKey).contains(id)
        guard done != isDone else { return }
        if done { completions.markDone(id, dayKey: dayKey) } else { completions.toggle(id, on: date(dayKey) ?? now()) }
        if done {
            NotificationScheduler.cancelCheckIn(id, dayKey: dayKey, center: center)
            metrics.record(source == .app ? .doneApp : source == .notification ? .doneNotification : .doneHealth, on: now())
        }
        enqueueRearm()
    }

    /// Marks blocks done from Apple Health workouts / study minutes. Returns the ids closed.
    @discardableResult
    func autoClose(workouts: [WorkoutSummary], studyMinutesToday: Int, on date: Date) -> [String] {
        let key = dayKey(date)
        let ids = DayLogic.autoCompletions(effectivePlan(on: date), workouts: workouts, studyMinutesToday: studyMinutesToday,
                                           now: date, completed: completions.completed(dayKey: key), calendar: calendar)
        for id in ids { setDone(id, true, dayKey: key, source: .health) }
        return ids
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
        metrics.record(source == .app ? .skipApp : .skipNotification, on: now())
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
        guard let record = days.undo, record.dayKey >= dayKey(now()) else {
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
        metrics.record(.undo, on: now())
        enqueueRearm()
        if source == .notification { enqueue { await self.post(title: "Undone", body: record.summary, category: nil, dayKey: nil) } }
        return true
    }

    /// A block that exists only on that day. Not undoable; delete it from its detail.
    func addExtra(_ block: Block, dayKey: String) {
        days.addExtra(block, dayKey: dayKey)
        enqueueRearm()
    }

    func removeExtra(_ id: String, dayKey: String) {
        days.removeExtra(id, dayKey: dayKey)
        completions.unskip(id, on: date(dayKey) ?? now())
        NotificationScheduler.cancelCheckIn(id, dayKey: dayKey, center: center)
        center.removePending([NotificationScheduler.movedIdentifier(id, dayKey: dayKey)])
        enqueueRearm()
    }

    func clearLastChange() { lastChange = nil }

    // MARK: - Notifications

    /// Re-arms check-ins and the one-shot starts for moved blocks (today + tomorrow).
    func rearm() async {
        _ = await NotificationScheduler.rearmCheckIns(
            plan: { [self] day in effectivePlan(on: day) }, now: now(),
            completed: { [self] in completions.completed(dayKey: $0) }, skipped: { [self] in completions.skipped(dayKey: $0) },
            movedIDs: { [self] key in
                let o = days.override(dayKey: key)
                return Set(o.moved.keys).union(o.extras.map(\.id))
            },
            checkIns: days.checkInsEnabled, places: days.places, legOverrides: { [self] in days.legMinutes(dayKey: $0) },
            brief: days.morningBrief, endNudges: days.endNudges, calendar: calendar, center: center
        )
        metrics.markRearm(now())
        await syncLiveActivity()
    }

    /// The Live Activity mirrors the current block; off in settings ends it.
    func syncLiveActivity() async {
        let current = now()
        guard days.liveActivity else { await LiveActivityController.endAll(); return }
        let key = dayKey(current)
        let snapshot = DayTimeline.snapshot(at: current, blocks: effectivePlan(on: current), completed: completions.completed(dayKey: key),
                                            skipped: completions.skipped(dayKey: key), hasPlan: !plan.needsOnboarding, calendar: calendar)
        await LiveActivityController.sync(snapshot: snapshot, places: days.places, calendar: calendar)
    }

    /// Waits for the queued notification work. Notification actions call this before returning so
    /// the system doesn't suspend the process mid-way.
    func flush() async { await queue?.value }

    private func enqueueRearm() {
        WidgetCenter.shared.reloadAllTimelines()
        enqueue { await self.rearm() }
    }

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
        content.sound = NotificationScheduler.sound
        content.threadIdentifier = "autopiloto-replan"
        if let category { content.categoryIdentifier = category }
        if let dayKey { content.userInfo = [NotificationScheduler.dayKeyKey: dayKey] }
        try? await center.add(UNNotificationRequest(identifier: "replan-\(UUID().uuidString)", content: content, trigger: nil))
    }

    // MARK: - Internals

    private func context(on date: Date) -> Replanner.Context {
        let key = dayKey(date)
        return Replanner.Context(
            plan: effectivePlan(on: date), override: days.override(dayKey: key), now: clock(for: date), dayEnd: days.dayEnd,
            completed: completions.completed(dayKey: key), skipped: completions.skipped(dayKey: key), calendar: calendar,
            places: days.places,
            busy: days.useCalendar ? CalendarBusy.shared.obstacles(dayKey: key, calendar: calendar) : []
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
            metrics.record(source == .app ? .replanApp : .replanNotification, on: now())
            log.info("\(summary)")
            finish(Change(summary: summary, undoable: true), source: source, dayKey: dayKey)
        case .noRoom:
            recordUndo(dayKey: dayKey, summary: "Skipped \(block.label) today")
            completions.skip(block.id, dayKey: dayKey)
            NotificationScheduler.cancelCheckIn(block.id, dayKey: dayKey, center: center)
            metrics.record(.replanNoRoom, on: now())
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
