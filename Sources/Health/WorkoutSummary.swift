import Foundation

enum WorkoutActivity: String, Codable, Sendable {
    case run, strength, walk, cycle, other
}

/// A workout as the app sees it, independent of HealthKit types so logic stays testable.
struct WorkoutSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let activity: WorkoutActivity
    let start: Date
    let end: Date
    let distanceMeters: Double?
    let kcal: Double?
    let source: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// What closes a block automatically: a Health workout of a kind, or a study session.
enum WorkoutMatch: String, Codable, Sendable {
    case run
    case strength
    case study

    func matches(_ workout: WorkoutSummary) -> Bool {
        switch self {
        case .run: workout.activity == .run
        case .strength: workout.activity == .strength
        case .study: false
        }
    }

    /// Minutes of study on the day needed to close a `.study` block.
    static let studyMinutesToClose = 20
}

struct WeekTotals: Equatable {
    var runs = 0
    var runMeters = 0.0
    var lifts = 0
    var minutes = 0

    var runKilometers: Double { runMeters / 1000 }

    /// Totals for the calendar week (per `calendar.firstWeekday`) containing `date`.
    static func make(_ workouts: [WorkoutSummary], weekOf date: Date, calendar: Calendar) -> WeekTotals {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return WeekTotals() }
        var totals = WeekTotals()
        for w in workouts where week.contains(w.start) {
            totals.minutes += Int(w.duration / 60)
            switch w.activity {
            case .run:
                totals.runs += 1
                totals.runMeters += w.distanceMeters ?? 0
            case .strength:
                totals.lifts += 1
            default:
                break
            }
        }
        return totals
    }
}

extension DayLogic {
    /// Ids of blocks that a workout done today closes: the block has an `autoComplete` match, is not
    /// done yet, and a matching workout started on the same calendar day as `now`.
    static func autoCompletions(_ blocks: [Block], workouts: [WorkoutSummary], studyMinutesToday: Int = 0, now: Date, completed: Set<String>, calendar: Calendar = .current) -> [String] {
        let today = workouts.filter { calendar.isDate($0.start, inSameDayAs: now) }
        return blocks.compactMap { block in
            guard let match = block.autoComplete, !completed.contains(block.id) else { return nil }
            if match == .study { return studyMinutesToday >= WorkoutMatch.studyMinutesToClose ? block.id : nil }
            return today.contains(where: match.matches) ? block.id : nil
        }
    }
}
