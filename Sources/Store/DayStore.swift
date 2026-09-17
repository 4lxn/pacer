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

    private struct Settings: Codable {
        var dayEnd: DateComponents
        var checkInsEnabled: Bool?
    }

    private let overridesURL: URL
    private let undoURL: URL
    private let settingsURL: URL

    static var defaultDirectory: URL { AppFiles.directory }

    init(directory: URL = DayStore.defaultDirectory, fallbackDayEnd: DateComponents = .hm(23, 0)) {
        overridesURL = directory.appendingPathComponent("overrides.json")
        undoURL = directory.appendingPathComponent("undo.json")
        settingsURL = directory.appendingPathComponent("settings.json")
        if case .loaded(let o) = JSONFile.load([String: DayOverride].self, from: overridesURL) { overrides = o }
        if case .loaded(let u) = JSONFile.load(UndoRecord.self, from: undoURL) { undo = u }
        if case .loaded(let s) = JSONFile.load(Settings.self, from: settingsURL) {
            dayEnd = s.dayEnd
            checkInsEnabled = s.checkInsEnabled ?? true
        } else {
            dayEnd = fallbackDayEnd
        }
    }

    private func saveSettings() { JSONFile.save(Settings(dayEnd: dayEnd, checkInsEnabled: checkInsEnabled), to: settingsURL) }

    func override(dayKey: String) -> DayOverride { overrides[dayKey] ?? DayOverride() }

    func setOverride(_ override: DayOverride, dayKey: String) {
        if override.isEmpty { overrides.removeValue(forKey: dayKey) } else { overrides[dayKey] = override }
        // Keep the file small: drop days older than yesterday.
        JSONFile.save(overrides, to: overridesURL)
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
