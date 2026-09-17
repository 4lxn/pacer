import Foundation
import Observation

struct StudySession: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var start: Date
    var end: Date
    var topic: String

    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// What you focus on. Sessions reference it by name (older sessions had free-text topics).
struct Subject: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var weeklyGoalMinutes: Int = 0   // 0 = no goal
    var symbol: String = "book"
}

struct ExpenseEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var date: Date
    var category: String
    var note: String = ""
    var amount: Decimal
    var recurringID: String? = nil
}

/// Salary on the 1st, rent on the 5th: applied once per month when the day arrives.
struct RecurringEntry: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case income, expense }
    var id: String = UUID().uuidString
    var kind: Kind
    var name: String          // income source or expense category
    var amount: Decimal
    var dayOfMonth: Int       // 1…28
    var note: String = ""
}

enum ExpenseCategory {
    static let defaults = ["Rent", "Food", "Transport", "Gym", "Health", "Fun", "Shopping", "Bills", "Other"]
    static func symbol(_ name: String) -> String {
        switch name.lowercased() {
        case "rent", "home": "house"
        case "food", "groceries": "cart"
        case "transport", "car", "uber": "car"
        case "gym", "training": "dumbbell"
        case "health": "cross.case"
        case "fun", "going out": "party.popper"
        case "shopping", "clothes": "bag"
        case "bills", "subscriptions": "doc.text"
        default: "creditcard"
        }
    }
}

