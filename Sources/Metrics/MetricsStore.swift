import Foundation
import Observation

/// On-device counters only (no network, no identifiers): how the day is actually being run.
/// Feeds "Your week" and the Replan kill criterion in Diagnostics. `metrics.json`.
@Observable
@MainActor
final class MetricsStore {
    enum Event: String, CaseIterable, Codable {
        case doneApp, doneNotification, doneHealth
        case skipApp, skipNotification
        case replanApp, replanNotification, replanNoRoom
        case undo
        case checkInDone, checkInSkip, checkInReplan   // actions taken on a check-in notification
    }

    struct Week: Equatable {
        var done = 0, skipped = 0, replans = 0, undone = 0, healthClosed = 0
        var checkInsActed = 0, checkInReplans = 0
        /// Kill criterion (docs/PRODUCT.md): ≥ 30 % of acted check-ins choose Replan and ≥ 70 % of replans stay.
        var replanShare: Double? { checkInsActed > 0 ? Double(checkInReplans) / Double(checkInsActed) : nil }
        var replanKept: Double? { replans > 0 ? 1 - Double(undone) / Double(replans) : nil }
    }

    private struct File: Codable {
        var days: [String: [Event: Int]] = [:]
        var lastRearm: Date?
        var lastHealthDelivery: Date?
    }

    private(set) var days: [String: [Event: Int]] = [:]
    private(set) var lastRearm: Date?
    private(set) var lastHealthDelivery: Date?
    private let fileURL: URL
    private let calendar: Calendar

    init(fileURL: URL = AppFiles.url("metrics.json"), calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if case .loaded(let f) = JSONFile.load(File.self, from: fileURL) {
            days = f.days; lastRearm = f.lastRearm; lastHealthDelivery = f.lastHealthDelivery
        }
    }

    func record(_ event: Event, on date: Date = .now) {
        days[DayLogic.dayKey(date, calendar: calendar), default: [:]][event, default: 0] += 1
        save()
    }

    func markRearm(_ date: Date = .now) { lastRearm = date; save() }
    func markHealthDelivery(_ date: Date = .now) { lastHealthDelivery = date; save() }

    func count(_ event: Event, dayKey: String) -> Int { days[dayKey]?[event] ?? 0 }

    /// Totals over the last 7 days including `now`.
    func week(now: Date = .now) -> Week {
        var w = Week()
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DayLogic.dayKey(day, calendar: calendar)
            func n(_ e: Event) -> Int { count(e, dayKey: key) }
            w.done += n(.doneApp) + n(.doneNotification) + n(.doneHealth)
            w.skipped += n(.skipApp) + n(.skipNotification)
            w.replans += n(.replanApp) + n(.replanNotification)
            w.undone += n(.undo)
            w.healthClosed += n(.doneHealth)
            w.checkInsActed += n(.checkInDone) + n(.checkInSkip) + n(.checkInReplan)
            w.checkInReplans += n(.checkInReplan)
        }
        return w
    }

    private func save() {
        // Keep the file small: 60 days is plenty for a weekly view.
        if days.count > 60 { for key in days.keys.sorted().prefix(days.count - 60) { days.removeValue(forKey: key) } }
        JSONFile.save(File(days: days, lastRearm: lastRearm, lastHealthDelivery: lastHealthDelivery), to: fileURL)
    }
}
