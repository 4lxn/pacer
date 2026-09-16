import Foundation

enum BlockKind: String, Codable {
    case fixed    // must start at `start`
    case window   // may happen anywhere in [start, end]
    case free     // anytime today, no clock
}

struct Block: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var kind: BlockKind
    var start: DateComponents?   // hour + minute only; nil for .free
    var end: DateComponents?     // hour + minute only; nil for .free
    var isAnchor: Bool           // exactly one block in the plan; never droppable
    var weekdays: Set<Int>?      // Calendar weekday (1 = Sunday … 7 = Saturday); nil = every day
    var autoComplete: WorkoutMatch?   // a matching Apple Health workout today marks this block done
    var weekdayNotes: [Int: String]?  // optional per-weekday subtitle, e.g. the gym session of the day

    init(
        id: String,
        label: String,
        kind: BlockKind,
        start: DateComponents? = nil,
        end: DateComponents? = nil,
        isAnchor: Bool = false,
        weekdays: Set<Int>? = nil,
        autoComplete: WorkoutMatch? = nil,
        weekdayNotes: [Int: String]? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.start = start
        self.end = end
        self.isAnchor = isAnchor
        self.weekdays = weekdays
        self.autoComplete = autoComplete
        self.weekdayNotes = weekdayNotes
    }

    func note(on day: Date, calendar: Calendar) -> String? {
        weekdayNotes?[calendar.component(.weekday, from: day)]
    }

    /// Wall-clock start on the calendar day of `day`. Built with `Calendar`, so it survives DST.
    func startDate(on day: Date, calendar: Calendar) -> Date? {
        Self.date(from: start, on: day, calendar: calendar)
    }

    func endDate(on day: Date, calendar: Calendar) -> Date? {
        Self.date(from: end, on: day, calendar: calendar)
    }

    func occurs(on day: Date, calendar: Calendar) -> Bool {
        guard let weekdays else { return true }
        return weekdays.contains(calendar.component(.weekday, from: day))
    }

    private static func date(from components: DateComponents?, on day: Date, calendar: Calendar) -> Date? {
        guard let components, let hour = components.hour, let minute = components.minute else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

extension DateComponents {
    static func hm(_ hour: Int, _ minute: Int) -> DateComponents {
        DateComponents(hour: hour, minute: minute)
    }
}
