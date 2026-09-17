import Foundation

/// Where a block happens. Travel times live between pairs of places, symmetric.
struct Place: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var note: String = ""   // address or how to get there

    static let homeID = "home"
    static let home = Place(id: homeID, name: "Home")
}

struct Places: Codable, Equatable, Sendable {
    var list: [Place] = [.home]
    /// Minutes between two places, keyed by the sorted pair "a|b".
    var travel: [String: Int] = [:]

    static func key(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    func place(id: String?) -> Place? { id.flatMap { id in list.first { $0.id == id } } }
    func name(id: String?) -> String? { place(id: id)?.name }

    /// Minutes to get from `a` to `b`. Same place, nil, or unknown pair → 0. A block without a
    /// place counts as wherever you already are.
    func minutes(from a: String?, to b: String?) -> Int {
        guard let a, let b, a != b else { return 0 }
        return travel[Self.key(a, b)] ?? 0
    }

    mutating func setTravel(_ a: String, _ b: String, minutes: Int) {
        guard a != b else { return }
        if minutes <= 0 { travel.removeValue(forKey: Self.key(a, b)) } else { travel[Self.key(a, b)] = minutes }
    }

    mutating func upsert(_ place: Place) {
        if let i = list.firstIndex(where: { $0.id == place.id || $0.name.caseInsensitiveCompare(place.name) == .orderedSame }) {
            var p = place; p.id = list[i].id; list[i] = p
        } else {
            list.append(place)
        }
    }

    mutating func remove(id: String) {
        guard id != Place.homeID else { return }
        list.removeAll { $0.id == id }
        travel = travel.filter { !$0.key.split(separator: "|").map(String.init).contains(id) }
    }
}

extension Places {
    /// Section for the Coach snapshot.
    func coachSummary() -> String {
        guard list.count > 1 || !travel.isEmpty else { return "## Places: only Home; no travel times set (add_place / set_travel)." }
        var lines = ["## Places: " + list.map(\.name).joined(separator: ", ")]
        let pairs = list.enumerated().flatMap { i, a in list[(i + 1)...].compactMap { b -> String? in
            let m = minutes(from: a.id, to: b.id); return m > 0 ? "\(a.name)↔\(b.name) \(m) min" : nil } }
        lines.append(pairs.isEmpty ? "No travel times set." : "Travel: " + pairs.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }
}

extension DayLogic {
    /// For consecutive timed blocks, the travel needed before each one: (block id → minutes,
    /// from place name). Zero-minute legs are omitted.
    static func travelLegs(_ blocks: [Block], places: Places) -> [String: (minutes: Int, from: String)] {
        var legs: [String: (Int, String)] = [:]
        var lastPlace: String? = Place.homeID
        for b in sorted(blocks) where b.start != nil {
            let here = b.place ?? lastPlace
            let minutes = places.minutes(from: lastPlace, to: here)
            if minutes > 0 { legs[b.id] = (minutes, places.name(id: lastPlace) ?? "") }
            lastPlace = here
        }
        return legs
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
