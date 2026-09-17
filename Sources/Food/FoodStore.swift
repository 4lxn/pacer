import Foundation
import Observation

struct PantryItem: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var quantity: Double
    var unit: String          // "g", "pcs", "L", "scoops"…
    var minQuantity: Double   // below this it goes on the grocery list

    var isLow: Bool { quantity < minQuantity }
}

struct MealEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var date: Date
    var name: String
    var kcal: Int
    var proteinGrams: Int
    var carbsGrams: Int = 0
    var fatGrams: Int = 0

    init(id: String = UUID().uuidString, date: Date, name: String, kcal: Int, proteinGrams: Int, carbsGrams: Int = 0, fatGrams: Int = 0) {
        self.id = id; self.date = date; self.name = name; self.kcal = kcal; self.proteinGrams = proteinGrams; self.carbsGrams = carbsGrams; self.fatGrams = fatGrams
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); date = try c.decode(Date.self, forKey: .date); name = try c.decode(String.self, forKey: .name)
        kcal = try c.decode(Int.self, forKey: .kcal); proteinGrams = try c.decode(Int.self, forKey: .proteinGrams)
        carbsGrams = try c.decodeIfPresent(Int.self, forKey: .carbsGrams) ?? 0; fatGrams = try c.decodeIfPresent(Int.self, forKey: .fatGrams) ?? 0
    }
}

/// A saved meal for one-tap logging.
struct MealPreset: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var kcal: Int
    var proteinGrams: Int
    var carbsGrams: Int = 0
    var fatGrams: Int = 0

    init(id: String = UUID().uuidString, name: String, kcal: Int, proteinGrams: Int, carbsGrams: Int = 0, fatGrams: Int = 0) {
        self.id = id; self.name = name; self.kcal = kcal; self.proteinGrams = proteinGrams; self.carbsGrams = carbsGrams; self.fatGrams = fatGrams
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        kcal = try c.decode(Int.self, forKey: .kcal); proteinGrams = try c.decode(Int.self, forKey: .proteinGrams)
        carbsGrams = try c.decodeIfPresent(Int.self, forKey: .carbsGrams) ?? 0; fatGrams = try c.decodeIfPresent(Int.self, forKey: .fatGrams) ?? 0
    }
}

struct MacroTargets: Codable, Hashable, Sendable {
    var kcal: Int
    var proteinGrams: Int
    var carbsGrams: Int = 0   // 0 = not tracked
    var fatGrams: Int = 0

    init(kcal: Int, proteinGrams: Int, carbsGrams: Int = 0, fatGrams: Int = 0) {
        self.kcal = kcal; self.proteinGrams = proteinGrams; self.carbsGrams = carbsGrams; self.fatGrams = fatGrams
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kcal = try c.decode(Int.self, forKey: .kcal); proteinGrams = try c.decode(Int.self, forKey: .proteinGrams)
        carbsGrams = try c.decodeIfPresent(Int.self, forKey: .carbsGrams) ?? 0; fatGrams = try c.decodeIfPresent(Int.self, forKey: .fatGrams) ?? 0
    }
}

struct DayMacros: Equatable {
    var kcal = 0
    var proteinGrams = 0
    var carbsGrams = 0
    var fatGrams = 0
}

/// Something you cook from the pantry. Cooking deducts the ingredients and logs the meal.
struct Recipe: Codable, Identifiable, Hashable, Sendable {
    struct Ingredient: Codable, Hashable, Sendable {
        var name: String      // matched to a pantry item by name, case-insensitive
        var amount: Double
        var unit: String
    }
    var id: String = UUID().uuidString
    var name: String
    var ingredients: [Ingredient]
    var kcal: Int
    var proteinGrams: Int
    var carbsGrams: Int = 0
    var fatGrams: Int = 0
    var note: String = ""
}

@Observable
@MainActor
final class FoodStore {
    private struct Snapshot: Codable {
        var pantry: [PantryItem]
        var meals: [MealEntry]
        var presets: [MealPreset]
        var targets: MacroTargets
        var recipes: [Recipe]?
        var water: [String: Int]?
        var waterTarget: Int?
    }

    private(set) var pantry: [PantryItem] = []
    private(set) var meals: [MealEntry] = []
    private(set) var presets: [MealPreset] = []
    private(set) var recipes: [Recipe] = []
    /// Glasses per dayKey.
    private(set) var water: [String: Int] = [:]
    var waterTarget = 8 { didSet { save() } }
    var targets = MacroTargets(kcal: 2300, proteinGrams: 160) { didSet { save() } }

    private let fileURL: URL
    private let calendar: Calendar

    static var defaultURL: URL {
        AppFiles.url("food.json")
    }

    init(fileURL: URL = FoodStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if case .loaded(let s) = JSONFile.load(Snapshot.self, from: fileURL) {
            pantry = s.pantry; meals = s.meals; presets = s.presets; targets = s.targets; recipes = s.recipes ?? []
            water = s.water ?? [:]; waterTarget = s.waterTarget ?? 8
        }
    }

