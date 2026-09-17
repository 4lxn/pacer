import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct AutopilotoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(store: appDelegate.store, plan: appDelegate.plan, days: appDelegate.days, mutator: appDelegate.mutator,
                     health: appDelegate.health, food: appDelegate.food, track: appDelegate.track, account: appDelegate.account,
                     wardrobe: appDelegate.wardrobe, agent: appDelegate.agent)
        }
    }
}

/// Owns the stores and the notification delegate so notification actions work even when no
/// SwiftUI scene is alive.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let rearmTaskID = "com.alan.autopiloto.rearm"

    let store = CompletionStore()
    let plan = PlanStore()
    let health = HealthStore()
    let food = FoodStore()
    let track = TrackStore()
    let account = CoachAccount()
    let wardrobe = WardrobeStore()
    let days = DayStore()
    lazy var mutator = DayMutator(plan: plan, completions: store, days: days)
    lazy var agent = CoachAgent(
        chat: CoachChatStore(),
        tools: CoachTools(plan: plan, completions: store, food: food, wardrobe: wardrobe, health: health, track: track, mutator: mutator)
    )
    private(set) lazy var notificationDelegate = NotificationDelegate(mutator: mutator)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        // Screenshots / UI checks: seed the sample plan so onboarding doesn't show.
        if CoachAccount.screenshotMode != nil, plan.needsOnboarding { plan.replace(with: Plan.blocks) }
        if CoachAccount.screenshotMode == "replan" {
            let missed = DayLogic.sorted(mutator.effectivePlan(on: .now)).filter { $0.status(now: .now, completed: [], calendar: .current) == .missed && $0.kind != .free && !$0.isAnchor }
            if let block = missed.last { mutator.replan(block.id, on: .now) }
        }
        #endif
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        NotificationScheduler.registerCategory(center: center)

        // Backstop for check-in re-arming when the app isn't opened and no notification is acted on.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.rearmTaskID, using: nil) { [weak self] task in
            guard let self else { task.setTaskCompleted(success: false); return }
            let work = Task { @MainActor in
                await self.notificationDelegate.rearm()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel(); task.setTaskCompleted(success: false) }
        }
        Self.scheduleRearm()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Self.scheduleRearm()
    }

    static func scheduleRearm() {
        let request = BGAppRefreshTaskRequest(identifier: rearmTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
