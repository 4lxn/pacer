import XCTest
@testable import Autopiloto

final class QuickAddTests: XCTestCase {
    func testPhrasings() {
        XCTAssertEqual(QuickAdd.parse("gym 7pm 45m"), .init(label: "Gym", start: .hm(19, 0), end: .hm(19, 45)))
        XCTAssertEqual(QuickAdd.parse("gym at 7pm for 45 min"), .init(label: "Gym", start: .hm(19, 0), end: .hm(19, 45)))
        XCTAssertEqual(QuickAdd.parse("call mom 19:00"), .init(label: "Call mom", start: .hm(19, 0), end: .hm(19, 30)))
        XCTAssertEqual(QuickAdd.parse("deep work 9:30-11"), .init(label: "Deep work", start: .hm(9, 30), end: .hm(11, 0)))
        XCTAssertEqual(QuickAdd.parse("lunch noon 1h"), .init(label: "Lunch", start: .hm(12, 0), end: .hm(13, 0)))
        XCTAssertEqual(QuickAdd.parse("run 6:30am 40m"), .init(label: "Run", start: .hm(6, 30), end: .hm(7, 10)))
        XCTAssertEqual(QuickAdd.parse("dentist from 3pm to 4:15pm"), .init(label: "Dentist", start: .hm(15, 0), end: .hm(16, 15)))
        XCTAssertEqual(QuickAdd.parse("water"), .init(label: "Water", start: nil, end: nil))
        XCTAssertEqual(QuickAdd.parse("read 20 pages"), .init(label: "Read 20 pages", start: nil, end: nil), "a bare number is not a time")
        XCTAssertEqual(QuickAdd.parse("wind down 11:45pm 30m"), .init(label: "Wind down", start: .hm(23, 45), end: .hm(23, 59)), "clamped to the day")
        XCTAssertNil(QuickAdd.parse("   "))
        XCTAssertNil(QuickAdd.parse("7pm"), "a time with no label is not a block")
    }
}
