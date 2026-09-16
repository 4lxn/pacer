import UserNotifications
import XCTest
@testable import Autopiloto

final class SchedulerTests: XCTestCase {
    func testOneRepeatingTriggerPerFixedBlockAndWeekday() {
        let requests = NotificationScheduler.buildRequests(for: Plan.blocks)
        let expected = Plan.blocks.filter { $0.kind == .fixed }.reduce(0) { $0 + ($1.weekdays?.count ?? 1) }
        XCTAssertEqual(requests.count, expected)
        XCTAssertEqual(requests.count, 30)
        for request in requests {
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            XCTAssertNotNil(trigger, request.identifier)
            XCTAssertTrue(trigger?.repeats ?? false, request.identifier)
        }
        XCTAssertEqual(Set(requests.map(\.identifier)).count, requests.count)
    }

    func testNonFixedBlocksProduceNothing() {
        let blocks = [
            Block(id: "w", label: "W", kind: .window, start: .hm(9, 0), end: .hm(9, 30)),
            Block(id: "f", label: "F", kind: .free),
        ]
        XCTAssertTrue(NotificationScheduler.buildRequests(for: blocks).isEmpty)
    }

    func testBlockIDRoundTripsThroughUserInfo() {
        let block = Block(id: "b13", label: "Leave", kind: .fixed, start: .hm(17, 45), end: .hm(17, 55))
        let request = NotificationScheduler.buildRequests(for: [block])[0]
        XCTAssertEqual(request.content.userInfo[NotificationScheduler.blockIDKey] as? String, "b13")
        XCTAssertEqual(request.content.categoryIdentifier, "BLOCK_ACTIONS")
        let trigger = request.trigger as! UNCalendarNotificationTrigger
        XCTAssertEqual(trigger.dateComponents.hour, 17)
        XCTAssertEqual(trigger.dateComponents.minute, 45)
        XCTAssertNil(trigger.dateComponents.weekday)
    }

    func testWeekdayBlocksCarryTheWeekday() {
        let block = Block(id: "b07", label: "Work", kind: .fixed, start: .hm(10, 0), end: .hm(13, 0), weekdays: [2, 3])
        let requests = NotificationScheduler.buildRequests(for: [block])
        XCTAssertEqual(requests.map(\.identifier), ["b07-wd2", "b07-wd3"])
        let weekdays = requests.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday }
        XCTAssertEqual(weekdays, [2, 3])
    }

    func testAnchorIsTimeSensitive() {
        let anchor = Plan.blocks.first { $0.isAnchor }!
        let other = Plan.blocks.first { $0.kind == .fixed && !$0.isAnchor }!
        XCTAssertEqual(NotificationScheduler.content(for: anchor).interruptionLevel, .timeSensitive)
        XCTAssertEqual(NotificationScheduler.content(for: other).interruptionLevel, .active)
    }

    func testSnoozeIsOneShotTenMinutes() {
        let request = NotificationScheduler.snoozeRequest(for: Plan.blocks[0])
        let trigger = request.trigger as! UNTimeIntervalNotificationTrigger
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.timeInterval, 600)
        XCTAssertEqual(request.content.userInfo[NotificationScheduler.blockIDKey] as? String, "b01")
    }

    func testPlanStaysUnderTheCeiling() {
        XCTAssertLessThanOrEqual(NotificationScheduler.buildRequests(for: Plan.blocks).count, NotificationScheduler.maxPending)
    }

    func testCeilingIsDetectable() {
        // 65 daily fixed blocks would exceed the ceiling; buildRequests still reports the true count.
        let many = (0..<65).map { Block(id: "x\($0)", label: "X", kind: .fixed, start: .hm(0, $0 % 60), end: .hm(1, 0)) }
        XCTAssertGreaterThan(NotificationScheduler.buildRequests(for: many).count, NotificationScheduler.maxPending)
    }
}
