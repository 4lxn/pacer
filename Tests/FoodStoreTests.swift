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

    func testFreshInstallIsEmpty() {
        XCTAssertTrue(FoodStore(fileURL: fileURL, calendar: calendar).pantry.isEmpty)
        XCTAssertFalse(FoodStore.seedPantry.isEmpty)
    }

    func testMacrosPerDayAndPersistence() {
        let store = FoodStore(fileURL: fileURL, calendar: calendar)
        store.log(name: "Shake", kcal: 450, proteinGrams: 40, at: date(16, 8), saveAsPreset: true)
        store.log(name: "Beef + rice", kcal: 800, proteinGrams: 60, at: date(16, 14), saveAsPreset: false)
        store.log(name: "Yesterday", kcal: 500, proteinGrams: 30, at: date(15, 20), saveAsPreset: false)
        XCTAssertEqual(store.macros(on: date(16, 22)), DayMacros(kcal: 1250, proteinGrams: 100))
        XCTAssertEqual(store.meals(on: date(16, 22)).map(\.name), ["Shake", "Beef + rice"])
        XCTAssertEqual(store.presets.map(\.name), ["Shake"])

        let again = FoodStore(fileURL: fileURL, calendar: calendar)
        XCTAssertEqual(again.meals.count, 3)
        XCTAssertEqual(again.presets.count, 1)
        again.log(again.presets[0], at: date(16, 23))
        XCTAssertEqual(again.macros(on: date(16, 23)).proteinGrams, 140)
    }

    func testGroceryListAndAdjust() {
        let store = FoodStore(fileURL: fileURL, calendar: calendar)
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

@MainActor
final class FoodDepthTests: XCTestCase {
    func testRecipesCookRestockAndLegacyDecode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("food.json")
        // A pre-macros file: no carbs/fat, no recipes.
        try Data(#"{"pantry":[{"id":"r","name":"Rice","quantity":500,"unit":"g","minQuantity":700}],"meals":[],"presets":[{"id":"p","name":"Shake","kcal":450,"proteinGrams":40}],"targets":{"kcal":2300,"proteinGrams":160}}"#.utf8).write(to: url)
        let food = FoodStore(fileURL: url)
        XCTAssertEqual(food.presets.first?.carbsGrams, 0)
        XCTAssertEqual(food.targets.fatGrams, 0)
        XCTAssertTrue(food.recipes.isEmpty)

        food.upsert(PantryItem(name: "Chicken breast", quantity: 800, unit: "g", minQuantity: 600))
        let bowl = Recipe(name: "Chicken bowl", ingredients: [.init(name: "chicken breast", amount: 200, unit: "g"), .init(name: "rice", amount: 70, unit: "g")], kcal: 520, proteinGrams: 50, carbsGrams: 55, fatGrams: 9)
        food.upsertRecipe(bowl)
        XCTAssertTrue(food.canCook(bowl))
        XCTAssertTrue(food.cook(bowl))
        XCTAssertEqual(food.item(named: "Rice")?.quantity, 430)
        XCTAssertEqual(food.item(named: "chicken BREAST")?.quantity, 600)
        XCTAssertEqual(food.macros(on: .now).carbsGrams, 55)

        let big = Recipe(name: "Big", ingredients: [.init(name: "rice", amount: 5000, unit: "g"), .init(name: "salmon", amount: 1, unit: "pcs")], kcal: 1, proteinGrams: 1)
        XCTAssertEqual(food.missing(for: big).map(\.name), ["rice", "salmon"])
        XCTAssertFalse(food.cook(big))
        XCTAssertTrue(food.cook(big, force: true))
        XCTAssertEqual(food.item(named: "Rice")?.quantity, 0)

        // Groceries: rice is low; "bought" restocks to 2× min.
        XCTAssertTrue(food.groceryList.contains { $0.name == "Rice" })
        food.restock(id: "r")
        XCTAssertEqual(food.item(named: "Rice")?.quantity, 1400)
        XCTAssertFalse(food.groceryList.contains { $0.name == "Rice" })

        XCTAssertEqual(food.kcalByDay(days: 7, now: .now).count, 7)
        XCTAssertEqual(food.kcalByDay(days: 7, now: .now).last?.kcal, 521)

        // Round trip keeps recipes and macros.
        let again = FoodStore(fileURL: url)
        XCTAssertEqual(again.recipes.count, 1)
        XCTAssertEqual(again.meals.last?.carbsGrams, 0)
    }

    func testMealGuessParsesInsideProse() {
        let g = MealGuess.parse("Sure! {\"name\":\"Eggs on toast\",\"kcal\":420,\"proteinGrams\":22,\"carbsGrams\":30,\"fatGrams\":24,\"note\":\"2 eggs, 1 slice, butter\"} hope that helps")
        XCTAssertEqual(g?.name, "Eggs on toast")
        XCTAssertEqual(g?.kcal, 420)
        XCTAssertEqual(g?.fatGrams, 24)
        XCTAssertNil(MealGuess.parse("no json here"))
        XCTAssertEqual(MealGuess.parse("{\"name\":\"\",\"kcal\":-5,\"proteinGrams\":1}")?.name, "Meal")
    }
}

@MainActor
final class WaterTests: XCTestCase {
    func testWaterAndAverages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let food = FoodStore(fileURL: url)
        food.logWater(3); food.logWater(-1); food.logWater(-5)
        XCTAssertEqual(food.water(on: .now), 0)
        food.logWater(4)
        XCTAssertEqual(FoodStore(fileURL: url).water(on: .now), 4)
        food.log(name: "A", kcal: 500, proteinGrams: 40, saveAsPreset: false)
        food.log(name: "B", kcal: 700, proteinGrams: 50, at: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, saveAsPreset: false)
        let avg = food.averages(days: 7, now: .now)
        XCTAssertEqual(avg.loggedDays, 2); XCTAssertEqual(avg.kcal, 600); XCTAssertEqual(avg.protein, 45)
    }
}
