import XCTest
@testable import Autopiloto

final class OnboardingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testGoalsAddBlocksAtValidTimes() {
        let plan = Plan.plan(wake: .hm(7, 30), sleep: .hm(23, 0), goals: Set(Goal.allCases))
        XCTAssertGreaterThan(plan.count, Plan.starter(wake: .hm(7, 30), sleep: .hm(23, 0)).count)
        for block in plan {
            if let s = block.start, let e = block.end {
                XCTAssertLessThan(DayLogic.minutes(s), DayLogic.minutes(e), block.label)
                XCTAssertLessThanOrEqual(DayLogic.minutes(e), 23 * 60 + 59, block.label)
            }
        }
        XCTAssertEqual(plan.filter { $0.isAnchor }.count, 1)
        XCTAssertFalse(plan.contains { $0.label == "Train" }, "a training goal replaces the generic block")
        XCTAssertTrue(plan.contains { $0.label == "Gym" && $0.autoComplete == .strength })
    }

    func testPlainDayKeepsGenericTraining() {
        let plan = Plan.plan(wake: .hm(7, 30), sleep: .hm(23, 0), goals: [])
        XCTAssertTrue(plan.contains { $0.label == "Train" })
    }

    func testLateWakeClampsToTheDay() {
        let plan = Plan.plan(wake: .hm(11, 0), sleep: .hm(2, 0), goals: [.gym, .read])
        for block in plan { if let e = block.end { XCTAssertLessThanOrEqual(DayLogic.minutes(e), 23 * 60 + 59, block.label) } }
    }

    @MainActor
    func testProfileComposesFromChips() {
        let text = ProfileChips.compose(goals: [.gym, .study], picks: ["training": ["Gym", "Running"], "rules": ["Be blunt"]], wake: .hm(7, 30), sleep: .hm(23, 0), extra: "Remote, two kids.")
        XCTAssertTrue(text.contains("Wakes at 07:30, sleeps at 23:00. Remote, two kids."))
        XCTAssertTrue(text.contains("Gym 3× a week, Study 1 h a day"))
        XCTAssertTrue(text.contains("Gym, Running"))
        XCTAssertTrue(text.contains("Be blunt"))
        XCTAssertTrue(text.contains("(targets, foods I actually eat, rules)"), "empty group keeps the hint")
    }
}
