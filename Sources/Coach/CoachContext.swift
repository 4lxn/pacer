import Foundation

/// System prompt pieces for the Coach: the agent rules (appended to the user's profile) and the
/// per-request snapshot of today.
enum CoachContext {
    /// Rules appended to the profile when the Coach runs as an agent with tools.
    static let agentRules = """

    ## How you work
    - You have tools for everything in the app: plan blocks, pantry, meals and presets, targets, closet
      (garments, laundry, outfit context), study sessions and goal, income, and your own memory. Add,
      change or delete whatever the user asks; never claim you changed something without calling the tool.
    - Read before you write when ids matter: call get_plan before update_block / delete_block.
    - Ask before deleting a block or moving the anchor. Everything else: just do it, then say what changed in one line.
    - Keep answers short. Reply in the user's language.
    - When asked what to buy, use get_grocery_list and the pantry, and reason from the user's food rules.
    - Save durable preferences with remember (e.g. "hates broccoli"); don't save one-off facts.

    ## Format
    - Short. Lead with the answer. Plain sentences or "-" bullets; **bold** only the number or item
      that matters. No headings, no tables, no emoji, no closing questions.
    """

    /// Today's plan and status, for the volatile part of the system prompt.
    static func snapshot(blocks: [Block], now: Date, completed: Set<String>, calendar: Calendar = .current, extra: [String] = []) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        var lines = ["## Today: \(formatter.string(from: now))"]
        for block in blocks {
            if let note = block.note(on: now, calendar: calendar) {
                lines.append("\(block.label) today: \(note).")
            }
        }
        lines.append("Blocks (time, label, status):")
        for block in DayLogic.sorted(blocks) {
            let time = block.start.map(NotificationScheduler.clock) ?? "anytime"
            let status = block.status(now: now, completed: completed, calendar: calendar)
            lines.append("- \(time) \(block.label) — \(label(status))")
        }
        for section in extra where !section.isEmpty {
            lines.append("")
            lines.append(section)
        }
        return lines.joined(separator: "\n")
    }

    private static func label(_ status: BlockStatus) -> String {
        switch status {
        case .done: "done"
        case .skipped: "skipped today"
        case .current: "current"
        case .upcoming: "upcoming"
        case .missed: "missed"
        case .free: "not done yet"
        }
    }
}
