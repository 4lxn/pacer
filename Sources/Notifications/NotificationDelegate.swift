import Foundation
import UserNotifications

/// Handles the BLOCK_ACTIONS buttons. Marking done from the notification persists without the
/// app coming to the foreground; the store is @MainActor so the work hops there.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let store: CompletionStore

    init(store: CompletionStore) {
        self.store = store
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let blockID = userInfo[NotificationScheduler.blockIDKey] as? String else { return }

        switch response.actionIdentifier {
        case NotificationScheduler.markDoneActionID:
            await store.markDone(blockID, on: .now)
        case NotificationScheduler.snoozeActionID:
            guard let block = Plan.blocks.first(where: { $0.id == blockID }) else { return }
            try? await center.add(NotificationScheduler.snoozeRequest(for: block))
        default:
            break // plain tap opens the app; nothing else to do
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
