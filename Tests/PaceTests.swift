import XCTest
@testable import Autopiloto

final class PaceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 20))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }

    /// scores[i] = score `i` days ago; nil = nothing planned.
    private func streak(_ scores: [Double?]) -> Int {
        DayLogic.paceStreak(now: today, calendar: calendar) { date in
            let offset = self.calendar.dateComponents([.day], from: date, to: self.today).day ?? 0
            return offset < scores.count ? scores[offset] : nil
        }
    }

    func testCountsConsecutiveDaysOnPace() {
        XCTAssertEqual(streak([1, 1, 0.9, 0.8]), 4)
        XCTAssertEqual(streak([]), 0)
    }

    func testTodayCountsOnlyOnceOnPace() {
        XCTAssertEqual(streak([0.2, 1, 1]), 2, "today is still in progress: neither a day nor a miss")
        XCTAssertEqual(streak([1, 1, 1]), 3)
    }

    func testOneMissPerWeekIsForgiven() {
        XCTAssertEqual(streak([1, 1, 0.3, 1, 1, 1]), 5)
        XCTAssertEqual(streak([1, 0.3, 1, 1, 0.1, 1, 1]), 3, "two misses within 7 days end the streak at the second")
        XCTAssertEqual(streak([1, 0.3, 1, 1, 1, 1, 1, 1, 0.1, 1, 1]), 9, "misses 7 days apart are both forgiven")
    }

    func testDaysWithNoPlanAreNeutral() {
        XCTAssertEqual(streak([1, nil, nil, 1, 1]), 3)
    }

    @MainActor
    func testNewUsersGetNowAndPace() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sections-\(UUID().uuidString).json")
        let fresh = SectionStore(fileURL: url)
        XCTAssertEqual(fresh.enabled, [.today, .pace])
        XCTAssertTrue(fresh.allowsTool("get_plan"))
        XCTAssertFalse(fresh.allowsTool("get_pantry"))
    }

    @MainActor
    func testExistingUsersGetPaceOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sections-\(UUID().uuidString).json")
        try #"{"enabled":["today","train","coach"]}"#.write(to: url, atomically: true, encoding: .utf8)
        let migrated = SectionStore(fileURL: url)
        XCTAssertEqual(migrated.enabled, [.today, .pace, .train, .coach])
        migrated.set(.pace, on: false)
        XCTAssertEqual(SectionStore(fileURL: url).enabled, [.today, .train, .coach], "turning Pace off sticks")
    }
}
