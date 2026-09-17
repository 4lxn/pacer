import Foundation
import UserNotifications

/// Handles the notification buttons. Marking done or skipping from the lock screen persists
/// without the app coming to the foreground; the store is @MainActor so the work hops there.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let store: CompletionStore
    private let plan: PlanStore
    private let calendar: Calendar

    init(store: CompletionStore, plan: PlanStore, calendar: Calendar = .current) {
        self.store = store
        self.plan = plan
        self.calendar = calendar
    }

    enum Action: Equatable { case done, snooze, skipToday, open }

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
        default: .open
        }
    }

    /// The effect of an action, separated from UNNotificationResponse so it can be tested.
    func handle(_ action: Action, blockID: String, dayKey: String, center: NotificationCenterClient = .live) async {
        switch action {
        case .done:
            store.markDone(blockID, dayKey: dayKey)
            NotificationScheduler.cancelCheckIn(blockID, dayKey: dayKey, center: center)
        case .skipToday:
            store.skip(blockID, dayKey: dayKey)
            NotificationScheduler.cancelCheckIn(blockID, dayKey: dayKey, center: center)
        case .snooze:
            guard let block = plan.block(id: blockID) else { return }
            try? await center.add(NotificationScheduler.snoozeRequest(for: block))
        case .open:
            break
        }
        await rearm(center: center)
    }

    func rearm(center: NotificationCenterClient = .live) async {
        _ = await NotificationScheduler.rearmCheckIns(
            for: plan.blocks, completed: { store.completed(dayKey: $0) }, skipped: { store.skipped(dayKey: $0) },
            calendar: calendar, center: center
        )
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let blockID = userInfo[NotificationScheduler.blockIDKey] as? String else { return }
        let action = Self.action(for: response.actionIdentifier)
        let fireDate = response.notification.date
        let dayKey = Self.dayKey(userInfo: userInfo, fireDate: fireDate, calendar: .current)
        await handle(action, blockID: blockID, dayKey: dayKey)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
