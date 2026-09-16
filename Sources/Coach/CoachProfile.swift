import Foundation

/// The static part of the Coach system prompt, editable by the user. Installs that predate the
/// editor keep the original text; fresh installs start from a short template.
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

    static func load(defaults: UserDefaults = .standard, legacyMarker: URL = CompletionStore.defaultURL) -> String {
        if let saved = defaults.string(forKey: key) { return saved }
        let seeded = FileManager.default.fileExists(atPath: legacyMarker.path) ? CoachContext.training : template
        defaults.set(seeded, forKey: key)
        return seeded
    }

    static func save(_ text: String, defaults: UserDefaults = .standard) {
        defaults.set(text, forKey: key)
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
