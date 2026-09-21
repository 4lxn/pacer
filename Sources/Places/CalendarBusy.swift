import EventKit
import Foundation
import Observation

/// Calendar events as busy time for the replanner and grey rows on Now. Read-only, on device;
/// nothing is written and nothing leaves the phone. Off unless the user turns it on in Settings.
@Observable
@MainActor
final class CalendarBusy {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
    }

    static let shared = CalendarBusy()
    private let store = EKEventStore()
    /// dayKey → events that day, refreshed for today and tomorrow.
    private(set) var events: [String: [Event]] = [:]
    private(set) var denied = false

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        denied = !ok
        return ok
    }

    /// Loads today and tomorrow. All-day events are not busy time.
    func refresh(now: Date = .now, calendar: Calendar = .current) {
        guard isAuthorized else { events = [:]; return }
        var out: [String: [Event]] = [:]
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            out[DayLogic.dayKey(day, calendar: calendar)] = store.events(matching: predicate)
                .filter { !$0.isAllDay && $0.endDate > $0.startDate }
                .map { Event(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Busy", start: $0.startDate, end: $0.endDate) }
                .sorted { $0.start < $1.start }
        }
        events = out
    }

    /// Replanner obstacles for a day, clipped to the calendar day.
    func obstacles(dayKey: String, calendar: Calendar = .current) -> [Replanner.Obstacle] {
        (events[dayKey] ?? []).compactMap { e in
            let s = DayLogic.minutesOfDay(e.start, calendar: calendar)
            let sameDay = calendar.isDate(e.start, inSameDayAs: e.end)
            let en = sameDay ? DayLogic.minutesOfDay(e.end, calendar: calendar) : 23 * 60 + 59
            return en > s ? Replanner.Obstacle(start: s, end: en, label: e.title, place: nil) : nil
        }
    }
}
