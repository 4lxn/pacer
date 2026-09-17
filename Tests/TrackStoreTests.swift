import XCTest
@testable import Autopiloto

@MainActor
final class TrackStoreTests: XCTestCase {
    private var fileURL: URL!
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        c.firstWeekday = 2
        return c
    }()

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("track-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func date(_ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
    }

    func testStudyTimerSurvivesRelaunchAndTotals() {
        let store = TrackStore(fileURL: fileURL, calendar: calendar)
        store.startStudy(topic: "Swift", at: date(9, 16, 15, 45))
        XCTAssertTrue(store.isStudying)

        let relaunched = TrackStore(fileURL: fileURL, calendar: calendar)
        XCTAssertTrue(relaunched.isStudying)
        XCTAssertEqual(relaunched.runningTopic, "Swift")
        let session = relaunched.stopStudy(at: date(9, 16, 17, 0))
        XCTAssertEqual(session?.minutes, 75)
        XCTAssertEqual(relaunched.studyMinutes(on: date(9, 16, 20)), 75)

        relaunched.startStudy(topic: "", at: date(9, 13, 10))   // previous week (Sunday 13th)
        _ = relaunched.stopStudy(at: date(9, 13, 10, 30))
        XCTAssertEqual(relaunched.studyMinutes(weekOf: date(9, 16, 20)), 75)
        XCTAssertEqual(relaunched.recentSessions().first?.topic, "Swift")
        XCTAssertEqual(relaunched.sessions.last?.topic, "Study")
    }

    func testSubMinuteSessionIsDropped() {
        let store = TrackStore(fileURL: fileURL, calendar: calendar)
        store.startStudy(topic: "x", at: date(9, 16, 10))
        XCTAssertNil(store.stopStudy(at: date(9, 16, 10).addingTimeInterval(30)))
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(store.isStudying)
    }

    func testIncomeTotalsByMonthSourceAndYear() {
        let store = TrackStore(fileURL: fileURL, calendar: calendar)
        store.addIncome(source: "Salary", amount: 50000, on: date(9, 1, 9))
        store.addIncome(source: "Freelance", amount: Decimal(string: "12000.50")!, on: date(9, 10, 9))
        store.addIncome(source: "Salary", amount: 50000, on: date(8, 1, 9))
        store.addIncome(source: "Salary", amount: 48000, on: date(1, 15, 9))
        XCTAssertEqual(store.incomeTotal(monthOf: date(9, 16, 12)), Decimal(string: "62000.50")!)
        XCTAssertEqual(store.incomeBySource(monthOf: date(9, 16, 12)).map(\.source), ["Salary", "Freelance"])
        XCTAssertEqual(store.incomeTotal(yearOf: date(9, 16, 12)), Decimal(string: "160000.50")!)
        XCTAssertEqual(store.incomeEntries(monthOf: date(9, 16, 12)).first?.source, "Freelance")

        let again = TrackStore(fileURL: fileURL, calendar: calendar)
        XCTAssertEqual(again.income.count, 4)
        again.deleteIncome(id: again.income[0].id)
        XCTAssertEqual(again.income.count, 3)
    }
}

@MainActor
final class LifeDepthTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()
    private func date(_ d: Int, _ h: Int = 12, month: Int = 9) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: h))! }

    func testStudyByDayTopicStreakAndFocus() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let track = TrackStore(fileURL: dir.appendingPathComponent("track.json"), calendar: calendar)
        track.addSession(start: date(16, 9), minutes: 30, topic: "Swift")
        track.addSession(start: date(15, 9), minutes: 25, topic: "Swift")
        track.addSession(start: date(14, 9), minutes: 45, topic: "Math")
        track.addSession(start: date(12, 9), minutes: 10, topic: "Math")   // too short for the streak, and breaks it
        XCTAssertEqual(track.studyStreak(now: date(16)), 3)
        XCTAssertEqual(track.studyStreak(now: date(17)), 3)                  // yesterday counts when today is empty
        XCTAssertEqual(track.studyStreak(now: date(18)), 0)
        XCTAssertEqual(track.studyMinutesByDay(days: 3, now: date(16)).map(\.minutes), [45, 25, 30])
        XCTAssertEqual(track.studyByTopic(weekOf: date(16)).map(\.topic), ["Swift", "Math"])   // week of Mon 14: Swift 55, Math 45

        track.startStudy(topic: "Swift", at: date(16, 20), focusMinutes: 25)
        XCTAssertEqual(track.runningUntil, date(16, 20).addingTimeInterval(1500))
        XCTAssertEqual(TrackStore(fileURL: dir.appendingPathComponent("track.json"), calendar: calendar).runningUntil, track.runningUntil)
        XCTAssertNotNil(track.stopStudy(at: date(16, 20).addingTimeInterval(1800)))
        XCTAssertNil(track.runningUntil)

        track.monthlyIncomeGoal = 30000
        track.addIncome(source: "Salary", amount: 20000, on: date(1))
        track.addIncome(source: "Freelance", amount: 5000, on: date(3, month: 8))
        let months = track.incomeByMonth(months: 3, now: date(16))
        XCTAssertEqual(months.map(\.amount), [0, 5000, 20000])
        XCTAssertEqual(TrackStore(fileURL: dir.appendingPathComponent("track.json"), calendar: calendar).monthlyIncomeGoal, 30000)
    }
}