    // MARK: - Meals

    func meals(on date: Date) -> [MealEntry] {
        meals.filter { calendar.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }

    func macros(on date: Date) -> DayMacros {
        meals(on: date).reduce(into: DayMacros()) {
            $0.kcal += $1.kcal; $0.proteinGrams += $1.proteinGrams; $0.carbsGrams += $1.carbsGrams; $0.fatGrams += $1.fatGrams
        }
    }

    /// kcal per day for the last `days` days, oldest first (today last).
    func kcalByDay(days: Int, now: Date) -> [(date: Date, kcal: Int, protein: Int)] {
        (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let m = macros(on: day)
            return (calendar.startOfDay(for: day), m.kcal, m.proteinGrams)
        }
    }

    func log(_ preset: MealPreset, at date: Date = .now) {
        meals.append(MealEntry(date: date, name: preset.name, kcal: preset.kcal, proteinGrams: preset.proteinGrams, carbsGrams: preset.carbsGrams, fatGrams: preset.fatGrams))
        save()
    }

    func log(name: String, kcal: Int, proteinGrams: Int, carbsGrams: Int = 0, fatGrams: Int = 0, at date: Date = .now, saveAsPreset: Bool) {
        meals.append(MealEntry(date: date, name: name, kcal: kcal, proteinGrams: proteinGrams, carbsGrams: carbsGrams, fatGrams: fatGrams))
        if saveAsPreset, !presets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            presets.append(MealPreset(name: name, kcal: kcal, proteinGrams: proteinGrams, carbsGrams: carbsGrams, fatGrams: fatGrams))
        }
        save()
    }

    // MARK: - Water

    func water(on date: Date) -> Int { water[DayLogic.dayKey(date, calendar: calendar)] ?? 0 }

    func logWater(_ glasses: Int, on date: Date = .now) {
        let key = DayLogic.dayKey(date, calendar: calendar)
        water[key] = max(0, (water[key] ?? 0) + glasses)
        if water.count > 90 { for k in water.keys.sorted().prefix(water.count - 90) { water.removeValue(forKey: k) } }
        save()
    }

    /// Averages over the last `days` days that have anything logged.
    func averages(days: Int, now: Date) -> (kcal: Int, protein: Int, loggedDays: Int) {
        let rows = kcalByDay(days: days, now: now).filter { $0.kcal > 0 }
        guard !rows.isEmpty else { return (0, 0, 0) }
        return (rows.map(\.kcal).reduce(0, +) / rows.count, rows.map(\.protein).reduce(0, +) / rows.count, rows.count)
    }

    // MARK: - Recipes

    func item(named name: String) -> PantryItem? {
        pantry.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Ingredients the pantry can't cover right now.
    func missing(for recipe: Recipe) -> [Recipe.Ingredient] {
        recipe.ingredients.filter { ing in
            guard let item = item(named: ing.name) else { return true }
            return item.quantity < ing.amount
        }
    }

    func canCook(_ recipe: Recipe) -> Bool { missing(for: recipe).isEmpty }

    func upsertRecipe(_ recipe: Recipe) {
        if let i = recipes.firstIndex(where: { $0.id == recipe.id || $0.name.caseInsensitiveCompare(recipe.name) == .orderedSame }) {
            var r = recipe; r.id = recipes[i].id; recipes[i] = r
        } else {
            recipes.append(recipe)
        }
        save()
    }

    func deleteRecipe(id: String) {
        recipes.removeAll { $0.id == id }
        save()
    }

    /// Deducts the ingredients (never below zero) and logs the meal. Returns false if something is missing.
    @discardableResult
    func cook(_ recipe: Recipe, at date: Date = .now, force: Bool = false) -> Bool {
        guard force || canCook(recipe) else { return false }
        for ing in recipe.ingredients {
            if let i = pantry.firstIndex(where: { $0.name.caseInsensitiveCompare(ing.name) == .orderedSame }) {
                pantry[i].quantity = max(0, pantry[i].quantity - ing.amount)
            }
        }
        meals.append(MealEntry(date: date, name: recipe.name, kcal: recipe.kcal, proteinGrams: recipe.proteinGrams, carbsGrams: recipe.carbsGrams, fatGrams: recipe.fatGrams))
        save()
        return true
    }

    func deleteMeal(id: String) {
        meals.removeAll { $0.id == id }
        save()
    }

    func addPreset(name: String, kcal: Int, proteinGrams: Int) {
        if let i = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            presets[i].kcal = kcal; presets[i].proteinGrams = proteinGrams
        } else {
            presets.append(MealPreset(name: name, kcal: kcal, proteinGrams: proteinGrams))
        }
        save()
    }

    func deletePreset(id: String) {
        presets.removeAll { $0.id == id }
        save()
    }

    // MARK: - Pantry

    var groceryList: [PantryItem] { pantry.filter(\.isLow).sorted { $0.name < $1.name } }

