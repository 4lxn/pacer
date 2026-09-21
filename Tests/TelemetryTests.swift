import XCTest
@testable import Autopiloto

@MainActor
final class TelemetryTests: XCTestCase {
    func testEventsAreCountsOnly() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metrics-\(UUID().uuidString).json")
        let metrics = MetricsStore(fileURL: url)
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        metrics.record(.appOpen, on: day); metrics.record(.appOpen, on: day)
        metrics.record(.doneNotification, on: day); metrics.record(.doneHealth, on: day)
        metrics.record(.checkInReplan, on: day); metrics.record(.replanNotification, on: day)
        let key = DayLogic.dayKey(day, calendar: .current)
        let e = Telemetry.events(metrics: metrics, dayKey: key, onPace: true)
        XCTAssertEqual(e, ["opened": 2, "closed": 2, "closedHealth": 1, "checkInNotif": 1, "moved": 1, "onPace": 1])
        XCTAssertTrue(e.values.allSatisfy { $0 >= 0 }, "integers only; nothing that could carry content")
    }

    func testTurningOffDiscardsTheID() {
        Telemetry.isEnabled = true
        let first = Telemetry.id
        XCTAssertEqual(Telemetry.id, first)
        Telemetry.isEnabled = false
        Telemetry.isEnabled = true
        XCTAssertNotEqual(Telemetry.id, first)
    }
}
