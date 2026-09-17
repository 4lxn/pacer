import Foundation

/// What the widget shows at a moment, and the moments it changes. Pure; shared with the widget.
enum DayTimeline {
    enum State: Equatable {
        case noPlan
        case now(Block, missed: Bool)
        case next(Block)
        case allDone
        case nothingLeft
    }

    struct Snapshot: Equatable {
        var date: Date
        var state: State
        var done: Int
        var total: Int
        /// What comes after the current block (or after now), soonest first; for medium/large widgets.
        var upcoming: [Block] = []
    }

    /// The state at `date`. `blocks` is that day's effective plan.
    static func snapshot(at date: Date, blocks: [Block], completed: Set<String>, skipped: Set<String>, hasPlan: Bool, calendar: Calendar) -> Snapshot {
        let counted = blocks.filter { !skipped.contains($0.id) }
        let done = counted.filter { completed.contains($0.id) }.count
        let state: State
        if !hasPlan {
            state = .noPlan
        } else if let block = DayLogic.currentBlock(blocks, now: date, completed: completed, skipped: skipped, calendar: calendar) {
            state = .now(block, missed: block.status(now: date, completed: completed, skipped: skipped, calendar: calendar) == .missed)
        } else if let next = DayLogic.nextUp(blocks, now: date, completed: completed, skipped: skipped, calendar: calendar) {
            state = .next(next)
        } else if done == counted.count {
            state = .allDone
        } else {
            state = .nothingLeft
        }
        let currentID: String? = { if case .now(let b, _) = state { return b.id } else { return nil } }()
        let upcoming = DayLogic.sorted(blocks).filter { $0.id != currentID && $0.status(now: date, completed: completed, skipped: skipped, calendar: calendar) == .upcoming }
        return Snapshot(date: date, state: state, done: done, total: counted.count, upcoming: Array(upcoming.prefix(6)))
    }

    /// One snapshot now, then one at every block start/end over the next `days` days (plus each
    /// midnight), dropping consecutive duplicates. Capped so WidgetKit accepts it.
    static func snapshots(
        now: Date, days: Int = 2, cap: Int = 60,
        plan: (Date) -> [Block], completed: (String) -> Set<String>, skipped: (String) -> Set<String>,
        hasPlan: Bool, calendar: Calendar = .current
    ) -> [Snapshot] {
        var moments: [Date] = [now]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if offset > 0 { moments.append(calendar.startOfDay(for: day)) }
            for block in plan(day) where block.occurs(on: day, calendar: calendar) {
                if let s = block.startDate(on: day, calendar: calendar), s > now { moments.append(s) }
                // The block turns missed the minute after it ends.
                if let e = block.endDate(on: day, calendar: calendar), let after = calendar.date(byAdding: .minute, value: 1, to: e), after > now { moments.append(after) }
            }
        }
        var result: [Snapshot] = []
        for moment in Set(moments).sorted().prefix(cap) {
            let day = moment
            let key = DayLogic.dayKey(day, calendar: calendar)
            let snap = snapshot(at: moment, blocks: plan(day), completed: completed(key), skipped: skipped(key), hasPlan: hasPlan, calendar: calendar)
            if snap.state != result.last?.state || snap.done != result.last?.done { result.append(snap) }
        }
        return result
    }
}
