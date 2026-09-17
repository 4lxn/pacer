import Foundation
import UserNotifications

/// Handles the notification buttons. Marking done, skipping or replanning from the lock screen
/// persists without the app coming to the foreground; everything goes through `DayMutator`.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let mutator: DayMutator
    private let calendar: Calendar

    init(mutator: DayMutator, calendar: Calendar = .current) {
        self.mutator = mutator
        self.calendar = calendar
    }

    enum Action: Equatable { case done, snooze, skipToday, replan, undo, open }

    /// Pure decision: which day a notification belongs to. Check-ins carry `dayKey`; start
    /// notifications use the fire date (a 23:56 block confirmed at 00:01 stays on its own day).
    nonisolated static func dayKey(userInfo: [AnyHashable: Any], fireDate: Date, calendar: Calendar) -> String {
        (userInfo[NotificationScheduler.dayKeyKey] as? String) ?? DayLogic.dayKey(fireDate, calendar: calendar)
    }

    nonisolated static func action(for identifier: String) -> Action {
        switch identifier {
        case NotificationScheduler.markDoneActionID: .done
        case NotificationScheduler.snoozeActionID: .snooze
        case NotificationScheduler.skipTodayActionID: .skipToday
        case NotificationScheduler.replanActionID: .replan
        case NotificationScheduler.undoActionID: .undo
        default: .open
        }
    }

    /// The effect of an action, separated from UNNotificationResponse so it can be tested.
    func handle(_ action: Action, blockID: String?, dayKey: String, isCheckIn: Bool = false, center: NotificationCenterClient = .live) async {
        mutator.center = center
        if isCheckIn {
            switch action {
            case .done: mutator.metrics.record(.checkInDone)
            case .skipToday: mutator.metrics.record(.checkInSkip)
            case .replan: mutator.metrics.record(.checkInReplan)
            default: break
            }
        }
        switch action {
        case .done:
            guard let blockID else { return }
            mutator.setDone(blockID, true, dayKey: dayKey, source: .notification)
        case .skipToday:
            guard let blockID else { return }
            mutator.skipToday(blockID, dayKey: dayKey, source: .notification)
        case .replan:
            guard let blockID, let day = mutator.date(dayKey) else { return }
            mutator.replan(blockID, on: day, source: .notification)
        case .undo:
            mutator.undo(source: .notification)
        case .snooze:
            guard let blockID, let block = mutator.plan.block(id: blockID) else { return }
            try? await center.add(NotificationScheduler.snoozeRequest(for: block))
        case .open:
            break
        }
        await mutator.flush()
    }

    func rearm(center: NotificationCenterClient = .live) async {
        mutator.center = center
        await mutator.rearm()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let blockID = userInfo[NotificationScheduler.blockIDKey] as? String
        let action = Self.action(for: response.actionIdentifier)
        let dayKey = Self.dayKey(userInfo: userInfo, fireDate: response.notification.date, calendar: .current)
        let isCheckIn = response.notification.request.content.categoryIdentifier == NotificationScheduler.checkInCategoryID
        await handle(action, blockID: blockID, dayKey: dayKey, isCheckIn: isCheckIn)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
