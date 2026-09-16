import SwiftUI

struct RootView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore
    @Bindable var health: HealthStore

    var body: some View {
        TabView {
            DayView(store: store, plan: plan, health: health)
                .tabItem { Label("Today", systemImage: "sun.max") }
            TrainView(health: health)
                .tabItem { Label("Train", systemImage: "figure.run") }
            PlanView(plan: plan)
                .tabItem { Label("Plan", systemImage: "list.bullet.rectangle") }
            CoachView(store: store, plan: plan)
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
