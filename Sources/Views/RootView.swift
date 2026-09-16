import SwiftUI

struct RootView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore
    @Bindable var health: HealthStore
    @Bindable var food: FoodStore
    @Bindable var track: TrackStore
    @Bindable var account: CoachAccount
    @Bindable var wardrobe: WardrobeStore
    @Bindable var agent: CoachAgent

    var body: some View {
        TabView {
            DayView(store: store, plan: plan, health: health, track: track)
                .tabItem { Label("Today", systemImage: "sun.max") }
            TrainView(health: health)
                .tabItem { Label("Train", systemImage: "figure.run") }
            FoodView(food: food)
                .tabItem { Label("Food", systemImage: "fork.knife") }
            LifeView(track: track, wardrobe: wardrobe, account: account)
                .tabItem { Label("Life", systemImage: "sparkles") }
            CoachView(store: store, plan: plan, health: health, food: food, track: track, account: account, wardrobe: wardrobe, agent: agent)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: Binding(get: { plan.needsOnboarding }, set: { _ in })) {
            OnboardingView { plan.replace(with: $0) }
        }
        .onChange(of: plan.blocks) { _, blocks in
            Task { await NotificationScheduler.register(blocks) }
        }
    }
}