@MainActor
final class FocusSubjectsTests: XCTestCase {
    func testSubjectsAdoptTopicsRenameAndExtend() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("track.json")
        let t = TrackStore(fileURL: url)
        t.addSession(start: .now.addingTimeInterval(-3600), minutes: 30, topic: "Swift")
        let again = TrackStore(fileURL: url)
        XCTAssertEqual(again.subjects.map(\.name), ["Swift"])        // adopted from the session topic
        var swift = again.subjects[0]; swift.name = "SwiftUI"; swift.weeklyGoalMinutes = 120
        again.upsertSubject(swift)
        XCTAssertEqual(again.sessions[0].topic, "SwiftUI")             // sessions follow the rename
        XCTAssertEqual(again.minutes(subject: "swiftui", weekOf: .now), 30)
        again.startStudy(topic: "SwiftUI", at: .now, focusMinutes: 25)
        let before = again.runningUntil!
        again.extendFocus(by: 5, now: .now)
        XCTAssertEqual(again.runningUntil!.timeIntervalSince(before), 300, accuracy: 2)
        again.deleteSubject(id: swift.id)
        XCTAssertTrue(again.subjects.isEmpty)
    }
}

@MainActor
final class MoneyTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Mexico_City")!; return c
    }()
    private func date(_ d: Int, month: Int = 9) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: 12))! }

    func testExpensesBudgetsAndSavings() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("track.json")
        let t = TrackStore(fileURL: url, calendar: calendar)
        t.addIncome(source: "Salary", amount: 30000, on: date(1))
        t.addExpense(category: "Rent", amount: 12000, note: "Sept", on: date(2))
        t.addExpense(category: "Food", amount: 3500, on: date(5))
        t.addExpense(category: "Food", amount: 1500, on: date(9))
        t.addExpense(category: "Fun", amount: 800, on: date(3, month: 8))   // last month
        t.setBudget(6000, category: "Food"); t.setBudget(500, category: "Transport")
        XCTAssertEqual(t.expenseTotal(monthOf: date(16)), 17000)
        XCTAssertEqual(t.saved(monthOf: date(16)), 13000)
        XCTAssertEqual(t.savingsRate(monthOf: date(16))!, 13000.0 / 30000.0, accuracy: 0.0001)
        XCTAssertEqual(t.expensesByCategory(monthOf: date(16)).map(\.category), ["Rent", "Food", "Transport"])   // budgeted-but-empty included
        XCTAssertEqual(t.expenseCategories.prefix(2), ["Food", "Rent"])                                       // most used first
        XCTAssertEqual(t.moneyByMonth(months: 2, now: date(16)).map(\.spent), [800, 17000])
        XCTAssertNil(TrackStore(fileURL: dir.appendingPathComponent("empty.json"), calendar: calendar).savingsRate(monthOf: date(16)))
        let again = TrackStore(fileURL: url, calendar: calendar)
        XCTAssertEqual(again.budgets["Food"], 6000)
        again.setBudget(0, category: "Transport")
        XCTAssertNil(again.budgets["Transport"])
        again.deleteExpense(id: again.expenses[0].id)
        XCTAssertEqual(again.expenses.count, 3)
    }
}
