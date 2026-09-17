import Foundation
import Observation

/// Per-day overrides (moved blocks) and the single-level undo record. Small files:
/// `overrides.json` keyed by dayKey, `undo.json`.
@Observable
@MainActor
final class DayStore {
    private(set) var overrides: [String: DayOverride] = [:]
    private(set) var undo: UndoRecord?
    /// Day end used by the replanner, ≤ 23:59. Set at onboarding from the sleep time.
    var dayEnd: DateComponents { didSet { saveSettings() } }
    /// Master switch for end-of-block check-ins (start notifications are unaffected).
    var checkInsEnabled = true { didSet { saveSettings() } }
    /// Dynamic Island / Lock Screen Live Activity for the block that's on.
    var liveActivity = true { didSet { saveSettings() } }
    /// One notification when the first block ends: the day in one line.
    var morningBrief = true { didSet { saveSettings() } }
    /// "pacer" (the bundled chime) or "system".
    var sound = "pacer" { didSet { saveSettings() } }
    /// Places and travel times between them (`places.json`).
    var places = Places() { didSet { JSONFile.save(places, to: placesURL) } }
    /// Maps ETAs for specific legs, keyed by dayKey then block id (`legs.json`); refreshed with the
    /// block's departure time so traffic at that hour counts. Overrides the flat matrix.
    private(set) var legs: [String: [String: Int]] = [:]

    private struct Settings: Codable {
        var dayEnd: DateComponents
        var checkInsEnabled: Bool?
        var sound: String?
        var liveActivity: Bool?
        var morningBrief: Bool?
    }

    private let overridesURL: URL
    private let undoURL: URL
    private let settingsURL: URL
    private let placesURL: URL
    private let legsURL: URL

    static var defaultDirectory: URL { AppFiles.directory }

    init(directory: URL = DayStore.defaultDirectory, fallbackDayEnd: DateComponents = .hm(23, 0)) {
        overridesURL = directory.appendingPathComponent("overrides.json")
        undoURL = directory.appendingPathComponent("undo.json")
        settingsURL = directory.appendingPathComponent("settings.json")
        placesURL = directory.appendingPathComponent("places.json")
        legsURL = directory.appendingPathComponent("legs.json")
        if case .loaded(let p) = JSONFile.load(Places.self, from: placesURL) { places = p }
        if case .loaded(let l) = JSONFile.load([String: [String: Int]].self, from: legsURL) { legs = l }
        if case .loaded(let o) = JSONFile.load([String: DayOverride].self, from: overridesURL) { overrides = o }
        if case .loaded(let u) = JSONFile.load(UndoRecord.self, from: undoURL) { undo = u }
        if case .loaded(let s) = JSONFile.load(Settings.self, from: settingsURL) {
            dayEnd = s.dayEnd
            checkInsEnabled = s.checkInsEnabled ?? true
            sound = s.sound ?? "pacer"
            liveActivity = s.liveActivity ?? true
            morningBrief = s.morningBrief ?? true
        } else {
            dayEnd = fallbackDayEnd
        }
    }

    private func saveSettings() { JSONFile.save(Settings(dayEnd: dayEnd, checkInsEnabled: checkInsEnabled, sound: sound, liveActivity: liveActivity, morningBrief: morningBrief), to: settingsURL) }

    func override(dayKey: String) -> DayOverride { overrides[dayKey] ?? DayOverride() }

    func setOverride(_ override: DayOverride, dayKey: String) {
        if override.isEmpty { overrides.removeValue(forKey: dayKey) } else { overrides[dayKey] = override }
        // Keep the file small: drop days older than yesterday.
        JSONFile.save(overrides, to: overridesURL)
    }

    func legMinutes(dayKey: String) -> [String: Int] { legs[dayKey] ?? [:] }

    /// Replaces a day's Maps legs and drops days before `keep`.
    func setLegs(_ minutes: [String: Int], dayKey: String, keepFrom keep: String) {
        legs[dayKey] = minutes
        legs = legs.filter { $0.key >= keep }
        JSONFile.save(legs, to: legsURL)
    }

    func setNote(_ note: String, blockID: String, dayKey: String) {
        var o = override(dayKey: dayKey)
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { o.notes.removeValue(forKey: blockID) } else { o.notes[blockID] = clean }
        setOverride(o, dayKey: dayKey)
    }

    func addExtra(_ block: Block, dayKey: String) {
        var o = override(dayKey: dayKey)
        o.extras.removeAll { $0.id == block.id }
        o.extras.append(block)
        setOverride(o, dayKey: dayKey)
    }

    func removeExtra(_ id: String, dayKey: String) {
        var o = override(dayKey: dayKey)
        o.extras.removeAll { $0.id == id }
        o.moved.removeValue(forKey: id)
        o.notes.removeValue(forKey: id)
        setOverride(o, dayKey: dayKey)
    }

    func setUndo(_ record: UndoRecord?) {
        undo = record
        if let record { JSONFile.save(record, to: undoURL) } else { try? FileManager.default.removeItem(at: undoURL) }
    }

    /// Clamp to 23:59; a sleep time at/after midnight (earlier than wake) becomes 23:59.
    static func dayEnd(fromSleep sleep: DateComponents, wake: DateComponents) -> DateComponents {
        DayLogic.minutes(sleep) <= DayLogic.minutes(wake) ? .hm(23, 59) : sleep
    }
}
