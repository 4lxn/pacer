import SwiftUI
import UserNotifications

@main
struct AutopilotoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(store: appDelegate.store, plan: appDelegate.plan, health: appDelegate.health)
        }
    }
}

/// Owns the store and the notification delegate so notification actions work even when no
/// SwiftUI scene is alive.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let store = CompletionStore()
    let plan = PlanStore()
    let health = HealthStore()
    private lazy var notificationDelegate = NotificationDelegate(store: store, plan: plan)

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
