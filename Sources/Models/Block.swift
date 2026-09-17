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
    /// A check-in notification fires 5 min after `end` unless the block is done or skipped.
    /// Default: on for window blocks of 20 min or more, off for fixed blocks (their start
    /// notification already covers them) and never for the anchor.
    var checkIn: Bool = false
    /// Where it happens (Place id); nil = wherever you already are.
    var place: String? = nil

    init(
        id: String,
        label: String,
        kind: BlockKind,
        start: DateComponents? = nil,
        end: DateComponents? = nil,
        isAnchor: Bool = false,
        weekdays: Set<Int>? = nil,
        autoComplete: WorkoutMatch? = nil,
        weekdayNotes: [Int: String]? = nil,
        checkIn: Bool? = nil,
        place: String? = nil
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
        self.checkIn = checkIn ?? Block.defaultCheckIn(kind: kind, start: start, end: end, isAnchor: isAnchor)
        self.place = place
    }

    static func defaultCheckIn(kind: BlockKind, start: DateComponents?, end: DateComponents?, isAnchor: Bool) -> Bool {
        guard kind == .window, !isAnchor, let s = start, let e = end else { return false }
        let minutes = ((e.hour ?? 0) * 60 + (e.minute ?? 0)) - ((s.hour ?? 0) * 60 + (s.minute ?? 0))
        return minutes >= 20
    }

    var durationMinutes: Int? {
        guard let s = start, let e = end else { return nil }
        return ((e.hour ?? 0) * 60 + (e.minute ?? 0)) - ((s.hour ?? 0) * 60 + (s.minute ?? 0))
    }

    // Older plan.json files have no `checkIn`; decode it as its default.
    private enum CodingKeys: String, CodingKey { case id, label, kind, start, end, isAnchor, weekdays, autoComplete, weekdayNotes, checkIn, place }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decode(BlockKind.self, forKey: .kind)
        start = try c.decodeIfPresent(DateComponents.self, forKey: .start)
        end = try c.decodeIfPresent(DateComponents.self, forKey: .end)
        isAnchor = try c.decode(Bool.self, forKey: .isAnchor)
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays)
        autoComplete = try c.decodeIfPresent(WorkoutMatch.self, forKey: .autoComplete)
        weekdayNotes = try c.decodeIfPresent([Int: String].self, forKey: .weekdayNotes)
        checkIn = try c.decodeIfPresent(Bool.self, forKey: .checkIn)
            ?? Block.defaultCheckIn(kind: kind, start: start, end: end, isAnchor: isAnchor)
        place = try c.decodeIfPresent(String.self, forKey: .place)
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
