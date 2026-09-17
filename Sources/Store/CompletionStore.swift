import Foundation
import Observation

/// Done and skipped block ids per calendar day, persisted as JSON. Day rollover falls out of
/// keying by the date (or dayKey) passed in.
@Observable
@MainActor
final class CompletionStore {
    struct Day: Codable, Equatable {
        var done: Set<String> = []
        var skipped: Set<String> = []
    }

    private(set) var days: [String: Day] = [:]
    private let fileURL: URL
    private let calendar: Calendar

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("completions.json")
    }

    init(fileURL: URL = CompletionStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        load()
    }

    // MARK: - Reads

    func completed(on date: Date) -> Set<String> { completed(dayKey: key(date)) }
    func skipped(on date: Date) -> Set<String> { skipped(dayKey: key(date)) }
    func completed(dayKey: String) -> Set<String> { days[dayKey]?.done ?? [] }
    func skipped(dayKey: String) -> Set<String> { days[dayKey]?.skipped ?? [] }

    // MARK: - Writes

    func markDone(_ id: String, on date: Date) { markDone(id, dayKey: key(date)) }

    func markDone(_ id: String, dayKey: String) {
        days[dayKey, default: Day()].done.insert(id)
        days[dayKey]?.skipped.remove(id)
        save()
    }

    func toggle(_ id: String, on date: Date) {
        let k = key(date)
        var day = days[k] ?? Day()
        if day.done.contains(id) { day.done.remove(id) } else { day.done.insert(id); day.skipped.remove(id) }
        days[k] = day
        save()
    }

    func skip(_ id: String, on date: Date) { skip(id, dayKey: key(date)) }

    func skip(_ id: String, dayKey: String) {
        days[dayKey, default: Day()].skipped.insert(id)
        days[dayKey]?.done.remove(id)
        save()
    }

    func unskip(_ id: String, on date: Date) {
        days[key(date)]?.skipped.remove(id)
        save()
    }

    /// Re-read from disk. Called when the app becomes active so a Done tapped on a
    /// notification while the app was suspended shows up.
    func reload() { load() }

    // MARK: - Persistence

    /// Older files were `[String: Set<String>]` (done only); read both shapes.
    private struct Legacy: Decodable { let values: [String: Set<String>] }

    private func load() {
        switch JSONFile.load([String: Day].self, from: fileURL) {
        case .loaded(let decoded):
            days = decoded
        case .missing, .corrupt:
            // The `.corrupt` branch already moved the file aside; try the pre-skip shape from the copy.
            let bad = fileURL.appendingPathExtension("bad")
            if let data = try? Data(contentsOf: bad),
               let old = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
                days = old.mapValues { Day(done: $0, skipped: []) }
                try? FileManager.default.removeItem(at: bad)
                PersistenceState.shared.clear()
                save()
            }
        }
    }

    private func save() { JSONFile.save(days, to: fileURL) }

    private func key(_ date: Date) -> String { DayLogic.dayKey(date, calendar: calendar) }
}
