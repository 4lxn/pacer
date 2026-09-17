import Foundation

/// Where a block lives today, when it differs from the template. Never touches the template.
struct MovedTime: Codable, Equatable, Sendable {
    var start: DateComponents
    var end: DateComponents
}

struct DayOverride: Codable, Equatable, Sendable {
    var moved: [String: MovedTime] = [:]
    var isEmpty: Bool { moved.isEmpty }
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
        blocks.filter { $0.occurs(on: date, calendar: calendar) }.map { block in
            guard let moved = override?.moved[block.id], block.kind != .free else { return block }
            var b = block
            b.start = moved.start
            b.end = moved.end
            return b
        }
    }

    static func minutes(_ c: DateComponents) -> Int { (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    static func components(minutes: Int) -> DateComponents { .hm(minutes / 60, minutes % 60) }
    static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
