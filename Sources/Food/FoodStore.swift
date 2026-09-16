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
}

/// A saved meal for one-tap logging.
struct MealPreset: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var kcal: Int
    var proteinGrams: Int
}

struct MacroTargets: Codable, Hashable, Sendable {
    var kcal: Int
    var proteinGrams: Int
}

struct DayMacros: Equatable {
    var kcal = 0
    var proteinGrams = 0
}

@Observable
@MainActor
final class FoodStore {
    private struct Snapshot: Codable {
        var pantry: [PantryItem]
        var meals: [MealEntry]
        var presets: [MealPreset]
        var targets: MacroTargets
    }

    private(set) var pantry: [PantryItem] = []
    private(set) var meals: [MealEntry] = []
    private(set) var presets: [MealPreset] = []
    var targets = MacroTargets(kcal: 2300, proteinGrams: 160) { didSet { save() } }

    private let fileURL: URL
    private let calendar: Calendar

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("food.json")
    }

    init(fileURL: URL = FoodStore.defaultURL, legacyMarker: URL = CompletionStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if let data = try? Data(contentsOf: fileURL),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            pantry = s.pantry; meals = s.meals; presets = s.presets; targets = s.targets
        } else if FileManager.default.fileExists(atPath: legacyMarker.path) {
            // Pre-editor install: seed the original user's staples and template meals.
            pantry = Self.seedPantry
            presets = Self.seedPresets
            save()
        }
    }

    // MARK: - Meals

    func meals(on date: Date) -> [MealEntry] {
        meals.filter { calendar.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }

    func macros(on date: Date) -> DayMacros {
        meals(on: date).reduce(into: DayMacros()) { $0.kcal += $1.kcal; $0.proteinGrams += $1.proteinGrams }
    }

    func log(_ preset: MealPreset, at date: Date = .now) {
        meals.append(MealEntry(date: date, name: preset.name, kcal: preset.kcal, proteinGrams: preset.proteinGrams))
        save()
    }

    func log(name: String, kcal: Int, proteinGrams: Int, at date: Date = .now, saveAsPreset: Bool) {
        meals.append(MealEntry(date: date, name: name, kcal: kcal, proteinGrams: proteinGrams))
        if saveAsPreset, !presets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            presets.append(MealPreset(name: name, kcal: kcal, proteinGrams: proteinGrams))
        }
        save()
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

    /// Text for the Coach snapshot and the share sheet.
    func groceryText() -> String {
        groceryList.map { "- \($0.name): have \(Self.format($0.quantity)) \($0.unit), want \(Self.format($0.minQuantity))" }.joined(separator: "\n")
    }

    /// Section for the Coach snapshot: macros so far, quick-log presets, what's running low.
    func coachSummary(now: Date) -> String {
        let m = macros(on: now)
        var lines = ["## Food today: \(m.kcal) / \(targets.kcal) kcal, \(m.proteinGrams) / \(targets.proteinGrams) g protein"]
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
        return lines.joined(separator: "\n")
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Persistence

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let s = Snapshot(pantry: pantry, meals: meals, presets: presets, targets: targets)
            try JSONEncoder().encode(s).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("FoodStore save failed: \(error)")
        }
    }

    // MARK: - Seeds (original user's staples)

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