    func upsert(_ item: PantryItem) {
        if let i = pantry.firstIndex(where: { $0.id == item.id }) { pantry[i] = item } else { pantry.append(item) }
        save()
    }

    func adjust(id: String, by delta: Double) {
        guard let i = pantry.firstIndex(where: { $0.id == id }) else { return }
        pantry[i].quantity = max(0, pantry[i].quantity + delta)
        save()
    }

    func deleteItem(id: String) {
        pantry.removeAll { $0.id == id }
        save()
    }

    /// Bought it: back to twice the minimum (or the minimum + what's there, whichever is more).
    func restock(id: String) {
        guard let i = pantry.firstIndex(where: { $0.id == id }) else { return }
        pantry[i].quantity = max(pantry[i].minQuantity * 2, pantry[i].quantity + pantry[i].minQuantity)
        save()
    }

    /// Text for the Coach snapshot and the share sheet.
    func groceryText() -> String {
        groceryList.map { "- \($0.name): have \(Self.format($0.quantity)) \($0.unit), want \(Self.format($0.minQuantity))" }.joined(separator: "\n")
    }

    /// Section for the Coach snapshot: macros so far, quick-log presets, what's running low.
    func coachSummary(now: Date) -> String {
        let m = macros(on: now)
        var lines = ["## Food today: \(m.kcal) / \(targets.kcal) kcal, \(m.proteinGrams) / \(targets.proteinGrams) g protein, water \(water(on: now)) / \(waterTarget) glasses"]
        let avg = averages(days: 7, now: now)
        if avg.loggedDays > 1 { lines.append("7-day average: \(avg.kcal) kcal, \(avg.protein) g protein over \(avg.loggedDays) logged days") }
        let logged = meals(on: now)
        if !logged.isEmpty {
            lines.append("Logged: " + logged.map { "\($0.name) (\($0.kcal) kcal, \($0.proteinGrams) g)" }.joined(separator: "; "))
        }
        if !pantry.isEmpty {
            lines.append("Pantry: " + pantry.map { "\($0.name) \(Self.format($0.quantity)) \($0.unit)" }.joined(separator: ", "))
        }
        if !groceryList.isEmpty {
            lines.append("Running low: " + groceryList.map(\.name).joined(separator: ", "))
        }
        if !recipes.isEmpty {
            lines.append("Recipes: " + recipes.map { "\($0.name)\(canCook($0) ? "" : " (missing \(missing(for: $0).map(\.name).joined(separator: ", ")))")" }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Persistence

    private func save() {
        JSONFile.save(Snapshot(pantry: pantry, meals: meals, presets: presets, targets: targets, recipes: recipes, water: water, waterTarget: waterTarget), to: fileURL)
    }

    // MARK: - Sample data (tests and previews)

    static let seedPantry: [PantryItem] = [
        PantryItem(name: "Ground beef 95/5", quantity: 1000, unit: "g", minQuantity: 750),
        PantryItem(name: "Chicken breast", quantity: 800, unit: "g", minQuantity: 600),
        PantryItem(name: "Tuna cans", quantity: 4, unit: "pcs", minQuantity: 3),
        PantryItem(name: "Rice", quantity: 2000, unit: "g", minQuantity: 700),
        PantryItem(name: "Corn (elote)", quantity: 4, unit: "pcs", minQuantity: 3),
        PantryItem(name: "Prunes", quantity: 300, unit: "g", minQuantity: 150),
        PantryItem(name: "Whey isolate", quantity: 20, unit: "scoops", minQuantity: 7),
        PantryItem(name: "Protein milk", quantity: 3, unit: "L", minQuantity: 1.5),
        PantryItem(name: "Jicama", quantity: 1, unit: "pcs", minQuantity: 1),
        PantryItem(name: "Cucumber", quantity: 2, unit: "pcs", minQuantity: 2),
        PantryItem(name: "Broccoli", quantity: 1, unit: "pcs", minQuantity: 1),
        PantryItem(name: "Avocado", quantity: 2, unit: "pcs", minQuantity: 1),
        PantryItem(name: "Greek yogurt", quantity: 3, unit: "pcs", minQuantity: 2),
        PantryItem(name: "Mineral water", quantity: 6, unit: "L", minQuantity: 3),
    ]

    static let seedPresets: [MealPreset] = [
        MealPreset(name: "Breakfast shake + 3 prunes", kcal: 450, proteinGrams: 40),
        MealPreset(name: "Beef 250 g + rice 70 g + veg + ½ avocado", kcal: 800, proteinGrams: 60),
        MealPreset(name: "Chicken 200 g + corn + broccoli", kcal: 450, proteinGrams: 48),
        MealPreset(name: "Tuna 200 g + corn + broccoli", kcal: 420, proteinGrams: 46),
        MealPreset(name: "Transition shake", kcal: 200, proteinGrams: 25),
        MealPreset(name: "Greek yogurt", kcal: 200, proteinGrams: 15),
        MealPreset(name: "Rice extra 30 g", kcal: 110, proteinGrams: 2),
    ]
}
