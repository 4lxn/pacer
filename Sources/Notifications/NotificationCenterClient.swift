import Foundation
import UserNotifications

/// The four calls the scheduler needs, so tests can assert on identifiers without the real
/// center (which cannot be authorized in a test bundle). Main-actor bound: every caller is.
@MainActor
struct NotificationCenterClient {
    var add: @MainActor (UNNotificationRequest) async throws -> Void
    var pendingIdentifiers: @MainActor () async -> [String]
    var removePending: ([String]) -> Void
    var removeAllPending: () -> Void

    static let live = NotificationCenterClient(
        add: { try await UNUserNotificationCenter.current().add($0) },
        pendingIdentifiers: { await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier) },
        removePending: { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0) },
        removeAllPending: { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
    )
}
