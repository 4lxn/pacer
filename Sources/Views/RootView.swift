import SwiftUI
import WidgetKit

struct RootView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore
    @Bindable var days: DayStore
    @Bindable var mutator: DayMutator
    @Bindable var metrics: MetricsStore
    @Bindable var health: HealthStore
    @Bindable var food: FoodStore
    @Bindable var track: TrackStore
    @Bindable var account: CoachAccount
    @Bindable var wardrobe: WardrobeStore
    @Bindable var agent: CoachAgent
    @State private var selectedTab = RootView.initialTab

    /// Debug-only: `AUTOPILOTO_TAB=coach` opens on that tab (screenshots).
    private static var initialTab: String {
        #if DEBUG
        ProcessInfo.processInfo.environment["AUTOPILOTO_TAB"] ?? "today"
        #else
        "today"
        #endif
    }

    var body: some View {
        #if DEBUG
        if let mode = CoachAccount.screenshotMode, mode.hasPrefix("widgets") {
            WidgetGallery(entry: Entry(date: .now, snapshot: Self.gallerySnapshot(plan: plan, store: store, days: days, mutator: mutator)), page: mode == "widgets2" ? 2 : 1)
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    #if DEBUG
    @MainActor
    private static func gallerySnapshot(plan: PlanStore, store: CompletionStore, days: DayStore, mutator: DayMutator) -> DayTimeline.Snapshot {
        let now = Date.now
        return DayTimeline.snapshot(at: now, blocks: mutator.effectivePlan(on: now), completed: store.completed(on: now), skipped: store.skipped(on: now), hasPlan: !plan.needsOnboarding, calendar: .current)
    }
    #endif

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            DayView(store: store, plan: plan, days: days, mutator: mutator, metrics: metrics, health: health, track: track, account: account)
                .tabItem { Label("Today", systemImage: "sun.max") }.tag("today")
            TrainView(health: health, mutator: mutator)
                .tabItem { Label("Train", systemImage: "figure.run") }.tag("train")
            FoodView(food: food, account: account)
                .tabItem { Label("Food", systemImage: "fork.knife") }.tag("food")
            LifeView(track: track, wardrobe: wardrobe, account: account)
                .tabItem { Label("Life", systemImage: "sparkles") }.tag("life")
            CoachView(store: store, plan: plan, health: health, food: food, track: track, account: account, wardrobe: wardrobe, agent: agent)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }.tag("coach")
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: Binding(get: { plan.needsOnboarding }, set: { _ in })) {
            OnboardingView { blocks, dayEnd in plan.replace(with: blocks); days.dayEnd = dayEnd }
        }
        .onChange(of: plan.blocks) { _, blocks in
            WidgetCenter.shared.reloadAllTimelines()
            Task { await NotificationScheduler.register(blocks) }
        }
        .onOpenURL { url in
            if url.host == "today" { selectedTab = "today" }
        }
    }
}
