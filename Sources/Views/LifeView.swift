import SwiftUI

/// Focus, Money and Closet each get their own tab; these wrap the content in a stack with the
/// section's title.
struct FocusTab: View {
    @Bindable var track: TrackStore
    var body: some View {
        NavigationStack { TrackContent(track: track, part: .focus).navigationTitle("Focus") }
    }
}

struct MoneyTab: View {
    @Bindable var track: TrackStore
    var body: some View {
        NavigationStack { TrackContent(track: track, part: .money).navigationTitle("Money") }
    }
}

struct ClosetTab: View {
    @Bindable var wardrobe: WardrobeStore
    @Bindable var account: CoachAccount
    var body: some View {
        NavigationStack { WardrobeView(wardrobe: wardrobe, account: account).navigationTitle("Closet") }
    }
}
