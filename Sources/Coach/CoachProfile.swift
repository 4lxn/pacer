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

    /// The onboarding questions. Answers become the profile sections below.
    struct Question: Identifiable {
        let id: String
        let title: String
        let hint: String
        let placeholder: String
    }

    static let questions: [Question] = [
        Question(id: "about", title: "Who are you?", hint: "Age, what you do, what your days look like.", placeholder: "27, software engineer, remote, two kids…"),
        Question(id: "goals", title: "What are you working toward?", hint: "Numbers and dates help the coach push the right way.", placeholder: "Lose 5 kg by December, run a 10K under 55 min…"),
        Question(id: "training", title: "How do you train?", hint: "Program, days, and what decides your workouts (a watch, a coach, an app).", placeholder: "Gym 4x/week, runs Tue/Thu/Sun from my Garmin plan…"),
        Question(id: "food", title: "How do you eat?", hint: "Targets, the foods you actually eat, rules you follow.", placeholder: "~2,000 kcal, 150 g protein, rice + chicken + eggs, no sugar on weekdays…"),
        Question(id: "rules", title: "Anything the coach must always remember?", hint: "Things it must never suggest, or always take into account.", placeholder: "Never medical advice; I hate broccoli; gym closed on Sundays…"),
    ]

    /// Builds the profile text from onboarding answers. Empty answers keep the template's
    /// placeholder line so the user sees what to fill in later.
    static func compose(answers: [String: String]) -> String {
        func section(_ id: String, _ fallback: String) -> String {
            let text = (answers[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? fallback : text
        }
        return """
        You are my coach. Answer in the language I write in. Be short and concrete.

        ## About me
        \(section("about", "(age, work, what my days look like)"))

        ## Goals
        \(section("goals", "(weight, strength, running, study — with numbers and dates)"))

        ## Training
        \(section("training", "(program, days, what the watch or coach app dictates)"))

        ## Food
        \(section("food", "(targets, foods I actually eat, rules)"))

        ## Rules
        \(section("rules", "(what you must never do, e.g. medical advice)"))
        """
    }

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
