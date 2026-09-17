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
        let store = PlanStore(fileURL: planURL)
        XCTAssertTrue(store.needsOnboarding)
        XCTAssertTrue(store.blocks.isEmpty)
    }

    func testCorruptPlanFileIsKeptAsideNotOverwritten() throws {
        try Data("not json".utf8).write(to: planURL)
        let store = PlanStore(fileURL: planURL)
        XCTAssertTrue(store.needsOnboarding)
        XCTAssertFalse(FileManager.default.fileExists(atPath: planURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: planURL.appendingPathExtension("bad").path))
        XCTAssertNotNil(PersistenceState.shared.lastError)
        PersistenceState.shared.clear()
    }

    func testOlderPlanFileWithoutCheckInDecodesWithDefaults() throws {
        let json = #"[{"id":"w","label":"Lunch","kind":"window","start":{"hour":13,"minute":0},"end":{"hour":13,"minute":40},"isAnchor":false}]"#
        try Data(json.utf8).write(to: planURL)
        let store = PlanStore(fileURL: planURL)
        XCTAssertEqual(store.blocks.first?.checkIn, true)   // window ≥ 20 min defaults on
    }

    func testReplacePersistsAndClearsOnboarding() {
        let store = PlanStore(fileURL: planURL)
        store.replace(with: Plan.starter(wake: .hm(7, 0), sleep: .hm(23, 0)))
        XCTAssertFalse(store.needsOnboarding)
        let again = PlanStore(fileURL: planURL)
        XCTAssertEqual(again.blocks, store.blocks)
        XCTAssertEqual(again.blocks.filter(\.isAnchor).count, 1)
    }

    func testUpsertKeepsExactlyOneAnchorAndDeleteRefusesIt() throws {
        let store = PlanStore(fileURL: planURL)
        store.replace(with: Plan.blocks)
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

    func testStarterPlanNeverEmitsBlocksAfterMidnight() {
        let plan = Plan.starter(wake: .hm(7, 30), sleep: .hm(0, 30))
        XCTAssertEqual(plan.filter(\.isAnchor).count, 1)
        XCTAssertEqual(plan.first?.start, .hm(7, 30))
        let sleep = plan.first { $0.label == "Sleep" }!
        XCTAssertEqual(sleep.start, .hm(23, 30))
        XCTAssertEqual(sleep.end, .hm(23, 45))
        for b in plan { if let e = b.end, let s = b.start { XCTAssertGreaterThan((e.hour! * 60 + e.minute!), (s.hour! * 60 + s.minute!), b.label) } }
        XCTAssertEqual(plan.count, 11)
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertTrue(plan.first { $0.label == "Train" }!.checkIn)
        XCTAssertFalse(plan.first { $0.label == "Work" }!.checkIn)
    }
}
