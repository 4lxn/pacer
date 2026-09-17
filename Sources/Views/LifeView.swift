import SwiftUI

/// Focus, Money and Closet each get their own tab; these wrap the content in a stack with the
/// section's title.
struct FocusTab: View {
    @Bindable var track: TrackStore
    var agent: CoachAgent? = nil
    var body: some View {
        NavigationStack { FocusContent(track: track, agent: agent).navigationTitle("Focus") }
    }
}

struct MoneyTab: View {
    @Bindable var track: TrackStore
    var agent: CoachAgent? = nil
    var body: some View {
        NavigationStack { MoneyContent(track: track, agent: agent).navigationTitle("Money") }
    }
}

struct ClosetTab: View {
    @Bindable var wardrobe: WardrobeStore
    @Bindable var account: CoachAccount
    var home: Place? = nil
    var body: some View {
        NavigationStack { WardrobeView(wardrobe: wardrobe, account: account, home: home).navigationTitle("Closet") }
    }
}
