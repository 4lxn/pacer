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
    @Bindable var sections: SectionStore
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
            ForEach(sections.enabled) { section in
                view(for: section)
                    .tabItem { Label(section.title, systemImage: section.symbol) }
                    .tag(section.rawValue)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: Binding(get: { plan.needsOnboarding }, set: { _ in })) {
            OnboardingView { blocks, dayEnd, picked in plan.replace(with: blocks); days.dayEnd = dayEnd; sections.replace(picked) }
        }
        .onChange(of: plan.blocks) { _, blocks in
            WidgetCenter.shared.reloadAllTimelines()
            Task { await NotificationScheduler.register(blocks) }
        }
        .onChange(of: agent.queued) { _, q in if q != nil { selectedTab = AppSection.coach.rawValue } }
        .onOpenURL { url in
            if let host = url.host, AppSection(rawValue: host) != nil { selectedTab = host }
        }
    }

    @ViewBuilder
    private func view(for section: AppSection) -> some View {
        switch section {
        case .today: DayView(store: store, plan: plan, days: days, mutator: mutator, metrics: metrics, health: health, track: track, account: account, sections: sections)
        case .train: TrainView(health: health, mutator: mutator)
        case .food: FoodView(food: food, account: account, agent: agent)
        case .focus: FocusTab(track: track)
        case .money: MoneyTab(track: track)
        case .closet: ClosetTab(wardrobe: wardrobe, account: account)
        case .coach: CoachView(store: store, plan: plan, health: health, food: food, track: track, account: account, wardrobe: wardrobe, agent: agent, sections: sections)
        }
    }
}
