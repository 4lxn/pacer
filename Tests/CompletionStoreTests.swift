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

    func testSkipAndUnskipAndDayKeyAPI() {
        let store = CompletionStore(fileURL: url, calendar: calendar)
        store.skip("b09", on: date(16, 13))
        XCTAssertEqual(store.skipped(on: date(16, 20)), ["b09"])
        store.markDone("b09", dayKey: "2026-09-16")        // done clears skipped
        XCTAssertEqual(store.skipped(dayKey: "2026-09-16"), [])
        XCTAssertEqual(store.completed(dayKey: "2026-09-16"), ["b09"])
        store.skip("b09", dayKey: "2026-09-16")             // skip clears done
        XCTAssertEqual(store.completed(on: date(16, 20)), [])
        store.unskip("b09", on: date(16, 20))
        XCTAssertEqual(store.skipped(on: date(16, 20)), [])
        XCTAssertEqual(CompletionStore(fileURL: url, calendar: calendar).days["2026-09-16"], CompletionStore.Day())
    }

    func testReadsThePreSkipFileShape() throws {
        try Data(#"{"2026-09-16":["b01","b02"]}"#.utf8).write(to: url)
        let store = CompletionStore(fileURL: url, calendar: calendar)
        XCTAssertEqual(store.completed(on: date(16, 9)), ["b01", "b02"])
        XCTAssertNil(PersistenceState.shared.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("bad").path))
    }

    func testToggle() {
        let store = CompletionStore(fileURL: url, calendar: calendar)
        store.toggle("b02", on: date(16, 9))
        XCTAssertTrue(store.completed(on: date(16, 9)).contains("b02"))
        store.toggle("b02", on: date(16, 9))
        XCTAssertFalse(store.completed(on: date(16, 9)).contains("b02"))
    }
}
