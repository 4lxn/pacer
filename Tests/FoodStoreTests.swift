import XCTest
@testable import Autopiloto

@MainActor
final class FoodStoreTests: XCTestCase {
    private var dir: URL!
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var fileURL: URL { dir.appendingPathComponent("food.json") }
    private var legacyURL: URL { dir.appendingPathComponent("completions.json") }
    private func date(_ d: Int, _ h: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))! }

    func testFreshInstallIsEmptyLegacyIsSeeded() throws {
        XCTAssertTrue(FoodStore(fileURL: fileURL, legacyMarker: legacyURL, calendar: calendar).pantry.isEmpty)
        try Data("{}".utf8).write(to: legacyURL)
        let seeded = FoodStore(fileURL: fileURL, legacyMarker: legacyURL, calendar: calendar)
        XCTAssertEqual(seeded.pantry.count, FoodStore.seedPantry.count)
        XCTAssertEqual(seeded.presets.count, FoodStore.seedPresets.count)
    }

    func testMacrosPerDayAndPersistence() {
        let store = FoodStore(fileURL: fileURL, legacyMarker: legacyURL, calendar: calendar)
        store.log(name: "Shake", kcal: 450, proteinGrams: 40, at: date(16, 8), saveAsPreset: true)
        store.log(name: "Beef + rice", kcal: 800, proteinGrams: 60, at: date(16, 14), saveAsPreset: false)
        store.log(name: "Yesterday", kcal: 500, proteinGrams: 30, at: date(15, 20), saveAsPreset: false)
        XCTAssertEqual(store.macros(on: date(16, 22)), DayMacros(kcal: 1250, proteinGrams: 100))
        XCTAssertEqual(store.meals(on: date(16, 22)).map(\.name), ["Shake", "Beef + rice"])
        XCTAssertEqual(store.presets.map(\.name), ["Shake"])

        let again = FoodStore(fileURL: fileURL, legacyMarker: legacyURL, calendar: calendar)
        XCTAssertEqual(again.meals.count, 3)
        XCTAssertEqual(again.presets.count, 1)
        again.log(again.presets[0], at: date(16, 23))
        XCTAssertEqual(again.macros(on: date(16, 23)).proteinGrams, 140)
    }

    func testGroceryListAndAdjust() {
        let store = FoodStore(fileURL: fileURL, legacyMarker: legacyURL, calendar: calendar)
        let rice = PantryItem(name: "Rice", quantity: 800, unit: "g", minQuantity: 700)
        let eggs = PantryItem(name: "Eggs", quantity: 2, unit: "pcs", minQuantity: 6)
        store.upsert(rice); store.upsert(eggs)
        XCTAssertEqual(store.groceryList.map(\.name), ["Eggs"])
        store.adjust(id: rice.id, by: -200)
        XCTAssertEqual(store.groceryList.map(\.name), ["Eggs", "Rice"])
        store.adjust(id: eggs.id, by: -10)
        XCTAssertEqual(store.pantry.first { $0.id == eggs.id }?.quantity, 0)
        XCTAssertTrue(store.groceryText().contains("- Eggs: have 0 pcs, want 6"))
        XCTAssertTrue(store.coachSummary(now: date(16, 12)).contains("Running low: Eggs, Rice"))
    }
}
