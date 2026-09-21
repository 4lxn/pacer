import Foundation

/// Moves a missed block into free time later today. Pure: takes the effective plan and returns
/// the override to apply. All math is minutes of the calendar day.
enum Replanner {
    static let minimumMinutes = 20
    static let granularity = 5

    enum Outcome: Equatable {
        /// New times for the block (and any windows pushed to make room).
        case moved(DayOverride, pushed: [String], pushedOut: [String])
        /// Same as moved but the block was shortened to the largest gap available.
        case shrunk(DayOverride, minutes: Int, pushed: [String], pushedOut: [String])
        /// No gap of at least `minimumMinutes` before day end.
        case noRoom
        case rejected(String)

        var override: DayOverride? {
            switch self {
            case let .moved(o, _, _), let .shrunk(o, _, _, _): o
            default: nil
            }
        }
    }

    struct Context {
        var plan: [Block]              // effective plan for the day (overrides applied)
        var override: DayOverride      // current override (to extend)
        var now: Date
        var dayEnd: DateComponents
        var completed: Set<String>
        var skipped: Set<String>
        var calendar: Calendar = .current
        var places = Places()
        /// Busy time from outside the plan (calendar events); never moved, never a block.
        var busy: [Obstacle] = []
    }

    /// An obstacle on the day: fixed or in-progress block the moved one must not overlap, with
    /// where it happens so travel fits on both sides.
    struct Obstacle: Equatable {
        var start: Int
        var end: Int
        var label: String
        var place: String?
    }

