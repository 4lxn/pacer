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
    static let replanActionID = "REPLAN"
    static let checkInPrefix = "checkin-"
    // Moved blocks (one-shot start notification for a replanned block)
    static let movedPrefix = "moved-"
    // Result of a replan done from a notification action; UNDO reverts it
    static let undoCategoryID = "REPLAN_UNDO"
    static let undoActionID = "UNDO"
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

    // MARK: - Check-ins and moved blocks

    /// One-shot check-in per check-in block for each of the next `checkInDays` days, skipping blocks
    /// already done or skipped that day and fire dates in the past, plus one start notification per
    /// moved block (its repeating start fires at the template time, so the new time needs its own).
    /// `plan(day)` is the effective plan for that day. Sorted soonest first. Pure.
    static func buildCheckIns(
        plan: (Date) -> [Block],
        now: Date,
        completed: (String) -> Set<String>,
        skipped: (String) -> Set<String>,
        movedIDs: (String) -> Set<String> = { _ in [] },
        checkIns: Bool = true,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        var requests: [(Date, UNNotificationRequest)] = []
        for offset in 0..<checkInDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let dayKey = DayLogic.dayKey(day, calendar: calendar)
            let done = completed(dayKey), skip = skipped(dayKey), moved = movedIDs(dayKey)
            for block in plan(day) where block.occurs(on: day, calendar: calendar) {
                guard !done.contains(block.id), !skip.contains(block.id) else { continue }
                if checkIns, block.checkIn, let end = block.endDate(on: day, calendar: calendar),
                   let fire = calendar.date(byAdding: .minute, value: checkInDelayMinutes, to: end), fire > now {
                    let content = UNMutableNotificationContent()
                    content.title = "\(block.label) ended"
                    content.body = "Did it happen?"
                    content.sound = .default
                    content.categoryIdentifier = checkInCategoryID
                    content.userInfo = [blockIDKey: block.id, dayKeyKey: dayKey]
                    content.threadIdentifier = "autopiloto-checkin"
                    requests.append((fire, UNNotificationRequest(identifier: checkInIdentifier(block.id, dayKey: dayKey), content: content, trigger: trigger(fire, calendar))))
                }
                if moved.contains(block.id), let fire = block.startDate(on: day, calendar: calendar), fire > now {
                    let content = content(for: block)
                    content.userInfo = [blockIDKey: block.id, dayKeyKey: dayKey]
                    requests.append((fire, UNNotificationRequest(identifier: movedIdentifier(block.id, dayKey: dayKey), content: content, trigger: trigger(fire, calendar))))
                }
            }
        }
        return requests.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func trigger(_ fire: Date, _ calendar: Calendar) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
    }

    static func checkInIdentifier(_ blockID: String, dayKey: String) -> String { "\(checkInPrefix)\(blockID)-\(dayKey)" }
    static func movedIdentifier(_ blockID: String, dayKey: String) -> String { "\(movedPrefix)\(blockID)-\(dayKey)" }
    static func isOneShot(_ identifier: String) -> Bool { identifier.hasPrefix(checkInPrefix) || identifier.hasPrefix(movedPrefix) }

    /// Replaces only the `checkin-*` / `moved-*` requests (start notifications and snoozes are
    /// untouched). Keeps the total under `maxPending`: soonest win, the rest are logged.
    @MainActor
    static func rearmCheckIns(
        plan: (Date) -> [Block],
        now: Date = .now,
        completed: (String) -> Set<String>,
        skipped: (String) -> Set<String>,
        movedIDs: (String) -> Set<String> = { _ in [] },
        checkIns: Bool = true,
        calendar: Calendar = .current,
        center: NotificationCenterClient = .live
    ) async -> Int {
        let pending = await center.pendingIdentifiers()
        let stale = pending.filter(isOneShot)
        center.removePending(stale)
        let room = max(0, maxPending - (pending.count - stale.count))
        let wanted = buildCheckIns(plan: plan, now: now, completed: completed, skipped: skipped, movedIDs: movedIDs, checkIns: checkIns, calendar: calendar)
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

    /// Convenience for a fixed plan (no overrides).
    @MainActor
    static func rearmCheckIns(
        for blocks: [Block],
        now: Date = .now,
        completed: (String) -> Set<String>,
        skipped: (String) -> Set<String>,
        calendar: Calendar = .current,
        center: NotificationCenterClient = .live
    ) async -> Int {
        await rearmCheckIns(plan: { _ in blocks }, now: now, completed: completed, skipped: skipped, calendar: calendar, center: center)
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
        let replan = UNNotificationAction(identifier: replanActionID, title: "Move it later", options: [])
        let undo = UNNotificationAction(identifier: undoActionID, title: "Undo", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [done, snooze], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: checkInCategoryID, actions: [done, replan, skip], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: undoCategoryID, actions: [undo], intentIdentifiers: [], options: []),
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
        center.removePending(pending.filter { !isOneShot($0) && !$0.hasSuffix("-snooze") })
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
