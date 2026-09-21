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
    @State private var askPresented = false

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
            OnboardingView { blocks, dayEnd, picked, home in
                plan.replace(with: blocks); days.dayEnd = dayEnd; sections.replace(picked)
                if let home { days.places.upsert(home) }
            }
        }
        .onChange(of: plan.blocks) { _, blocks in
            WidgetCenter.shared.reloadAllTimelines()
            Task { await NotificationScheduler.register(blocks) }
        }
        .onChange(of: agent.queued) { _, q in if q != nil { openAsk() } }
        .onOpenURL { url in
            guard let host = url.host, let section = AppSection(rawValue: host) else { return }
            if section == .coach { openAsk() } else if sections.isOn(section) { selectedTab = host }
        }
        .sheet(isPresented: $askPresented) { ask }
    }

    /// Ask is a sheet from anywhere; users who keep the Ask tab on get the tab instead.
    private func openAsk() {
        if sections.isOn(.coach) { selectedTab = AppSection.coach.rawValue } else { askPresented = true }
    }

    private var ask: some View {
        CoachView(store: store, plan: plan, health: health, food: food, track: track, account: account, wardrobe: wardrobe, agent: agent, sections: sections)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func view(for section: AppSection) -> some View {
        switch section {
        case .today: DayView(store: store, plan: plan, days: days, mutator: mutator, metrics: metrics, health: health, track: track, account: account, sections: sections, onAsk: openAsk)
        case .pace: PaceView(mutator: mutator, metrics: metrics, plan: plan)
        case .train: TrainView(health: health, mutator: mutator, agent: sections.isOn(.coach) ? agent : nil)
        case .food: FoodView(food: food, account: account, agent: agent)
        case .focus: FocusTab(track: track, agent: sections.isOn(.coach) ? agent : nil)
        case .money: MoneyTab(track: track, agent: sections.isOn(.coach) ? agent : nil)
        case .closet: ClosetTab(wardrobe: wardrobe, account: account, home: days.places.place(id: Place.homeID))
        case .coach: CoachView(store: store, plan: plan, health: health, food: food, track: track, account: account, wardrobe: wardrobe, agent: agent, sections: sections)
        }
    }
}
