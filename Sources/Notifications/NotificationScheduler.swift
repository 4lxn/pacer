import Foundation
import OSLog
import UserNotifications

enum NotificationScheduler {
    static let categoryID = "BLOCK_ACTIONS"
    static let markDoneActionID = "MARK_DONE"
    static let snoozeActionID = "SNOOZE_10"
    static let blockIDKey = "blockId"
    /// iOS keeps at most 64 pending local notifications per app.
    static let maxPending = 64
    static let snoozeSeconds: TimeInterval = 600

    private static let log = Logger(subsystem: "com.alan.autopiloto", category: "notifications")

    /// One repeating calendar trigger per `.fixed` block. Blocks limited to some weekdays get one
    /// trigger per weekday (a repeating trigger with a `weekday` component). Pure: no side effects.
    static func buildRequests(for blocks: [Block]) -> [UNNotificationRequest] {
        blocks.filter { $0.kind == .fixed }.flatMap { block -> [UNNotificationRequest] in
            guard let start = block.start else { return [] }
            let weekdays: [Int?] = block.weekdays.map { $0.sorted().map(Optional.some) } ?? [nil]
            return weekdays.map { weekday in
                var components = DateComponents(hour: start.hour, minute: start.minute)
                components.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let identifier = weekday.map { "\(block.id)-wd\($0)" } ?? block.id
                return UNNotificationRequest(identifier: identifier, content: content(for: block), trigger: trigger)
            }
        }
    }

    /// One-shot re-fire 10 minutes out, used by the SNOOZE_10 action.
    static func snoozeRequest(for block: Block) -> UNNotificationRequest {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snoozeSeconds, repeats: false)
        return UNNotificationRequest(identifier: "\(block.id)-snooze", content: content(for: block), trigger: trigger)
    }

    static func content(for block: Block) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = block.label
        if let start = block.start, let end = block.end {
            content.body = "\(Self.clock(start)) – \(Self.clock(end))"
        }
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = [blockIDKey: block.id]
        content.threadIdentifier = "autopiloto"
        if block.isAnchor {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }

    static func clock(_ c: DateComponents) -> String {
        String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func registerCategory(center: UNUserNotificationCenter = .current()) {
        let done = UNNotificationAction(identifier: markDoneActionID, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeActionID, title: "Snooze 10 min", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [done, snooze], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Removes every pending request and re-adds the plan's. Fine at this scale.
    static func register(_ blocks: [Block], center: UNUserNotificationCenter = .current()) async {
        let requests = buildRequests(for: blocks)
        assert(requests.count <= maxPending, "Plan needs \(requests.count) notifications; iOS allows \(maxPending)")
        if requests.count > maxPending {
            log.warning("Plan needs \(requests.count) notifications; iOS allows \(Self.maxPending). Extra ones will be dropped by the system.")
        }
        center.removeAllPendingNotificationRequests()
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                log.error("Could not schedule \(request.identifier): \(error.localizedDescription)")
            }
        }
        log.info("Scheduled \(requests.count) repeating notifications")
    }

    static func requestAuthorization(center: UNUserNotificationCenter = .current()) async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// True only when the user has explicitly denied; `.notDetermined` is not a denial yet.
    static func isDenied(center: UNUserNotificationCenter = .current()) async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }
}
