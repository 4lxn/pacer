import Foundation

/// Where a block happens. Travel times live between pairs of places, symmetric.
struct Place: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var note: String = ""   // address or how to get there
    /// Pinned on the map (Apple Maps search or current location); nil = travel typed by hand.
    var latitude: Double? = nil
    var longitude: Double? = nil

    var isPinned: Bool { latitude != nil && longitude != nil }

    static let homeID = "home"
    static let home = Place(id: homeID, name: "Home")

    private enum CodingKeys: String, CodingKey { case id, name, note, latitude, longitude }
    init(id: String = UUID().uuidString, name: String, note: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id; self.name = name; self.note = note; self.latitude = latitude; self.longitude = longitude
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude); longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
    }
}

struct Places: Codable, Equatable, Sendable {
    var list: [Place] = [.home]
    /// Minutes between two places, keyed by the sorted pair "a|b".
    var travel: [String: Int] = [:]
    /// Pairs whose minutes came from Apple Maps (the rest were typed).
    var estimated: Set<String> = []
    /// How you usually get around: driving, walking, transit.
    var mode: String = "driving"

    private enum CodingKeys: String, CodingKey { case list, travel, estimated, mode }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = try c.decodeIfPresent([Place].self, forKey: .list) ?? [.home]
        travel = try c.decodeIfPresent([String: Int].self, forKey: .travel) ?? [:]
        estimated = try c.decodeIfPresent(Set<String>.self, forKey: .estimated) ?? []
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "driving"
    }

    static func key(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    func place(id: String?) -> Place? { id.flatMap { id in list.first { $0.id == id } } }
    func name(id: String?) -> String? { place(id: id)?.name }

    /// Minutes to get from `a` to `b`. Same place, nil, or unknown pair → 0. A block without a
    /// place counts as wherever you already are.
    func minutes(from a: String?, to b: String?) -> Int {
        guard let a, let b, a != b else { return 0 }
        return travel[Self.key(a, b)] ?? 0
    }

    mutating func setTravel(_ a: String, _ b: String, minutes: Int, estimated isEstimate: Bool = false) {
        guard a != b else { return }
        let k = Self.key(a, b)
        if minutes <= 0 { travel.removeValue(forKey: k); estimated.remove(k) } else { travel[k] = minutes }
        if isEstimate { estimated.insert(k) } else { estimated.remove(k) }
    }

    /// Pairs where both ends are pinned and nothing was typed by hand — what Maps can fill in.
    var estimablePairs: [(Place, Place)] {
        var out: [(Place, Place)] = []
        for (i, a) in list.enumerated() where a.isPinned {
            for b in list[(i + 1)...] where b.isPinned {
                let k = Self.key(a.id, b.id)
                if travel[k] == nil || estimated.contains(k) { out.append((a, b)) }
            }
        }
        return out
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
        estimated = estimated.filter { !$0.split(separator: "|").map(String.init).contains(id) }
    }
}

extension Places {
    /// Section for the Coach snapshot.
    func coachSummary() -> String {
        guard list.count > 1 || !travel.isEmpty else { return "## Places: only Home; no travel times set (add_place / set_travel)." }
        var lines = ["## Places (\(mode)): " + list.map { $0.name + ($0.isPinned ? " (pinned)" : "") }.joined(separator: ", ")]
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
