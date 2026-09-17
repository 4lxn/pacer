import Foundation

/// What the model returns for "what did I eat" (text or photo). Parsed from JSON in its reply.
struct MealGuess: Codable, Equatable, Sendable {
    var name: String
    var kcal: Int
    var proteinGrams: Int
    var carbsGrams: Int?
    var fatGrams: Int?
    var note: String?

    static let prompt = """
    Estimate the nutrition of this meal as eaten. Reply with JSON only, no prose:
    {"name": "short meal name", "kcal": 0, "proteinGrams": 0, "carbsGrams": 0, "fatGrams": 0, "note": "one line on what you assumed (portions, oil)"}
    Use typical portions when unsure and say so in note. Integers only.
    """

    static func parse(_ text: String) -> MealGuess? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        guard var g = try? JSONDecoder().decode(MealGuess.self, from: Data(String(text[start...end]).utf8)) else { return nil }
        g.kcal = max(0, g.kcal); g.proteinGrams = max(0, g.proteinGrams)
        if g.name.trimmingCharacters(in: .whitespaces).isEmpty { g.name = "Meal" }
        return g
    }
}
