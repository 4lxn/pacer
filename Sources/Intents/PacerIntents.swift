import AppIntents
import Foundation

/// Siri / Shortcuts / Spotlight. Each intent talks to the live stores through the app delegate.
enum PacerIntents {
    @MainActor
    static var app: AppDelegate? { AppDelegate.shared }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription("Tells you what's on now and what comes next in your plan.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = PacerIntents.app else { return .result(dialog: "Open Pacer once and try again.") }
        let now = Date.now
        let key = app.mutator.dayKey(now)
        let snap = DayTimeline.snapshot(at: now, blocks: app.mutator.effectivePlan(on: now), completed: app.store.completed(dayKey: key),
                                        skipped: app.store.skipped(dayKey: key), hasPlan: !app.plan.needsOnboarding, calendar: .current)
        let line: String
        switch snap.state {
        case .now(let b, let missed):
            let end = b.end.map(DayLogic.clock) ?? ""
            line = missed ? "\(b.label) was missed. " : "Now: \(b.label) until \(end). "
        case .next(let b): line = "Nothing right now. Next: \(b.label) at \(b.start.map(DayLogic.clock) ?? ""). "
        case .allDone: line = "All done for today — \(snap.done) of \(snap.total). "
        case .nothingLeft: line = "Nothing left today; \(snap.done) of \(snap.total) done. "
        case .noPlan: line = "You haven't built a plan yet. "
        }
        let next = snap.upcoming.first.map { "Then \($0.label) at \($0.start.map(DayLogic.clock) ?? "")." } ?? ""
        return .result(dialog: IntentDialog(stringLiteral: (line + next).trimmingCharacters(in: .whitespaces)))
    }
}

struct MarkCurrentDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark the current block done"
    static let description = IntentDescription("Marks the block that's on (or the last missed one) as done.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = PacerIntents.app else { return .result(dialog: "Open Pacer once and try again.") }
        let now = Date.now
        let key = app.mutator.dayKey(now)
        app.store.reload()
        guard let block = DayLogic.currentBlock(app.mutator.effectivePlan(on: now), now: now, completed: app.store.completed(dayKey: key), skipped: app.store.skipped(dayKey: key)) else {
            return .result(dialog: "Nothing is on right now.")
        }
        app.mutator.setDone(block.id, true, dayKey: key, source: .notification)
        await app.mutator.flush()
        return .result(dialog: IntentDialog(stringLiteral: "\(block.label) done."))
    }
}

struct MoveCurrentLaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Move the missed block later"
    static let description = IntentDescription("Finds free time later today for the block you missed.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = PacerIntents.app else { return .result(dialog: "Open Pacer once and try again.") }
        let now = Date.now
        let key = app.mutator.dayKey(now)
        app.store.reload()
        let plan = DayLogic.sorted(app.mutator.effectivePlan(on: now))
        guard let missed = plan.first(where: { $0.status(now: now, completed: app.store.completed(dayKey: key), skipped: app.store.skipped(dayKey: key)) == .missed && $0.kind != .free && !$0.isAnchor }) else {
            return .result(dialog: "Nothing is missed right now.")
        }
        app.mutator.replan(missed.id, on: now, source: .notification)
        await app.mutator.flush()
        return .result(dialog: IntentDialog(stringLiteral: app.mutator.lastChange?.summary ?? "Done."))
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a focus session"
    static let description = IntentDescription("Starts a focus timer that shows in the Dynamic Island.")
    static let openAppWhenRun = false

    @Parameter(title: "Subject", default: "Focus") var subject: String
    @Parameter(title: "Minutes", default: 25) var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = PacerIntents.app else { return .result(dialog: "Open Pacer once and try again.") }
        if app.track.isStudying { return .result(dialog: IntentDialog(stringLiteral: "Already focusing on \(app.track.runningTopic).")) }
        if app.track.subject(named: subject) == nil { app.track.upsertSubject(Subject(name: subject)) }
        app.track.startStudy(topic: subject, focusMinutes: minutes > 0 ? minutes : nil)
        if let until = app.track.runningUntil { await NotificationScheduler.scheduleFocusEnd(at: until, topic: subject) }
        await FocusActivityController.sync(track: app.track)
        return .result(dialog: IntentDialog(stringLiteral: minutes > 0 ? "Focusing on \(subject) for \(minutes) minutes." : "Focusing on \(subject)."))
    }
}

struct StopFocusAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop the focus session"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = PacerIntents.app else { return .result(dialog: "Open Pacer once and try again.") }
        guard let session = app.track.stopStudy() else { return .result(dialog: "No session was running.") }
        NotificationScheduler.cancelFocusEnd()
        await FocusActivityController.sync(track: app.track)
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(session.minutes) minutes of \(session.topic)."))
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let openAppWhenRun = false
    @Parameter(title: "Glasses", default: 1) var glasses: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = PacerIntents.app else { return .result(dialog: "Open Pacer once and try again.") }
        app.food.logWater(glasses)
        return .result(dialog: IntentDialog(stringLiteral: "Water: \(app.food.water(on: .now)) of \(app.food.waterTarget) glasses."))
    }
}

struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log weight"
    static let description = IntentDescription("Saves today's weight to the Health app.")
    static let openAppWhenRun = false
    @Parameter(title: "Kilograms") var kilograms: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let app = PacerIntents.app else { return .result(dialog: "Open Pacer once and try again.") }
        guard kilograms > 20, kilograms < 300 else { return .result(dialog: "That doesn't look like a weight in kilograms.") }
        await app.health.saveWeight(kg: kilograms)
        return .result(dialog: IntentDialog(stringLiteral: String(format: "Logged %.1f kg.", kilograms)))
    }
}

struct PacerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsNextIntent(), phrases: ["What's next in \(.applicationName)", "What should I do now in \(.applicationName)"],
                    shortTitle: "What's next", systemImageName: "sun.max")
        AppShortcut(intent: MarkCurrentDoneIntent(), phrases: ["Mark it done in \(.applicationName)", "Done in \(.applicationName)"],
                    shortTitle: "Mark done", systemImageName: "checkmark.circle")
        AppShortcut(intent: MoveCurrentLaterIntent(), phrases: ["Move it later in \(.applicationName)"],
                    shortTitle: "Move it later", systemImageName: "arrow.right.circle")
        AppShortcut(intent: StartFocusIntent(), phrases: ["Start a focus session in \(.applicationName)", "Start focus in \(.applicationName)"],
                    shortTitle: "Start focus", systemImageName: "timer")
        AppShortcut(intent: StopFocusAppIntent(), phrases: ["Stop focus in \(.applicationName)"],
                    shortTitle: "Stop focus", systemImageName: "stop.circle")
        AppShortcut(intent: LogWaterIntent(), phrases: ["Log water in \(.applicationName)", "Log a glass of water in \(.applicationName)"],
                    shortTitle: "Log water", systemImageName: "drop")
        AppShortcut(intent: LogWeightIntent(), phrases: ["Log my weight in \(.applicationName)"],
                    shortTitle: "Log weight", systemImageName: "scalemass")
    }
}
