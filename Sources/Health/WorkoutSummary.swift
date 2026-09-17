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
    var avgHeartRate: Double? = nil

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// min/km for anything with distance.
    var paceMinPerKm: Double? {
        guard let m = distanceMeters, m > 500 else { return nil }
        return duration / 60 / (m / 1000)
    }

    static func pace(_ minPerKm: Double) -> String {
        let total = Int((minPerKm * 60).rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }
}

/// One week of training, for the 8-week chart.
struct WeekBar: Identifiable, Equatable {
    let weekStart: Date
    var runMinutes = 0
    var strengthMinutes = 0
    var otherMinutes = 0
    var runKilometers = 0.0
    var lifts = 0
    var id: Date { weekStart }

    /// Oldest first, `weeks` entries ending with the current week; empty weeks included.
    static func make(_ workouts: [WorkoutSummary], weeks: Int, now: Date, calendar: Calendar) -> [WeekBar] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var bars: [WeekBar] = (0..<weeks).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek).map { WeekBar(weekStart: $0) }
        }
        for w in workouts {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: w.start)?.start,
                  let i = bars.firstIndex(where: { $0.weekStart == start }) else { continue }
            let minutes = Int(w.duration / 60)
            switch w.activity {
            case .run: bars[i].runMinutes += minutes; bars[i].runKilometers += (w.distanceMeters ?? 0) / 1000
            case .strength: bars[i].strengthMinutes += minutes; bars[i].lifts += 1
            default: bars[i].otherMinutes += minutes
            }
        }
        return bars
    }
}

enum WeightStats {
    /// Trailing 7-day average at each sample (by date, not by count).
    static func movingAverage(_ samples: [WeightSample], days: Int = 7, calendar: Calendar) -> [WeightSample] {
        samples.map { s in
            let from = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: s.date)) ?? s.date
            let window = samples.filter { $0.date >= from && $0.date <= s.date }
            return WeightSample(date: s.date, kg: window.map(\.kg).reduce(0, +) / Double(window.count))
        }
    }

    /// Change between the latest 7-day average and the one a week earlier; nil without enough data.
    static func weeklyChange(_ samples: [WeightSample], now: Date, calendar: Calendar) -> Double? {
        func avg(endingAt end: Date) -> Double? {
            let from = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: end))!
            let w = samples.filter { $0.date >= from && $0.date <= end }.map(\.kg)
            return w.isEmpty ? nil : w.reduce(0, +) / Double(w.count)
        }
        guard let latest = avg(endingAt: now), let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), let earlier = avg(endingAt: weekAgo) else { return nil }
        return latest - earlier
    }
}

extension WorkoutMatch {
    func matches(_ workout: WorkoutSummary) -> Bool {
        switch self {
        case .run: workout.activity == .run
        case .strength: workout.activity == .strength
        case .study: false
        }
    }
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


/// Personal bests over the loaded window (8 weeks).
struct TrainingBests: Equatable {
    var fastest5kPace: Double?      // min/km over runs ≥ 5 km
    var longestRunKm: Double?
    var longestSessionMinutes: Int?
    var biggestWeekMinutes: Int?

    static func make(_ workouts: [WorkoutSummary], calendar: Calendar) -> TrainingBests {
        var b = TrainingBests()
        for w in workouts {
            if w.activity == .run, let m = w.distanceMeters, m >= 5000, let pace = w.paceMinPerKm { b.fastest5kPace = min(b.fastest5kPace ?? pace, pace) }
            if w.activity == .run, let m = w.distanceMeters { b.longestRunKm = max(b.longestRunKm ?? 0, m / 1000) }
            b.longestSessionMinutes = max(b.longestSessionMinutes ?? 0, Int(w.duration / 60))
        }
        var weeks: [Date: Int] = [:]
        for w in workouts { if let start = calendar.dateInterval(of: .weekOfYear, for: w.start)?.start { weeks[start, default: 0] += Int(w.duration / 60) } }
        b.biggestWeekMinutes = weeks.values.max()
        return b
    }
}

/// One line about how ready you are, from last night and the resting heart rate.
enum Readiness {
    static func line(sleepMinutes: Int?, restingHR: Int?, typicalRestingHR: Int? = nil) -> (text: String, good: Bool) {
        var notes: [String] = []
        var good = true
        if let s = sleepMinutes {
            if s < 6 * 60 { notes.append("short night (\(s / 60) h \(s % 60) min)"); good = false }
            else if s >= 7 * 60 { notes.append("slept \(s / 60) h \(s % 60) min") }
            else { notes.append("\(s / 60) h \(s % 60) min of sleep") }
        }
        if let hr = restingHR {
            if let typical = typicalRestingHR, hr >= typical + 5 { notes.append("resting HR up (\(hr) vs \(typical))"); good = false }
            else { notes.append("resting HR \(hr)") }
        }
        guard !notes.isEmpty else { return ("No sleep or heart data yet.", true) }
        return ((good ? "Ready: " : "Go easy: ") + notes.joined(separator: ", ") + ".", good)
    }
}