    /// Find the first gap that fits the block after `max(now, end)`; else shrink; else no room.
    static func replan(_ block: Block, in ctx: Context) -> Outcome {
        guard let dur = block.durationMinutes, dur > 0, let end = block.end else { return .rejected("This block has no time.") }
        if block.isAnchor { return .rejected("The anchor block stays where it is.") }
        if ctx.completed.contains(block.id) { return .rejected("Already done.") }
        let from = roundUp(max(DayLogic.minutesOfDay(ctx.now, calendar: ctx.calendar), DayLogic.minutes(end)))
        let dayEnd = DayLogic.minutes(ctx.dayEnd)
        guard from < dayEnd else { return .noRoom }
        let gaps = freeGaps(from: from, to: dayEnd, obstacles: obstacles(in: ctx, excluding: block.id), place: block.place, places: ctx.places)
        if let gap = gaps.first(where: { $0.1 - $0.0 >= dur }) {
            return apply(block, start: gap.0, minutes: dur, ctx: ctx, shrunk: false)
        }
        if let gap = gaps.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }), gap.1 - gap.0 >= minimumMinutes {
            return apply(block, start: gap.0, minutes: gap.1 - gap.0, ctx: ctx, shrunk: true)
        }
        return .noRoom
    }

    /// Put the block at an explicit start (coach `move_today`). Rejects the past, obstacles and day end.
    static func place(_ block: Block, at start: DateComponents, in ctx: Context) -> Outcome {
        guard let dur = block.durationMinutes, dur > 0 else { return .rejected("This block has no time.") }
        if block.isAnchor { return .rejected("The anchor block stays where it is.") }
        if ctx.completed.contains(block.id) { return .rejected("Already done.") }
        let s = DayLogic.minutes(start), e = s + dur
        if s < DayLogic.minutesOfDay(ctx.now, calendar: ctx.calendar) { return .rejected("That time already passed.") }
        if e > DayLogic.minutes(ctx.dayEnd) { return .rejected("That runs past the end of your day.") }
        let obs = obstacles(in: ctx, excluding: block.id)
        if let hit = obs.first(where: { $0.end > s && $0.start < e }) {
            return .rejected("That overlaps \(hit.label).")
        }
        if let before = obs.last(where: { $0.end <= s }), ctx.places.minutes(from: before.place, to: block.place) > s - before.end {
            return .rejected("Not enough time to get there from \(before.label) (\(ctx.places.minutes(from: before.place, to: block.place)) min).")
        }
        if let after = obs.first(where: { $0.start >= e }), ctx.places.minutes(from: block.place, to: after.place) > after.start - e {
            return .rejected("Not enough time to get to \(after.label) afterwards (\(ctx.places.minutes(from: block.place, to: after.place)) min).")
        }
        return apply(block, start: s, minutes: dur, ctx: ctx, shrunk: false)
    }

    // MARK: - Internals

    /// (start, end, label) of every not-done, not-skipped fixed block, plus any window block in
    /// progress right now. Other windows are pushable.
    static func obstacles(in ctx: Context, excluding id: String) -> [Obstacle] {
        let nowMin = DayLogic.minutesOfDay(ctx.now, calendar: ctx.calendar)
        let fromPlan: [Obstacle] = ctx.plan.compactMap { b in
            guard b.id != id, let s = b.start, let e = b.end, !ctx.completed.contains(b.id), !ctx.skipped.contains(b.id) else { return nil }
            let sm = DayLogic.minutes(s), em = DayLogic.minutes(e)
            let isCurrentWindow = b.kind == .window && sm <= nowMin && nowMin <= em
            return b.kind == .fixed || isCurrentWindow ? Obstacle(start: sm, end: em, label: b.label, place: b.place) : nil
        }
        return (fromPlan + ctx.busy).sorted { $0.start < $1.start }
    }

    /// Free intervals between obstacles, each shrunk by the travel needed from the obstacle
    /// before it and to the obstacle after it (for a block at `place`).
    static func freeGaps(from: Int, to: Int, obstacles: [Obstacle], place: String? = nil, places: Places = Places()) -> [(Int, Int)] {
        var gaps: [(Int, Int)] = []
        var cursor = from
        var previous: Obstacle?
        for o in obstacles where o.end > from {
            if o.start > cursor {
                let lead = places.minutes(from: previous?.place, to: place)
                let tail = places.minutes(from: place, to: o.place)
                gaps.append((cursor + lead, min(o.start - tail, to)))
            }
            cursor = max(cursor, o.end)
            previous = o
            if cursor >= to { break }
        }
        if cursor < to { gaps.append((cursor + places.minutes(from: previous?.place, to: place), to)) }
        return gaps.filter { $0.1 > $0.0 }.map { (roundUp($0.0), $0.1) }.filter { $0.1 > $0.0 }
    }

    private static func apply(_ block: Block, start: Int, minutes: Int, ctx: Context, shrunk: Bool) -> Outcome {
        var override = ctx.override
        override.moved[block.id] = MovedTime(start: DayLogic.components(minutes: start), end: DayLogic.components(minutes: start + minutes))
        var placedEnd = start + minutes
        var pushed: [String] = [], pushedOut: [String] = []
        let dayEnd = DayLogic.minutes(ctx.dayEnd)
        let nowMin = DayLogic.minutesOfDay(ctx.now, calendar: ctx.calendar)
        // Pushable windows intersecting the placed interval, in start order, cascade forward.
        let windows = ctx.plan.filter { b in
            b.kind == .window && b.id != block.id && !ctx.completed.contains(b.id) && !ctx.skipped.contains(b.id)
        }.compactMap { b -> (Block, Int, Int)? in
            guard let s = b.start, let e = b.end else { return nil }
            let sm = DayLogic.minutes(s), em = DayLogic.minutes(e)
            return (sm <= nowMin && nowMin <= em) ? nil : (b, sm, em)   // current windows were obstacles
        }.sorted { $0.1 < $1.1 }
        for (b, sm, em) in windows where em > start && sm < placedEnd {
            let width = em - sm
            let newStart = placedEnd, newEnd = placedEnd + width
            if newEnd > dayEnd {
                pushedOut.append(b.id)
                continue
            }
            override.moved[b.id] = MovedTime(start: DayLogic.components(minutes: newStart), end: DayLogic.components(minutes: newEnd))
            pushed.append(b.id)
            placedEnd = newEnd
        }
        return shrunk ? .shrunk(override, minutes: minutes, pushed: pushed, pushedOut: pushedOut) : .moved(override, pushed: pushed, pushedOut: pushedOut)
    }

    private static func roundUp(_ m: Int) -> Int { (m + granularity - 1) / granularity * granularity }
}
