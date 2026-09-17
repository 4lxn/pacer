import SwiftUI

/// The sections of the app. Today is always on; the rest are the user's to keep or hide, in
/// their order. Each owns a tint so its hero, progress and charts read as one thing.
enum AppSection: String, CaseIterable, Codable, Identifiable, Sendable {
    case today, train, food, focus, money, closet, coach

    var id: String { rawValue }
    var isCore: Bool { self == .today }

    var title: String {
        switch self {
        case .today: "Today"
        case .train: "Train"
        case .food: "Food"
        case .focus: "Focus"
        case .money: "Money"
        case .closet: "Closet"
        case .coach: "Coach"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .train: "figure.run"
        case .food: "fork.knife"
        case .focus: "timer"
        case .money: "banknote"
        case .closet: "tshirt"
        case .coach: "bubble.left.and.text.bubble.right"
        }
    }

    var pitch: String {
        switch self {
        case .today: "Your plan, what's now, what's next."
        case .train: "Workouts and weight from Apple Health; sessions close themselves."
        case .food: "Calories and macros, pantry, recipes, groceries."
        case .focus: "Focus sessions with a timer in the Dynamic Island; subjects and streaks."
        case .money: "Income, expenses, budgets, savings."
        case .closet: "Scan clothes, laundry, today's outfit."
        case .coach: "An AI coach that knows all of this and can change your day."
        }
    }

    var tint: Color {
        switch self {
        case .today: .accentColor
        case .train: .orange
        case .food: .green
        case .focus: .indigo
        case .money: .teal
        case .closet: .pink
        case .coach: .purple
        }
    }

    /// Coach tools that belong to a section; tools not listed anywhere are always on.
    var toolPrefixes: [String] {
        switch self {
        case .today, .coach: []
        case .train: ["get_training"]
        case .food: ["get_pantry", "add_pantry_item", "adjust_pantry", "delete_pantry_item", "get_grocery_list", "get_meals_today", "log_meal", "get_recipes", "add_recipe", "cook_recipe", "delete_recipe", "delete_meal", "set_targets", "add_preset", "delete_preset", "log_water"]
        case .focus: ["get_study", "add_study_session", "delete_study_session", "set_study_goal", "start_focus", "stop_focus"]
        case .money: ["get_income", "add_income", "delete_income", "set_income_goal", "add_expense", "get_money", "set_budget", "delete_expense", "add_recurring"]
        case .closet: ["get_closet", "add_garment", "update_garment", "delete_garment", "wear_outfit", "mark_washed", "set_closet_context"]
        }
    }
}

/// Which sections are on, in what order (`sections.json`).
@Observable
@MainActor
final class SectionStore {
    private struct File: Codable { var enabled: [AppSection] }
    private(set) var enabled: [AppSection]
    private let fileURL: URL

    /// Every section, in the canonical order (used to slot a re-enabled section back).
    static let defaultOrder: [AppSection] = [.today, .train, .food, .focus, .money, .closet, .coach]
    /// What a new user gets: five tabs, the coach reachable in one tap. Money and Closet are a toggle away.
    static let defaultEnabled: [AppSection] = [.today, .train, .food, .focus, .coach]

    init(fileURL: URL = AppFiles.url("sections.json")) {
        self.fileURL = fileURL
        if case .loaded(let f) = JSONFile.load(File.self, from: fileURL), !f.enabled.isEmpty {
            enabled = f.enabled.contains(.today) ? f.enabled : [.today] + f.enabled
        } else {
            enabled = Self.defaultEnabled
        }
    }

    func isOn(_ s: AppSection) -> Bool { enabled.contains(s) }

    func set(_ s: AppSection, on: Bool) {
        guard !s.isCore else { return }
        if on, !enabled.contains(s) {
            // Keep the default relative order when re-enabling.
            let after = enabled.filter { Self.defaultOrder.firstIndex(of: $0)! < Self.defaultOrder.firstIndex(of: s)! }
            enabled.insert(s, at: after.count)
        } else if !on {
            enabled.removeAll { $0 == s }
        }
        save()
    }

    func move(from: IndexSet, to: Int) {
        enabled.move(fromOffsets: from, toOffset: to)
        if let i = enabled.firstIndex(of: .today), i != 0 { enabled.remove(at: i); enabled.insert(.today, at: 0) }
        save()
    }

    func replace(_ list: [AppSection]) {
        enabled = list.contains(.today) ? list : [.today] + list
        save()
    }

    /// Tool names the coach may use given the enabled sections.
    func allowsTool(_ name: String) -> Bool {
        for s in AppSection.allCases where !enabled.contains(s) {
            if s.toolPrefixes.contains(where: { name == $0 || name.hasPrefix($0) }) { return false }
        }
        return true
    }

    private func save() { JSONFile.save(File(enabled: enabled), to: fileURL) }
}
