import Foundation
import Observation

struct StudySession: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var start: Date
    var end: Date
    var topic: String

    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct IncomeEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var date: Date
    var source: String
    var amount: Decimal
}

/// Study sessions (with a running timer that survives relaunch) and income entries.
@Observable
@MainActor
final class TrackStore {
    private struct Snapshot: Codable {
        var sessions: [StudySession]
        var income: [IncomeEntry]
        var weeklyStudyGoalMinutes: Int
        var runningSince: Date?
        var runningTopic: String
    }

    private(set) var sessions: [StudySession] = []
    private(set) var income: [IncomeEntry] = []
    var weeklyStudyGoalMinutes = 300 { didSet { save() } }
    private(set) var runningSince: Date?
    private(set) var runningTopic = ""

    private let fileURL: URL
    private let calendar: Calendar

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("track.json")
    }

    init(fileURL: URL = TrackStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            sessions = s.sessions; income = s.income; weeklyStudyGoalMinutes = s.weeklyStudyGoalMinutes
            runningSince = s.runningSince; runningTopic = s.runningTopic
        }
    }

    // MARK: - Study

    var isStudying: Bool { runningSince != nil }

    func startStudy(topic: String, at date: Date = .now) {
        guard runningSince == nil else { return }
        runningSince = date
        runningTopic = topic
        save()
    }

    /// Ends the running session. Sessions under a minute are dropped.
    @discardableResult
    func stopStudy(at date: Date = .now) -> StudySession? {
        guard let start = runningSince else { return nil }
        runningSince = nil
        let topic = runningTopic
        runningTopic = ""
        guard date.timeIntervalSince(start) >= 60 else { save(); return nil }
        let session = StudySession(start: start, end: date, topic: topic.isEmpty ? "Study" : topic)
        sessions.append(session)
        save()
        return session
    }

    /// A session logged after the fact (e.g. "I studied 45 min this morning").
    func addSession(start: Date, minutes: Int, topic: String) {
        sessions.append(StudySession(start: start, end: start.addingTimeInterval(Double(max(1, minutes)) * 60), topic: topic.isEmpty ? "Study" : topic))
        save()
    }

    func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func studyMinutes(on date: Date) -> Int {
        sessions.filter { calendar.isDate($0.start, inSameDayAs: date) }.reduce(0) { $0 + $1.minutes }
    }

    func studyMinutes(weekOf date: Date) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return sessions.filter { week.contains($0.start) }.reduce(0) { $0 + $1.minutes }
    }

    func recentSessions(limit: Int = 10) -> [StudySession] {
        Array(sessions.sorted { $0.start > $1.start }.prefix(limit))
    }

    // MARK: - Income

    func addIncome(source: String, amount: Decimal, on date: Date = .now) {
        income.append(IncomeEntry(date: date, source: source.isEmpty ? "Income" : source, amount: amount))
        save()
    }

    func deleteIncome(id: String) {
        income.removeAll { $0.id == id }
        save()
    }

    func incomeTotal(monthOf date: Date) -> Decimal {
        incomeEntries(monthOf: date).reduce(0) { $0 + $1.amount }
    }

    func incomeEntries(monthOf date: Date) -> [IncomeEntry] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        return income.filter { month.contains($0.date) }.sorted { $0.date > $1.date }
    }

    /// Per-source totals for the month, largest first.
    func incomeBySource(monthOf date: Date) -> [(source: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for e in incomeEntries(monthOf: date) { totals[e.source, default: 0] += e.amount }
        return totals.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
    }

    func incomeTotal(yearOf date: Date) -> Decimal {
        guard let year = calendar.dateInterval(of: .year, for: date) else { return 0 }
        return income.filter { year.contains($0.date) }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Coach

    func coachSummary(now: Date) -> String {
        var lines = ["## Study: \(studyMinutes(on: now)) min today, \(studyMinutes(weekOf: now)) / \(weeklyStudyGoalMinutes) min this week"]
        if let since = runningSince {
            lines.append("A study session is running since \(since.formatted(date: .omitted, time: .shortened)) (\(runningTopic)).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let s = Snapshot(sessions: sessions, income: income, weeklyStudyGoalMinutes: weeklyStudyGoalMinutes, runningSince: runningSince, runningTopic: runningTopic)
            try JSONEncoder().encode(s).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("TrackStore save failed: \(error)")
        }
    }
}
