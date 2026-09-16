import Foundation

/// The seeded day. There is no editing UI: change this array and rebuild.
enum Plan {
    private static let weekdaysMonFri: Set<Int> = [2, 3, 4, 5, 6]
    private static let weekdaysTueFri: Set<Int> = [3, 4, 5, 6]
    private static let weekdaysTueSun: Set<Int> = [1, 3, 4, 5, 6, 7]

    static let blocks: [Block] = [
        Block(id: "b01", label: "Wake up", kind: .fixed, start: .hm(7, 30), end: .hm(7, 35), isAnchor: true),
        Block(id: "b02", label: "Bathroom + brush teeth", kind: .window, start: .hm(7, 30), end: .hm(7, 45)),
        Block(id: "b03", label: "Minoxidil AM + skincare", kind: .window, start: .hm(7, 35), end: .hm(7, 55)),
        Block(id: "b04", label: "Breakfast: shake + prunes", kind: .window, start: .hm(7, 55), end: .hm(8, 20)),
        Block(id: "b05", label: "Shower + dress", kind: .window, start: .hm(8, 20), end: .hm(8, 50)),
        Block(id: "b06", label: "Log on / leave for the office", kind: .fixed, start: .hm(9, 45), end: .hm(9, 55), weekdays: weekdaysMonFri),
        Block(id: "b07", label: "Work block", kind: .fixed, start: .hm(10, 0), end: .hm(13, 0), weekdays: weekdaysMonFri),
        Block(id: "b08", label: "Protein shake", kind: .fixed, start: .hm(11, 30), end: .hm(11, 45)),
        Block(id: "b09", label: "Lunch: beef + rice", kind: .window, start: .hm(13, 0), end: .hm(13, 40)),
        Block(id: "b10", label: "Work block", kind: .fixed, start: .hm(13, 45), end: .hm(15, 30), weekdays: weekdaysMonFri),
        Block(id: "b11", label: "Study", kind: .fixed, start: .hm(15, 45), end: .hm(17, 15), weekdays: weekdaysMonFri),
        Block(id: "b12", label: "Send one application", kind: .free, weekdays: weekdaysMonFri),
        Block(id: "b13", label: "Leave for training", kind: .fixed, start: .hm(17, 45), end: .hm(17, 55)),
        Block(id: "b14", label: "Run (Garmin Coach)", kind: .window, start: .hm(18, 0), end: .hm(19, 0), weekdays: weekdaysTueSun),
        Block(id: "b15", label: "Transition shake", kind: .fixed, start: .hm(19, 0), end: .hm(19, 15), weekdays: weekdaysTueFri),
        Block(id: "b16", label: "Gym · Min-Max B1", kind: .window, start: .hm(19, 15), end: .hm(20, 15), weekdays: weekdaysMonFri),
        Block(id: "b17", label: "Dinner", kind: .window, start: .hm(20, 30), end: .hm(21, 0)),
        Block(id: "b18", label: "Minox PM + skincare + brush teeth", kind: .fixed, start: .hm(21, 45), end: .hm(22, 0)),
        Block(id: "b19", label: "Lay out clothes + gym bag", kind: .window, start: .hm(22, 0), end: .hm(22, 15)),
        Block(id: "b20", label: "Screens off", kind: .fixed, start: .hm(22, 30), end: .hm(22, 40)),
        Block(id: "b21", label: "Sleep", kind: .fixed, start: .hm(23, 15), end: .hm(23, 30)),
    ]

    static let gymBlockID = "b16"

    /// Blocks that occur on the calendar day of `date`.
    static func today(on date: Date, calendar: Calendar = .current) -> [Block] {
        blocks.filter { $0.occurs(on: date, calendar: calendar) }
    }

    /// Min-Max Block 1 session for the weekday, Mon–Fri.
    static func gymSession(on date: Date, calendar: Calendar = .current) -> String? {
        switch calendar.component(.weekday, from: date) {
        case 2: "Upper 1"
        case 3: "Lower 1"
        case 4: "Upper 2"
        case 5: "Arms/Delts"
        case 6: "Lower 2"
        default: nil
        }
    }
}
