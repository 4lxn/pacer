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
