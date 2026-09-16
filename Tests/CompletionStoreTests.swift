import XCTest
@testable import Autopiloto

@MainActor
final class CompletionStoreTests: XCTestCase {
    private var url: URL!
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    override func setUp() async throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("completions-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func date(_ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    func testMarkDonePersistsAcrossInstances() {
        let a = CompletionStore(fileURL: url, calendar: calendar)
        a.markDone("b01", on: date(16, 8))
        let b = CompletionStore(fileURL: url, calendar: calendar)
        XCTAssertEqual(b.completed(on: date(16, 20)), ["b01"])
    }

    func testRollsOverAtMidnight() {
        let store = CompletionStore(fileURL: url, calendar: calendar)
        store.markDone("b01", on: date(16, 23))
        XCTAssertEqual(store.completed(on: date(16, 23)), ["b01"])
        XCTAssertEqual(store.completed(on: date(17, 0)), [])
    }

    func testToggle() {
        let store = CompletionStore(fileURL: url, calendar: calendar)
        store.toggle("b02", on: date(16, 9))
        XCTAssertTrue(store.completed(on: date(16, 9)).contains("b02"))
        store.toggle("b02", on: date(16, 9))
        XCTAssertFalse(store.completed(on: date(16, 9)).contains("b02"))
    }
}
