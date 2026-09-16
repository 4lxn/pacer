import Foundation
import Observation

/// Completed block ids per calendar day, persisted as JSON in Application Support.
/// The day key is derived from the date passed in, so the store rolls over at midnight by itself.
@Observable
@MainActor
final class CompletionStore {
    private(set) var days: [String: Set<String>] = [:]
    private let fileURL: URL
    private let calendar: Calendar

    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("completions.json")
    }

    init(fileURL: URL = CompletionStore.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        load()
    }

    func completed(on date: Date) -> Set<String> {
        days[DayLogic.dayKey(date, calendar: calendar)] ?? []
    }

    func markDone(_ id: String, on date: Date) {
        days[DayLogic.dayKey(date, calendar: calendar), default: []].insert(id)
        save()
    }

    func toggle(_ id: String, on date: Date) {
        let key = DayLogic.dayKey(date, calendar: calendar)
        var set = days[key] ?? []
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        days[key] = set
        save()
    }

    /// Re-read from disk. Called when the app becomes active so a Done tapped on a
    /// notification while the app was suspended shows up.
    func reload() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) else { return }
        days = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(days)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("CompletionStore save failed: \(error)")
        }
    }
}
