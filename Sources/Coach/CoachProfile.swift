import Foundation

/// The static part of the Coach system prompt, editable by the user; new installs start from a
/// short template.
@MainActor
enum CoachProfile {
    static let key = "coachProfile"

    static let template = """
    You are my coach. Answer in the language I write in. Be short and concrete.

    ## About me
    (age, work, what my days look like)

    ## Goals
    (weight, strength, running, study — with numbers and dates)

    ## Training
    (program, days, what the watch or coach app dictates)

    ## Food
    (targets, foods I actually eat, rules)

    ## Rules
    (what you must never do, e.g. medical advice)
    """

    static func load(defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: key) { return saved }
        defaults.set(template, forKey: key)
        return template
    }

    static func save(_ text: String, defaults: UserDefaults = .standard) {
        defaults.set(text, forKey: key)
    }

    /// Removes Memory lines containing `text` (case-insensitive). Returns how many were removed.
    @discardableResult
    static func forget(_ text: String, defaults: UserDefaults = .standard) -> Int {
        let lines = load(defaults: defaults).components(separatedBy: "\n")
        let needle = text.lowercased()
        var inMemory = false
        var removed = 0
        let kept = lines.filter { line in
            if line.hasPrefix("## ") { inMemory = line.hasPrefix("## Memory") }
            if inMemory, line.hasPrefix("- "), line.lowercased().contains(needle) { removed += 1; return false }
            return true
        }
        if removed > 0 { save(kept.joined(separator: "\n"), defaults: defaults) }
        return removed
    }

    /// Appends a line under a `## Memory` section (created on first use). The agent's `remember` tool.
    static func appendMemory(_ note: String, defaults: UserDefaults = .standard) {
        var text = load(defaults: defaults)
        let line = "- \(note.trimmingCharacters(in: .whitespacesAndNewlines))"
        if text.contains("## Memory") {
            text += "\n" + line
        } else {
            text += "\n\n## Memory\n" + line
        }
        save(text, defaults: defaults)
    }
}
