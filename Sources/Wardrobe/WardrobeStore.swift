import Foundation
import Observation

struct OutfitLog: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var date: Date
    var garmentIDs: [String]
}

@Observable
@MainActor
final class WardrobeStore {
    private struct Snapshot: Codable {
        var closet: [Garment]
        var outfits: [OutfitLog]
        var weather: Weather
        var formality: Formality
    }

    private(set) var closet: [Garment] = []
    private(set) var outfits: [OutfitLog] = []
    var weather: Weather = .mild { didSet { save() } }
    var formality: Formality = .casual { didSet { save() } }

    private let fileURL: URL
    let imagesDirectory: URL
    private let calendar: Calendar

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wardrobe.json")
    }

    init(fileURL: URL = WardrobeStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.imagesDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("wardrobe", isDirectory: true)
        self.calendar = calendar
        if case .loaded(let s) = JSONFile.load(Snapshot.self, from: fileURL) {
            closet = s.closet; outfits = s.outfits; weather = s.weather; formality = s.formality
        }
    }

    var laundry: [Garment] { closet.filter(\.needsWash).sorted { $0.wearsSinceWash > $1.wearsSinceWash } }

    func suggestion(now: Date = .now) -> [Garment] {
        let yesterday = outfit(on: calendar.date(byAdding: .day, value: -1, to: now) ?? now) ?? []
        return OutfitPicker.pick(from: closet, weather: weather, formality: formality, now: now, yesterday: yesterday)
    }

    func outfit(on day: Date) -> [Garment]? {
        guard let log = outfits.last(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return nil }
        return log.garmentIDs.compactMap { id in closet.first { $0.id == id } }
    }

    func todaysOutfit(now: Date = .now) -> [Garment]? { outfit(on: now) }

    func add(_ garment: Garment, imageData: Data?) {
        var g = garment
        if let imageData {
            try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            let file = "\(g.id).jpg"
            if (try? imageData.write(to: imagesDirectory.appendingPathComponent(file), options: .atomic)) != nil {
                g.imageFile = file
            }
        }
        closet.append(g)
        save()
    }

    func update(_ garment: Garment) {
        guard let i = closet.firstIndex(where: { $0.id == garment.id }) else { return }
        closet[i] = garment
        save()
    }

    func remove(id: String) {
        if let g = closet.first(where: { $0.id == id }), let file = g.imageFile {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
        closet.removeAll { $0.id == id }
        save()
    }

    /// Logs the outfit for today and bumps wear counts (once per garment per day).
    func wear(_ garments: [Garment], now: Date = .now) {
        let already = Set(todaysOutfit(now: now)?.map(\.id) ?? [])
        for g in garments where !already.contains(g.id) {
            guard let i = closet.firstIndex(where: { $0.id == g.id }) else { continue }
            closet[i].wearsSinceWash += 1
            closet[i].lastWorn = now
        }
        if let i = outfits.lastIndex(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            outfits[i].garmentIDs = Array(Set(outfits[i].garmentIDs + garments.map(\.id)))
        } else {
            outfits.append(OutfitLog(date: now, garmentIDs: garments.map(\.id)))
        }
        save()
    }

    func washed(id: String) {
        guard let i = closet.firstIndex(where: { $0.id == id }) else { return }
        closet[i].wearsSinceWash = 0
        save()
    }

    func washAll() {
        for i in closet.indices where closet[i].needsWash { closet[i].wearsSinceWash = 0 }
        save()
    }

    func imageURL(for garment: Garment) -> URL? {
        garment.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    func coachSummary() -> String {
        guard !closet.isEmpty else { return "" }
        var lines = ["## Closet: \(closet.count) items, weather set to \(weather.rawValue), style \(formality.rawValue)"]
        if !laundry.isEmpty { lines.append("Laundry pile: " + laundry.map(\.name).joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    private func save() {
        JSONFile.save(Snapshot(closet: closet, outfits: outfits, weather: weather, formality: formality), to: fileURL)
    }
}
