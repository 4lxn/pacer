import SwiftUI

struct RootView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore
    @Bindable var health: HealthStore
    @Bindable var food: FoodStore

    var body: some View {
        TabView {
            DayView(store: store, plan: plan, health: health)
                .tabItem { Label("Today", systemImage: "sun.max") }
            TrainView(health: health)
                .tabItem { Label("Train", systemImage: "figure.run") }
            FoodView(food: food)
                .tabItem { Label("Food", systemImage: "fork.knife") }
            CoachView(store: store, plan: plan, health: health, food: food)
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
