import Foundation

enum BlockStatus: Equatable {
    case done
    case skipped      // the user chose to skip it today
    case current      // now within [start, end]
    case upcoming     // now < start
    case missed       // now > end and not done
    case free         // kind == .free and not done
}

extension Block {
    func status(now: Date, completed: Set<String>, skipped: Set<String> = [], calendar: Calendar = .current) -> BlockStatus {
        if completed.contains(id) { return .done }
        if skipped.contains(id) { return .skipped }
        if kind == .free { return .free }
        guard let start = startDate(on: now, calendar: calendar),
              let end = endDate(on: now, calendar: calendar) else { return .free }
        if now < start { return .upcoming }
        if now >= start && now <= end { return .current }
        return .missed
    }
}

enum DayLogic {
    /// Start-time order; `.free` blocks last, ties keep plan order.
    static func sorted(_ blocks: [Block]) -> [Block] {
        blocks.enumerated().sorted { lhs, rhs in
            switch (lhs.element.start, rhs.element.start) {
            case let (l?, r?):
                let lm = (l.hour ?? 0) * 60 + (l.minute ?? 0)
                let rm = (r.hour ?? 0) * 60 + (r.minute ?? 0)
                return lm != rm ? lm < rm : lhs.offset < rhs.offset
            case (nil, nil): return lhs.offset < rhs.offset
            case (nil, _): return false
            case (_, nil): return true
            }
        }.map(\.element)
    }

    /// First `.current` block in start order; if none, the first `.missed` one.
    static func currentBlock(_ blocks: [Block], now: Date, completed: Set<String>, skipped: Set<String> = [], calendar: Calendar = .current) -> Block? {
        let ordered = sorted(blocks)
        if let current = ordered.first(where: { $0.status(now: now, completed: completed, skipped: skipped, calendar: calendar) == .current }) {
            return current
        }
        return ordered.first { $0.status(now: now, completed: completed, skipped: skipped, calendar: calendar) == .missed }
    }

    static func nextUp(_ blocks: [Block], now: Date, completed: Set<String>, skipped: Set<String> = [], calendar: Calendar = .current) -> Block? {
        sorted(blocks).first { $0.status(now: now, completed: completed, skipped: skipped, calendar: calendar) == .upcoming }
    }

    static func clock(_ c: DateComponents) -> String {
        String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `yyyy-MM-dd` in the calendar's time zone; the key completion is stored under.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
