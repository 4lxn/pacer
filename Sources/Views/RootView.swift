import SwiftUI

struct RootView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore
    @Bindable var health: HealthStore
    @Bindable var food: FoodStore
    @Bindable var track: TrackStore

    var body: some View {
        TabView {
            DayView(store: store, plan: plan, health: health, track: track)
                .tabItem { Label("Today", systemImage: "sun.max") }
            TrainView(health: health)
                .tabItem { Label("Train", systemImage: "figure.run") }
            FoodView(food: food)
                .tabItem { Label("Food", systemImage: "fork.knife") }
            TrackView(track: track)
                .tabItem { Label("Track", systemImage: "chart.bar") }
            CoachView(store: store, plan: plan, health: health, food: food, track: track)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
        }
        .fullScreenCover(isPresented: Binding(get: { plan.needsOnboarding }, set: { _ in })) {
            OnboardingView { plan.replace(with: $0) }
        }
        .onChange(of: plan.blocks) { _, blocks in
            Task { await NotificationScheduler.register(blocks) }
        }
    }
}
