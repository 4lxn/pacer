import Foundation

/// Seed plans: `blocks` is a sample day (tests, previews); `starter(wake:sleep:)` builds the
/// first plan for a new user.
enum Plan {
    private static let weekdaysMonFri: Set<Int> = [2, 3, 4, 5, 6]
    private static let weekdaysTueFri: Set<Int> = [3, 4, 5, 6]
    private static let weekdaysTueSun: Set<Int> = [1, 3, 4, 5, 6, 7]

    /// A sample day used by tests and previews. Not personal: no medication, no programs.
    static let blocks: [Block] = [
        Block(id: "b01", label: "Wake up", kind: .fixed, start: .hm(7, 30), end: .hm(7, 35), isAnchor: true),
        Block(id: "b02", label: "Bathroom + brush teeth", kind: .window, start: .hm(7, 30), end: .hm(7, 45)),
        Block(id: "b03", label: "Skincare", kind: .window, start: .hm(7, 35), end: .hm(7, 55)),
        Block(id: "b04", label: "Breakfast", kind: .window, start: .hm(7, 55), end: .hm(8, 20)),
        Block(id: "b05", label: "Shower + dress", kind: .window, start: .hm(8, 20), end: .hm(8, 50)),
        Block(id: "b06", label: "Log on / leave for the office", kind: .fixed, start: .hm(9, 45), end: .hm(9, 55), weekdays: weekdaysMonFri),
        Block(id: "b07", label: "Work block", kind: .fixed, start: .hm(10, 0), end: .hm(13, 0), weekdays: weekdaysMonFri),
        Block(id: "b08", label: "Snack", kind: .fixed, start: .hm(11, 30), end: .hm(11, 45)),
        Block(id: "b09", label: "Lunch", kind: .window, start: .hm(13, 0), end: .hm(13, 40)),
        Block(id: "b10", label: "Work block", kind: .fixed, start: .hm(13, 45), end: .hm(15, 30), weekdays: weekdaysMonFri),
        Block(id: "b11", label: "Study", kind: .fixed, start: .hm(15, 45), end: .hm(17, 15), weekdays: weekdaysMonFri, autoComplete: .study),
        Block(id: "b12", label: "One thing for the future", kind: .free, weekdays: weekdaysMonFri),
        Block(id: "b13", label: "Leave for training", kind: .fixed, start: .hm(17, 45), end: .hm(17, 55)),
        Block(id: "b14", label: "Run", kind: .window, start: .hm(18, 0), end: .hm(19, 0), weekdays: weekdaysTueSun, autoComplete: .run),
        Block(id: "b15", label: "Snack", kind: .fixed, start: .hm(19, 0), end: .hm(19, 15), weekdays: weekdaysTueFri),
        Block(id: "b16", label: "Gym", kind: .window, start: .hm(19, 15), end: .hm(20, 15), weekdays: weekdaysMonFri, autoComplete: .strength,
              weekdayNotes: [2: "Upper", 3: "Lower", 4: "Upper", 5: "Arms", 6: "Lower"]),
        Block(id: "b17", label: "Dinner", kind: .window, start: .hm(20, 30), end: .hm(21, 0)),
        Block(id: "b18", label: "Evening routine", kind: .fixed, start: .hm(21, 45), end: .hm(22, 0)),
        Block(id: "b19", label: "Lay out clothes + gym bag", kind: .window, start: .hm(22, 0), end: .hm(22, 15)),
        Block(id: "b20", label: "Screens off", kind: .fixed, start: .hm(22, 30), end: .hm(22, 40)),
        Block(id: "b21", label: "Sleep", kind: .fixed, start: .hm(23, 15), end: .hm(23, 30)),
    ]

    static let gymBlockID = "b16"

    /// A generic day built around the user's wake and sleep times. Work blocks Mon–Fri.
    /// A sleep time after midnight is clamped to 23:30 — the day is the calendar day, and a
    /// 00:30 block would sort first and read as missed all day.
    static func starter(wake: DateComponents, sleep: DateComponents) -> [Block] {
        func minutes(_ c: DateComponents) -> Int { (c.hour ?? 0) * 60 + (c.minute ?? 0) }
        let sleep = minutes(sleep) <= minutes(wake) ? DateComponents.hm(23, 30) : sleep
        func at(_ base: DateComponents, _ minutes: Int) -> DateComponents {
            let total = min(23 * 60 + 59, max(0, (base.hour ?? 0) * 60 + (base.minute ?? 0) + minutes))
            return .hm(total / 60, total % 60)
        }
        let id = { UUID().uuidString }
        return [
            Block(id: id(), label: "Wake up", kind: .fixed, start: wake, end: at(wake, 5), isAnchor: true),
            Block(id: id(), label: "Morning routine", kind: .window, start: at(wake, 5), end: at(wake, 45)),
            Block(id: id(), label: "Breakfast", kind: .window, start: at(wake, 30), end: at(wake, 60)),
            Block(id: id(), label: "Work", kind: .fixed, start: at(wake, 150), end: at(wake, 330), weekdays: weekdaysMonFri),
            Block(id: id(), label: "Lunch", kind: .window, start: at(wake, 330), end: at(wake, 370)),
            Block(id: id(), label: "Work", kind: .fixed, start: at(wake, 390), end: at(wake, 540), weekdays: weekdaysMonFri),
            Block(id: id(), label: "Train", kind: .window, start: at(wake, 600), end: at(wake, 660)),
            Block(id: id(), label: "One thing for the future", kind: .free),
            Block(id: id(), label: "Dinner", kind: .window, start: at(sleep, -180), end: at(sleep, -150)),
            Block(id: id(), label: "Wind down, screens off", kind: .fixed, start: at(sleep, -45), end: at(sleep, -35)),
            Block(id: id(), label: "Sleep", kind: .fixed, start: sleep, end: at(sleep, 15)),
        ]
    }
}
