import XCTest
@testable import Autopiloto

@MainActor
final class PlanStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var planURL: URL { dir.appendingPathComponent("plan.json") }
    private var legacyURL: URL { dir.appendingPathComponent("completions.json") }

    func testFreshInstallNeedsOnboarding() {
        let store = PlanStore(fileURL: planURL, legacyMarker: legacyURL)
        XCTAssertTrue(store.needsOnboarding)
        XCTAssertTrue(store.blocks.isEmpty)
    }

    func testLegacyInstallIsSeededWithTheOriginalDay() throws {
        try Data("{}".utf8).write(to: legacyURL)
        let store = PlanStore(fileURL: planURL, legacyMarker: legacyURL)
        XCTAssertFalse(store.needsOnboarding)
        XCTAssertEqual(store.blocks.map(\.id), Plan.blocks.map(\.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: planURL.path))
    }

    func testReplacePersistsAndClearsOnboarding() {
        let store = PlanStore(fileURL: planURL, legacyMarker: legacyURL)
        store.replace(with: Plan.starter(wake: .hm(7, 0), sleep: .hm(23, 0)))
        XCTAssertFalse(store.needsOnboarding)
        let again = PlanStore(fileURL: planURL, legacyMarker: legacyURL)
        XCTAssertEqual(again.blocks, store.blocks)
        XCTAssertEqual(again.blocks.filter(\.isAnchor).count, 1)
    }

    func testUpsertKeepsExactlyOneAnchorAndDeleteRefusesIt() throws {
        try Data("{}".utf8).write(to: legacyURL)
        let store = PlanStore(fileURL: planURL, legacyMarker: legacyURL)
        var sleep = store.block(id: "b21")!
        sleep.isAnchor = true
        store.upsert(sleep)
        XCTAssertEqual(store.blocks.filter(\.isAnchor).map(\.id), ["b21"])
        XCTAssertFalse(store.delete(id: "b21"))
        XCTAssertTrue(store.delete(id: "b01"))
        XCTAssertNil(store.block(id: "b01"))

        let new = Block(id: "new", label: "Read", kind: .window, start: .hm(21, 0), end: .hm(21, 30))
        store.upsert(new)
        XCTAssertEqual(store.block(id: "new")?.label, "Read")
    }

    func testWithSingleAnchorFlagsEarliestWhenNoneSet() {
        let a = Block(id: "a", label: "A", kind: .fixed, start: .hm(9, 0), end: .hm(9, 5))
        let b = Block(id: "b", label: "B", kind: .fixed, start: .hm(7, 0), end: .hm(7, 5))
        XCTAssertEqual(PlanStore.withSingleAnchor([a, b]).filter(\.isAnchor).map(\.id), ["b"])
    }

    func testStarterPlanWrapsPastMidnightAndHasOneAnchor() {
        let plan = Plan.starter(wake: .hm(22, 0), sleep: .hm(6, 0))
        XCTAssertEqual(plan.filter(\.isAnchor).count, 1)
        XCTAssertEqual(plan.first?.start, .hm(22, 0))
        let dinner = plan.first { $0.label == "Dinner" }!
        XCTAssertEqual(dinner.start, .hm(3, 0))
        XCTAssertEqual(plan.count, 11)
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
    }
}
