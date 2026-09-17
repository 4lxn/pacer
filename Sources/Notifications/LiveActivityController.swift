import ActivityKit
import Foundation
import OSLog

/// Keeps one Live Activity in step with the current block: started when a block is on, updated
/// when it changes, ended when nothing is on. Called from the same place the check-ins are re-armed.
@MainActor
enum LiveActivityController {
    private static let log = Logger(subsystem: "com.alan.autopiloto", category: "live-activity")

    static func sync(snapshot: DayTimeline.Snapshot, places: Places, calendar: Calendar = .current) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Activity<PacerActivityAttributes>.activities
        guard case .now(let block, let missed) = snapshot.state, !missed,
              let start = block.startDate(on: snapshot.date, calendar: calendar),
              let end = block.endDate(on: snapshot.date, calendar: calendar) else {
            for a in existing { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let next = snapshot.upcoming.first
        let state = PacerActivityAttributes.ContentState(
            blockID: block.id, label: block.label, start: start, end: end, place: places.name(id: block.place),
            nextLabel: next?.label, nextStart: next.flatMap { $0.startDate(on: snapshot.date, calendar: calendar) },
            done: snapshot.done, total: snapshot.total, dayKey: DayLogic.dayKey(snapshot.date, calendar: calendar)
        )
        let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(5 * 60))
        if let current = existing.first {
            for extra in existing.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            if current.content.state != state { await current.update(content) }
            return
        }
        do {
            _ = try Activity.request(attributes: PacerActivityAttributes(), content: content, pushType: nil)
            log.info("Started Live Activity for \(block.label)")
        } catch {
            log.error("Live Activity: \(error.localizedDescription)")
        }
    }

    static func endAll() async {
        for a in Activity<PacerActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }
}
