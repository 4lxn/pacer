import SwiftUI
import UserNotifications

@main
struct AutopilotoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DayView(store: appDelegate.store)
        }
    }
}

/// Owns the store and the notification delegate so notification actions work even when no
/// SwiftUI scene is alive.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let store = CompletionStore()
    private lazy var notificationDelegate = NotificationDelegate(store: store)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        NotificationScheduler.registerCategory(center: center)
        return true
    }
}
