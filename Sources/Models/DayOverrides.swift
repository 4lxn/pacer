import Foundation

/// Where a block lives today, when it differs from the template. Never touches the template.
struct MovedTime: Codable, Equatable, Sendable {
    var start: DateComponents
    var end: DateComponents
}

struct DayOverride: Codable, Equatable, Sendable {
    var moved: [String: MovedTime] = [:]
    /// Blocks that exist only on this day ("just for today").
    var extras: [Block] = []
    /// A note for a block on this day only.
    var notes: [String: String] = [:]
    var isEmpty: Bool { moved.isEmpty && extras.isEmpty && notes.isEmpty }

    private enum CodingKeys: String, CodingKey { case moved, extras, notes }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moved = try c.decodeIfPresent([String: MovedTime].self, forKey: .moved) ?? [:]
        extras = try c.decodeIfPresent([Block].self, forKey: .extras) ?? []
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
    }
}

/// One level of undo for the last Replan / Skip on a day. Persisted so it survives a relaunch and
/// the background notification path.
struct UndoRecord: Codable, Equatable, Sendable {
    var dayKey: String
    var previousOverride: DayOverride
    var previousSkipped: Set<String>
    var summary: String
}

extension DayLogic {
    /// Template blocks that occur on `date` with that day's overrides applied. Orphan ids (a block
    /// that no longer exists or no longer occurs) are ignored; an override survives template edits.
    static func effectivePlan(_ blocks: [Block], override: DayOverride?, on date: Date, calendar: Calendar = .current) -> [Block] {
        let template = blocks.filter { $0.occurs(on: date, calendar: calendar) }
        return (template + (override?.extras ?? [])).map { block in
            guard let moved = override?.moved[block.id], block.kind != .free else { return block }
            var b = block
            b.start = moved.start
            b.end = moved.end
            return b
        }
    }

    enum HistoryMark: Equatable { case done, skipped, missed, off, pending }

    /// The block's last `days` days, oldest first: done / skipped / missed / not scheduled, and
    /// `pending` for today when it hasn't ended yet.
    static func history(of block: Block, days: Int, now: Date, completed: (String) -> Set<String>, skipped: (String) -> Set<String>, calendar: Calendar = .current) -> [(dayKey: String, mark: HistoryMark)] {
        (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = dayKey(day, calendar: calendar)
            guard block.occurs(on: day, calendar: calendar) else { return (key, .off) }
            if completed(key).contains(block.id) { return (key, .done) }
            if skipped(key).contains(block.id) { return (key, .skipped) }
            if offset == 0, let end = block.endDate(on: day, calendar: calendar), end > now { return (key, .pending) }
            if offset == 0, block.kind == .free { return (key, .pending) }
            return (key, .missed)
        }
    }

    /// Consecutive days (ending today or yesterday) with a score ≥ `threshold`; today counts once it qualifies.
    /// A day is "on pace" at this share of its blocks done. Skipped blocks don't count against it.
    static let paceThreshold = 0.8

    /// Days on pace in a row ending today (today counts only once it is on pace), with one
    /// forgiven miss per 7 days. Days with nothing planned are skipped, not broken.
    static func paceStreak(now: Date, calendar: Calendar = .current, score: (Date) -> Double?) -> Int {
        var streak = 0, day = now, lastMiss: Date?
        if let s = score(now), s >= paceThreshold { streak += 1 }
        for _ in 0..<365 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            guard let s = score(day) else { continue }
            if s >= paceThreshold { streak += 1; continue }
            if let lastMiss, (calendar.dateComponents([.day], from: day, to: lastMiss).day ?? 0) < 7 { break }
            lastMiss = day
        }
        return streak
    }

    static func dayStreak(now: Date, threshold: Double = 0.8, calendar: Calendar = .current, score: (Date) -> Double?) -> Int {
        var streak = 0
        var day = now
        if (score(now) ?? 0) < threshold {
            guard let y = calendar.date(byAdding: .day, value: -1, to: now), (score(y) ?? 0) >= threshold else { return 0 }
            day = y
        }
        while (score(day) ?? 0) >= threshold, streak < 365 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// done / counted for a day; nil when nothing was planned.
    static func dayScore(_ blocks: [Block], completed: Set<String>, skipped: Set<String>) -> Double? {
        let counted = blocks.filter { !skipped.contains($0.id) }
        guard !counted.isEmpty else { return nil }
        return Double(counted.filter { completed.contains($0.id) }.count) / Double(counted.count)
    }

    static func minutes(_ c: DateComponents) -> Int { (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    static func components(minutes: Int) -> DateComponents { .hm(minutes / 60, minutes % 60) }
    static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
