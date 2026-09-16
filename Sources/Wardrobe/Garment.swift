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
    var pattern: String = "solid"   // solid, striped, graphic, plaid…
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
    var pattern: String? = "solid"
    var washAfter: Int?

    private struct Wrapper: Decodable { let garments: [GarmentGuess] }

    /// Single garment (legacy shape) — first of `parseMany`.
    static func parse(_ text: String) -> GarmentGuess? { parseMany(text).first }

    /// Accepts `{"garments":[…]}`, a bare array, or a single object, anywhere inside prose.
    static func parseMany(_ text: String) -> [GarmentGuess] {
        let decoder = JSONDecoder()
        func clamp(_ g: GarmentGuess) -> GarmentGuess {
            var c = g
            c.warmth = min(3, max(1, c.warmth))
            if c.pattern?.isEmpty ?? true { c.pattern = "solid" }
            if let w = c.washAfter, w < 0 { c.washAfter = nil }
            return c
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            let json = Data(String(text[start...end]).utf8)
            if let w = try? decoder.decode(Wrapper.self, from: json) { return w.garments.map(clamp) }
            if let one = try? decoder.decode(GarmentGuess.self, from: json) { return [clamp(one)] }
        }
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"),
           let many = try? decoder.decode([GarmentGuess].self, from: Data(String(text[start...end]).utf8)) {
            return many.map(clamp)
        }
        return []
    }

    static let prompt = """
    List every garment visible in this photo (a flat lay or a rack can hold several). Reply with JSON only, no prose:
    {"garments":[{"name": short name like "navy hoodie", "category": top|bottom|shoes|outer|accessory, \
    "color": one or two words, "pattern": solid|striped|graphic|plaid|floral|other, \
    "warmth": 1 (light) | 2 (mid) | 3 (warm), "formality": sport|casual|smart, \
    "washAfter": wears before washing, e.g. 1 for tees, 3 for jeans, 8 for jackets, 0 for shoes}]}
    """

    func garment() -> Garment {
        Garment(name: name, category: category, color: color, warmth: warmth, formality: formality,
                pattern: pattern ?? "solid", washAfter: washAfter ?? category.defaultWashAfter)
    }
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
    static let neutrals: Set<String> = ["black", "white", "grey", "gray", "navy", "beige", "denim", "khaki", "cream", "charcoal", "off-white", "tan", "brown", "olive"]

    /// "light grey", "navy blue", "dark denim" are neutral; "blue", "red", "mustard" are accents.
    static func isNeutral(_ color: String) -> Bool {
        color.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" }).contains { neutrals.contains(String($0)) }
    }

    /// One top, one bottom, shoes, plus an outer layer when cold. Picks category by category in
    /// order top → bottom → outer → shoes; each pick is scored on cleanliness, warmth fit, style,
    /// time since last worn, "not the same as yesterday", and a colour rule: at most one
    /// non-neutral colour per outfit.
    static func pick(from closet: [Garment], weather: Weather, formality: Formality, now: Date, yesterday: [Garment] = []) -> [Garment] {
        var outfit: [Garment] = []
        var accentUsed = false
        let order: [GarmentCategory] = weather == .cold ? [.top, .bottom, .outer, .shoes] : [.top, .bottom, .shoes]
        for category in order {
            let candidates = closet.filter { $0.category == category }
            guard let best = candidates.max(by: { a, b in
                score(a, weather: weather, formality: formality, now: now, yesterday: yesterday, accentUsed: accentUsed)
                    < score(b, weather: weather, formality: formality, now: now, yesterday: yesterday, accentUsed: accentUsed)
            }) else { continue }
            outfit.append(best)
            if !isNeutral(best.color) { accentUsed = true }
        }
        return outfit
    }

    static func score(_ g: Garment, weather: Weather, formality: Formality, now: Date, yesterday: [Garment] = [], accentUsed: Bool = false) -> Double {
        var s = 0.0
        if g.needsWash { s -= 100 }
        if weather.wantedWarmth.contains(g.warmth) { s += 20 } else { s -= 10 * Double(abs(g.warmth - weather.wantedWarmth.lowerBound)) }
        if g.formality == formality { s += 10 } else if g.formality == .casual || formality == .casual { s += 3 }
        if let last = g.lastWorn {
            s += min(14, now.timeIntervalSince(last) / 86_400)   // up to 14 points for two weeks unworn
        } else {
            s += 14
        }
        if g.wearsSinceWash == 0 && g.washAfter > 0 { s += 2 }       // just washed
        if yesterday.contains(where: { $0.id == g.id }) { s -= 8 }   // not the same as yesterday
        if accentUsed && !isNeutral(g.color) { s -= 12 }              // one accent colour per outfit
        return s
    }
}
