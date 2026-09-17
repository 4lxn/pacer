import SwiftUI

/// Study, income and the closet share one tab.
struct LifeView: View {
    @Bindable var track: TrackStore
    @Bindable var wardrobe: WardrobeStore
    @Bindable var account: CoachAccount
    @AppStorage("lifeSection") private var section = "track"

    var body: some View {
        NavigationStack {
            Group {
                if section == "closet" {
                    WardrobeView(wardrobe: wardrobe, account: account)
                } else {
                    TrackContent(track: track)
                }
            }
            .navigationTitle(section == "closet" ? "Closet" : "Life")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $section) {
                        Text("Study & income").tag("track")
                        Text("Closet").tag("closet")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
        }
    }
}
