import SwiftUI

struct RootView: View {
    @Bindable var store: CompletionStore
    @Bindable var health: HealthStore

    var body: some View {
        TabView {
            DayView(store: store, health: health)
                .tabItem { Label("Today", systemImage: "sun.max") }
            TrainView(health: health)
                .tabItem { Label("Train", systemImage: "figure.run") }
            CoachView(store: store)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
        }
    }
}
