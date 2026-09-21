import Foundation

/// The chips on the first onboarding screen. Each one is a template: a few blocks placed
/// around the user's wake and sleep times. Pick several; they combine.
enum Goal: String, CaseIterable, Identifiable, Sendable {
    case gym, run, deepWork, study, cook, water, read, walk, meditate, leaveOnTime, mealPrep, earlyNight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gym: "Gym 3× a week"
        case .run: "Run in the morning"
        case .deepWork: "Deep work mornings"
        case .study: "Study 1 h a day"
        case .cook: "Cook at home"
        case .water: "Drink more water"
        case .read: "Read before bed"
        case .walk: "Walk 30 min"
        case .meditate: "10 min of quiet"
        case .leaveOnTime: "Leave work on time"
        case .mealPrep: "Meal prep Sunday"
        case .earlyNight: "Screens off by 22:30"
        }
    }

    var symbol: String {
        switch self {
        case .gym: "dumbbell"
        case .run: "figure.run"
        case .deepWork: "brain.head.profile"
        case .study: "book"
        case .cook: "frying.pan"
        case .water: "drop"
        case .read: "book.closed"
        case .walk: "figure.walk"
        case .meditate: "leaf"
        case .leaveOnTime: "door.left.hand.open"
        case .mealPrep: "takeoutbag.and.cup.and.straw"
        case .earlyNight: "moon.zzz"
        }
    }

    /// True for goals that already put training on the plan, so the starter's generic block goes.
    var isTraining: Bool { self == .gym || self == .run }

    private static let monWedFri: Set<Int> = [2, 4, 6]
    private static let tueThuSat: Set<Int> = [3, 5, 7]
    private static let monFri: Set<Int> = [2, 3, 4, 5, 6]

    /// Blocks for this goal. `at(base, minutes)` shifts a time; the caller clamps to the day.
    func blocks(wake: DateComponents, sleep: DateComponents, at: (DateComponents, Int) -> DateComponents, id: () -> String) -> [Block] {
        switch self {
        case .gym:
            [Block(id: id(), label: "Gym", kind: .window, start: at(wake, 690), end: at(wake, 750), weekdays: Self.monWedFri, autoComplete: .strength, checkIn: true)]
        case .run:
            [Block(id: id(), label: "Run", kind: .window, start: at(wake, 30), end: at(wake, 75), weekdays: Self.tueThuSat, autoComplete: .run, checkIn: true)]
        case .deepWork:
            [Block(id: id(), label: "Deep work", kind: .fixed, start: at(wake, 120), end: at(wake, 240), weekdays: Self.monFri, checkIn: true)]
        case .study:
            [Block(id: id(), label: "Study", kind: .window, start: at(sleep, -210), end: at(sleep, -150), autoComplete: .study, checkIn: true)]
        case .cook:
            [Block(id: id(), label: "Cook dinner", kind: .window, start: at(sleep, -200), end: at(sleep, -155), checkIn: true)]
        case .water:
            [Block(id: id(), label: "Water: 2 L", kind: .free)]
        case .read:
            [Block(id: id(), label: "Read", kind: .window, start: at(sleep, -60), end: at(sleep, -35), checkIn: true)]
        case .walk:
            [Block(id: id(), label: "Walk", kind: .window, start: at(wake, 420), end: at(wake, 450), checkIn: true)]
        case .meditate:
            [Block(id: id(), label: "Quiet", kind: .window, start: at(wake, 10), end: at(wake, 20))]
        case .leaveOnTime:
            [Block(id: id(), label: "Leave work", kind: .fixed, start: at(wake, 600), end: at(wake, 605), weekdays: Self.monFri)]
        case .mealPrep:
            [Block(id: id(), label: "Meal prep", kind: .window, start: at(sleep, -360), end: at(sleep, -270), weekdays: [1], checkIn: true)]
        case .earlyNight:
            [Block(id: id(), label: "Screens off", kind: .fixed, start: .hm(22, 30), end: .hm(22, 40))]
        }
    }
}

/// The "About you" chips. They become the profile text Ask reads, so no typing is needed.
@MainActor
enum ProfileChips {
    struct Group: Identifiable {
        let id: String
        let title: String
        let options: [String]
    }

    static let groups: [Group] = [
        Group(id: "training", title: "I train…", options: ["Gym", "Running", "Cycling", "Swimming", "Yoga", "Team sports", "Not yet"]),
        Group(id: "food", title: "I eat…", options: ["High protein", "Vegetarian", "Vegan", "Intermittent fasting", "No sugar on weekdays", "Whatever's around"]),
        Group(id: "rules", title: "Always…", options: ["Keep it short", "Be blunt", "Be gentle", "No medical advice", "Answer in Spanish", "Answer in English"]),
    ]

    /// Profile text from goals, chips and the day's shape. Empty groups keep the template hint.
    static func compose(goals: Set<Goal>, picks: [String: Set<String>], wake: DateComponents, sleep: DateComponents, extra: String) -> String {
        func list(_ id: String) -> String { picks[id, default: []].sorted().joined(separator: ", ") }
        var about = "Wakes at \(DayLogic.clock(wake)), sleeps at \(DayLogic.clock(sleep))."
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { about += " " + extra }
        return CoachProfile.compose(answers: [
            "about": about,
            "goals": goals.map(\.label).sorted().joined(separator: ", "),
            "training": list("training"),
            "food": list("food"),
            "rules": list("rules"),
        ])
    }
}

extension Plan {
    /// The first plan: the starter day plus one template per goal. Goal blocks that would fall
    /// outside the day are clamped by `starter`'s `at` rule (00:00–23:59).
    static func plan(wake: DateComponents, sleep: DateComponents, goals: Set<Goal>) -> [Block] {
        let clampedSleep = DayLogic.minutes(sleep) <= DayLogic.minutes(wake) ? DateComponents.hm(23, 30) : sleep
        func at(_ base: DateComponents, _ minutes: Int) -> DateComponents {
            let total = min(23 * 60 + 59, max(0, DayLogic.minutes(base) + minutes))
            return .hm(total / 60, total % 60)
        }
        let id = { UUID().uuidString }
        var blocks = starter(wake: wake, sleep: sleep, includeTraining: !goals.contains { $0.isTraining })
        for goal in Goal.allCases where goals.contains(goal) {
            blocks += goal.blocks(wake: wake, sleep: clampedSleep, at: at, id: id)
        }
        return blocks
    }
}