struct IncomeEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var date: Date
    var source: String
    var amount: Decimal
    var recurringID: String? = nil
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
        var runningUntil: Date?
        var monthlyIncomeGoal: Decimal?
        var subjects: [Subject]?
        var expenses: [ExpenseEntry]?
        var budgets: [String: Decimal]?
        var recurring: [RecurringEntry]?
    }

    private(set) var sessions: [StudySession] = []
    private(set) var subjects: [Subject] = []
    private(set) var income: [IncomeEntry] = []
    private(set) var expenses: [ExpenseEntry] = []
    /// Monthly budget per category (flat, every month).
    private(set) var budgets: [String: Decimal] = [:]
    private(set) var recurring: [RecurringEntry] = []
    var weeklyStudyGoalMinutes = 300 { didSet { save() } }
    var monthlyIncomeGoal: Decimal = 0 { didSet { save() } }
    private(set) var runningSince: Date?
    private(set) var runningTopic = ""
    /// Focus target for the running session (pomodoro); the timer keeps counting past it.
    private(set) var runningUntil: Date?

    private let fileURL: URL
    private let calendar: Calendar

    static var defaultURL: URL {
        AppFiles.url("track.json")
    }

    init(fileURL: URL = TrackStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if case .loaded(let s) = JSONFile.load(Snapshot.self, from: fileURL) {
            sessions = s.sessions; income = s.income; weeklyStudyGoalMinutes = s.weeklyStudyGoalMinutes
            runningSince = s.runningSince; runningTopic = s.runningTopic; runningUntil = s.runningUntil
            monthlyIncomeGoal = s.monthlyIncomeGoal ?? 0
            subjects = s.subjects ?? []
            expenses = s.expenses ?? []
            budgets = s.budgets ?? [:]
            recurring = s.recurring ?? []
            // Adopt topics from older sessions as subjects.
            for topic in Set(sessions.map(\.topic)) where topic != "Study" && !subjects.contains(where: { $0.name.caseInsensitiveCompare(topic) == .orderedSame }) {
                subjects.append(Subject(name: topic))
            }
        }
    }

    // MARK: - Study

    var isStudying: Bool { runningSince != nil }

    func startStudy(topic: String, at date: Date = .now, focusMinutes: Int? = nil) {
        guard runningSince == nil else { return }
        runningSince = date
        runningTopic = topic
        runningUntil = focusMinutes.map { date.addingTimeInterval(Double($0) * 60) }
        save()
    }

    /// Ends the running session. Sessions under a minute are dropped.
    @discardableResult
    func stopStudy(at date: Date = .now) -> StudySession? {
        guard let start = runningSince else { return nil }
        runningSince = nil
        runningUntil = nil
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

    /// Minutes per day, oldest first, today last.
    func studyMinutesByDay(days: Int, now: Date) -> [(date: Date, minutes: Int)] {
        (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now).map { (calendar.startOfDay(for: $0), studyMinutes(on: $0)) }
        }
    }

    /// Minutes per topic this week, largest first.
    func studyByTopic(weekOf date: Date) -> [(topic: String, minutes: Int)] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        var totals: [String: Int] = [:]
        for s in sessions where week.contains(s.start) { totals[s.topic, default: 0] += s.minutes }
        return totals.map { ($0.key, $0.value) }.sorted { $0.minutes > $1.minutes }
    }

    // MARK: - Subjects

    func subject(named name: String) -> Subject? { subjects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }

    @discardableResult
    func upsertSubject(_ subject: Subject) -> Subject {
        if let i = subjects.firstIndex(where: { $0.id == subject.id || $0.name.caseInsensitiveCompare(subject.name) == .orderedSame }) {
            let old = subjects[i]
            var s = subject; s.id = old.id
            subjects[i] = s
            if old.name != s.name { for j in sessions.indices where sessions[j].topic == old.name { sessions[j].topic = s.name } }
            save(); return s
        }
        subjects.append(subject)
        save()
        return subject
    }

    func deleteSubject(id: String) {
        subjects.removeAll { $0.id == id }
        save()
    }

    func minutes(subject: String, weekOf date: Date) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return sessions.filter { week.contains($0.start) && $0.topic.caseInsensitiveCompare(subject) == .orderedSame }.reduce(0) { $0 + $1.minutes }
    }

    /// Extend the running focus target by `minutes` (or set one if it was open).
    func extendFocus(by minutes: Int, now: Date = .now) {
        guard runningSince != nil else { return }
        runningUntil = max(runningUntil ?? now, now).addingTimeInterval(Double(minutes) * 60)
        save()
    }

    /// Consecutive days (ending today or yesterday) with at least `minimum` minutes.
    func studyStreak(now: Date, minimum: Int = 20) -> Int {
        var streak = 0
        var day = now
        if studyMinutes(on: now) < minimum {
            guard let y = calendar.date(byAdding: .day, value: -1, to: now), studyMinutes(on: y) >= minimum else { return 0 }
            day = y
        }
        while studyMinutes(on: day) >= minimum {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
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

    /// Monthly totals, oldest first, current month last.
    func incomeByMonth(months: Int, now: Date) -> [(month: Date, amount: Decimal)] {
        (0..<months).reversed().compactMap { offset in
            guard let m = calendar.date(byAdding: .month, value: -offset, to: now), let start = calendar.dateInterval(of: .month, for: m)?.start else { return nil }
            return (start, incomeTotal(monthOf: m))
        }
    }

    // MARK: - Expenses

    func addExpense(category: String, amount: Decimal, note: String = "", on date: Date = .now) {
        expenses.append(ExpenseEntry(date: date, category: category.isEmpty ? "Other" : category, note: note, amount: amount))
        save()
    }

    func deleteExpense(id: String) {
        expenses.removeAll { $0.id == id }
        save()
    }

    func setBudget(_ amount: Decimal, category: String) {
        if amount <= 0 { budgets.removeValue(forKey: category) } else { budgets[category] = amount }
        save()
    }

    // MARK: - Recurring

    func upsertRecurring(_ r: RecurringEntry) {
        var r = r; r.dayOfMonth = min(28, max(1, r.dayOfMonth))
        if let i = recurring.firstIndex(where: { $0.id == r.id }) { recurring[i] = r } else { recurring.append(r) }
        save()
    }

    func deleteRecurring(id: String) {
        recurring.removeAll { $0.id == id }
        save()
    }

    /// Adds this month's entries for every recurring item whose day has come (once per month).
    /// Returns how many were added.
    @discardableResult
    func applyRecurring(now: Date = .now) -> Int {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        let today = calendar.component(.day, from: now)
        var added = 0
        for r in recurring where r.dayOfMonth <= today {
            let date = calendar.date(byAdding: .day, value: r.dayOfMonth - 1, to: month.start) ?? month.start
            switch r.kind {
            case .income:
                guard !income.contains(where: { $0.recurringID == r.id && month.contains($0.date) }) else { continue }
                income.append(IncomeEntry(date: date, source: r.name, amount: r.amount, recurringID: r.id))
            case .expense:
                guard !expenses.contains(where: { $0.recurringID == r.id && month.contains($0.date) }) else { continue }
                expenses.append(ExpenseEntry(date: date, category: r.name, note: r.note, amount: r.amount, recurringID: r.id))
            }
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func expenses(monthOf date: Date) -> [ExpenseEntry] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        return expenses.filter { month.contains($0.date) }.sorted { $0.date > $1.date }
    }

    func expenseTotal(monthOf date: Date) -> Decimal { expenses(monthOf: date).reduce(0) { $0 + $1.amount } }

    /// Per-category spend for the month, largest first; budgeted categories with no spend included.
    func expensesByCategory(monthOf date: Date) -> [(category: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for e in expenses(monthOf: date) { totals[e.category, default: 0] += e.amount }
        for c in budgets.keys where totals[c] == nil { totals[c] = 0 }
        return totals.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
    }

    /// Categories seen so far plus the defaults, most used first.
    var expenseCategories: [String] {
        var counts: [String: Int] = [:]
        for e in expenses { counts[e.category, default: 0] += 1 }
        let used = counts.keys.sorted { (counts[$0]!, $0) > (counts[$1]!, $1) }
        return used + ExpenseCategory.defaults.filter { !counts.keys.contains($0) }
    }

    func saved(monthOf date: Date) -> Decimal { incomeTotal(monthOf: date) - expenseTotal(monthOf: date) }

    /// Saved ÷ income; nil without income.
    func savingsRate(monthOf date: Date) -> Double? {
        let income = incomeTotal(monthOf: date)
        guard income > 0 else { return nil }
        return NSDecimalNumber(decimal: saved(monthOf: date)).doubleValue / NSDecimalNumber(decimal: income).doubleValue
    }

    /// Income and spend per month, oldest first.
    func moneyByMonth(months: Int, now: Date) -> [(month: Date, income: Decimal, spent: Decimal)] {
        (0..<months).reversed().compactMap { offset in
            guard let m = calendar.date(byAdding: .month, value: -offset, to: now), let start = calendar.dateInterval(of: .month, for: m)?.start else { return nil }
            return (start, incomeTotal(monthOf: m), expenseTotal(monthOf: m))
        }
    }

    func incomeTotal(yearOf date: Date) -> Decimal {
        guard let year = calendar.dateInterval(of: .year, for: date) else { return 0 }
        return income.filter { year.contains($0.date) }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Coach

    func coachSummary(now: Date) -> String {
        var lines = ["## Study: \(studyMinutes(on: now)) min today, \(studyMinutes(weekOf: now)) / \(weeklyStudyGoalMinutes) min this week, streak \(studyStreak(now: now)) days"]
        let topics = studyByTopic(weekOf: now)
        if !topics.isEmpty { lines.append("By subject this week: " + topics.map { "\($0.topic) \($0.minutes) min" }.joined(separator: ", ")) }
        if !subjects.isEmpty { lines.append("Subjects: " + subjects.map { $0.weeklyGoalMinutes > 0 ? "\($0.name) (goal \($0.weeklyGoalMinutes) min/wk)" : $0.name }.joined(separator: ", ")) }
        if monthlyIncomeGoal > 0 { lines.append("Income this month: \(incomeTotal(monthOf: now)) of goal \(monthlyIncomeGoal)") }
        if !expenses(monthOf: now).isEmpty || !budgets.isEmpty {
            let cats = expensesByCategory(monthOf: now).map { c in "\(c.category) \(c.amount)" + (budgets[c.category].map { " / \($0)" } ?? "") }.joined(separator: ", ")
            lines.append("Spent this month: \(expenseTotal(monthOf: now)) (\(cats)); saved \(saved(monthOf: now))" + (savingsRate(monthOf: now).map { String(format: ", %.0f%% of income", $0 * 100) } ?? ""))
        }
        if let since = runningSince {
            lines.append("A study session is running since \(since.formatted(date: .omitted, time: .shortened)) (\(runningTopic)).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func save() {
        JSONFile.save(Snapshot(sessions: sessions, income: income, weeklyStudyGoalMinutes: weeklyStudyGoalMinutes, runningSince: runningSince, runningTopic: runningTopic,
                               runningUntil: runningUntil, monthlyIncomeGoal: monthlyIncomeGoal, subjects: subjects, expenses: expenses, budgets: budgets, recurring: recurring), to: fileURL)
    }
}
