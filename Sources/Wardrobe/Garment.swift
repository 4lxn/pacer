import Foundation

enum GarmentCategory: String, Codable, CaseIterable, Sendable {
    case top, bottom, shoes, outer, accessory

    /// Wears before it goes to the laundry pile (accessories and shoes never do).
    var defaultWashAfter: Int {
        switch self {
        case .top: 1
        case .bottom: 3
        case .outer: 8
        case .shoes, .accessory: 0
        }
    }
}

enum Formality: String, Codable, CaseIterable, Sendable {
    case sport, casual, smart
}

struct Garment: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var category: GarmentCategory
    var color: String
    var warmth: Int              // 1 light · 2 mid · 3 warm
    var formality: Formality
    var washAfter: Int           // 0 = never needs washing tracking
    var wearsSinceWash = 0
    var lastWorn: Date?
    var imageFile: String?

    var needsWash: Bool { washAfter > 0 && wearsSinceWash >= washAfter }
}

/// What the vision call returns for a photo. Parsed from JSON in the model's text reply.
struct GarmentGuess: Codable, Equatable, Sendable {
    var name: String
    var category: GarmentCategory
    var color: String
    var warmth: Int
    var formality: Formality

    static func parse(_ text: String) -> GarmentGuess? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let json = String(text[start...end])
        guard var guess = try? JSONDecoder().decode(GarmentGuess.self, from: Data(json.utf8)) else { return nil }
        guess.warmth = min(3, max(1, guess.warmth))
        return guess
    }

    static let prompt = """
    Look at the garment in this photo. Reply with JSON only, no prose, exactly these keys:
    {"name": short name like "navy hoodie", "category": one of top|bottom|shoes|outer|accessory, \
    "color": one or two words, "warmth": 1 (light) | 2 (mid) | 3 (warm), "formality": sport|casual|smart}
    """
}

enum Weather: String, Codable, CaseIterable, Sendable {
    case cold, mild, hot

    var wantedWarmth: ClosedRange<Int> {
        switch self {
        case .cold: 2...3
        case .mild: 1...3
        case .hot: 1...1
        }
    }
}

enum OutfitPicker {
    /// One top, one bottom, shoes, plus an outer layer when cold. Clean first, then least recently
    /// worn, then warmth fit. Empty categories are skipped.
    static func pick(from closet: [Garment], weather: Weather, formality: Formality, now: Date) -> [Garment] {
        func best(_ category: GarmentCategory) -> Garment? {
            closet.filter { $0.category == category }.min { a, b in
                score(a, weather: weather, formality: formality, now: now) > score(b, weather: weather, formality: formality, now: now)
            }
        }
        var outfit = [best(.top), best(.bottom), best(.shoes)].compactMap { $0 }
        if weather == .cold, let outer = best(.outer) { outfit.append(outer) }
        return outfit
    }

    static func score(_ g: Garment, weather: Weather, formality: Formality, now: Date) -> Double {
        var s = 0.0
        if g.needsWash { s -= 100 }
        if weather.wantedWarmth.contains(g.warmth) { s += 20 } else { s -= 10 * Double(abs(g.warmth - weather.wantedWarmth.lowerBound)) }
        if g.formality == formality { s += 10 } else if g.formality == .casual || formality == .casual { s += 3 }
        if let last = g.lastWorn {
            s += min(14, now.timeIntervalSince(last) / 86_400)   // up to 14 points for two weeks unworn
        } else {
            s += 14
        }
        return s
    }
}
