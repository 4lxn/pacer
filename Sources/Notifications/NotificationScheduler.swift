import Foundation
import OSLog
import UserNotifications

enum NotificationScheduler {
    // Start notifications (repeating, per fixed block × weekday)
    static let categoryID = "BLOCK_ACTIONS"
    static let markDoneActionID = "MARK_DONE"
    static let snoozeActionID = "SNOOZE_10"
    // Check-ins (one-shot, 5 min after a block ends, today + tomorrow)
    static let checkInCategoryID = "CHECK_IN"
    static let skipTodayActionID = "SKIP_TODAY"
    static let checkInPrefix = "checkin-"
    static let checkInDelayMinutes = 5
    static let checkInDays = 2

    static let blockIDKey = "blockId"
    static let dayKeyKey = "dayKey"
    /// iOS keeps at most 64 pending local notifications per app.
    static let maxPending = 64
    static let snoozeSeconds: TimeInterval = 600

    private static let log = Logger(subsystem: "com.alan.autopiloto", category: "notifications")

    // MARK: - Start notifications (unchanged scheme: repeating, survive force-quit)

    /// One repeating calendar trigger per `.fixed` block. Blocks limited to some weekdays get one
    /// trigger per weekday. Pure.
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
            content.body = "\(DayLogic.clock(start)) – \(DayLogic.clock(end))"
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

    static func clock(_ c: DateComponents) -> String { DayLogic.clock(c) }

    // MARK: - Check-ins

    /// One-shot check-in per check-in block for each of the next `checkInDays` days, skipping blocks
    /// already done or skipped that day and fire dates in the past. Sorted soonest first. Pure.
    static func buildCheckIns(
        for blocks: [Block],
        now: Date,
        completed: (String) -> Set<String>,
        skipped: (String) -> Set<String>,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        var requests: [(Date, UNNotificationRequest)] = []
        for offset in 0..<checkInDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let dayKey = DayLogic.dayKey(day, calendar: calendar)
            let done = completed(dayKey), skip = skipped(dayKey)
            for block in blocks where block.checkIn && block.occurs(on: day, calendar: calendar) {
                guard !done.contains(block.id), !skip.contains(block.id),
                      let end = block.endDate(on: day, calendar: calendar),
                      let fire = calendar.date(byAdding: .minute, value: checkInDelayMinutes, to: end),
                      fire > now else { continue }
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let content = UNMutableNotificationContent()
                content.title = "\(block.label) ended"
                content.body = "Did it happen?"
                content.sound = .default
                content.categoryIdentifier = checkInCategoryID
                content.userInfo = [blockIDKey: block.id, dayKeyKey: dayKey]
                content.threadIdentifier = "autopiloto-checkin"
                requests.append((fire, UNNotificationRequest(identifier: checkInIdentifier(block.id, dayKey: dayKey), content: content, trigger: trigger)))
            }
        }
        return requests.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func checkInIdentifier(_ blockID: String, dayKey: String) -> String { "\(checkInPrefix)\(blockID)-\(dayKey)" }

    /// Replaces only the `checkin-*` requests (start notifications and snoozes are untouched).
    /// Keeps the total under `maxPending`: soonest check-ins win, the rest are logged.
    @MainActor
    static func rearmCheckIns(
        for blocks: [Block],
        now: Date = .now,
        completed: (String) -> Set<String>,
        skipped: (String) -> Set<String>,
        calendar: Calendar = .current,
        center: NotificationCenterClient = .live
    ) async -> Int {
        let pending = await center.pendingIdentifiers()
        let stale = pending.filter { $0.hasPrefix(checkInPrefix) }
        center.removePending(stale)
        let room = max(0, maxPending - (pending.count - stale.count))
        let wanted = buildCheckIns(for: blocks, now: now, completed: completed, skipped: skipped, calendar: calendar)
        if wanted.count > room {
            log.warning("\(wanted.count) check-ins wanted, room for \(room); dropping the latest ones")
        }
        var added = 0
        for request in wanted.prefix(room) {
            do { try await center.add(request); added += 1 } catch {
                log.error("Could not schedule \(request.identifier): \(error.localizedDescription)")
            }
        }
        log.info("Re-armed \(added) check-ins")
        return added
    }

    /// Cancels one day's check-in for a block (after Done / Skip).
    @MainActor
    static func cancelCheckIn(_ blockID: String, dayKey: String, center: NotificationCenterClient = .live) {
        center.removePending([checkInIdentifier(blockID, dayKey: dayKey)])
    }

    // MARK: - Registration

    static func registerCategory(center: UNUserNotificationCenter = .current()) {
        let done = UNNotificationAction(identifier: markDoneActionID, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: snoozeActionID, title: "Snooze 10 min", options: [])
        let skip = UNNotificationAction(identifier: skipTodayActionID, title: "Skip today", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [done, snooze], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: checkInCategoryID, actions: [done, skip], intentIdentifiers: [], options: []),
        ])
    }

    /// Removes every pending start request and re-adds the plan's. Check-ins are re-armed separately.
    @MainActor
    static func register(_ blocks: [Block], center: NotificationCenterClient = .live) async {
        let requests = buildRequests(for: blocks)
        assert(requests.count <= maxPending, "Plan needs \(requests.count) notifications; iOS allows \(maxPending)")
        if requests.count > maxPending {
            log.warning("Plan needs \(requests.count) start notifications; iOS allows \(Self.maxPending)")
        }
        let pending = await center.pendingIdentifiers()
        center.removePending(pending.filter { !$0.hasPrefix(checkInPrefix) && !$0.hasSuffix("-snooze") })
        for request in requests {
            do { try await center.add(request) } catch {
                log.error("Could not schedule \(request.identifier): \(error.localizedDescription)")
            }
        }
        log.info("Scheduled \(requests.count) repeating start notifications")
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
