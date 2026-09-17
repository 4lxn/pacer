#if DEBUG
import SwiftUI
import WidgetKit

/// Screenshot mode `widgets`: every widget family rendered at its real size, for a visual check
/// without adding widgets by hand in the simulator.
struct WidgetGallery: View {
    let entry: Entry
    var page = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Widgets · \(page)").font(.title2.weight(.bold))
                if page == 1 {
                    row("Now / Next · small", size: CGSize(width: 158, height: 158), family: .systemSmall) { f in NowNextView(entry: entry, familyOverride: f) }
                    row("Now / Next · medium", size: CGSize(width: 338, height: 158), family: .systemMedium) { f in NowNextView(entry: entry, familyOverride: f) }
                    row("Now / Next · large", size: CGSize(width: 338, height: 354), family: .systemLarge) { f in NowNextView(entry: entry, familyOverride: f) }
                } else {
                    row("Today's plan · medium", size: CGSize(width: 338, height: 158), family: .systemMedium) { f in DayListView(entry: entry, familyOverride: f) }
                    row("Today's plan · large", size: CGSize(width: 338, height: 354), family: .systemLarge) { f in DayListView(entry: entry, familyOverride: f) }
                    HStack(alignment: .top, spacing: 12) {
                        row("Day progress · small", size: CGSize(width: 158, height: 158), family: .systemSmall) { f in DayProgressView(entry: entry, familyOverride: f) }
                        VStack(alignment: .leading, spacing: 12) {
                            lock("rectangular", size: CGSize(width: 172, height: 76), family: .accessoryRectangular) { f in NowNextView(entry: entry, familyOverride: f) }
                            lock("circular", size: CGSize(width: 76, height: 76), family: .accessoryCircular) { f in DayProgressView(entry: entry, familyOverride: f) }
                        }
                    }
                    lock("inline", size: CGSize(width: 300, height: 26), family: .accessoryInline) { f in NowNextView(entry: entry, familyOverride: f) }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func row<V: View>(_ title: String, size: CGSize, family: WidgetFamily, @ViewBuilder content: (WidgetFamily) -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content(family)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .clipped()
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func lock<V: View>(_ title: String, size: CGSize, family: WidgetFamily, @ViewBuilder content: (WidgetFamily) -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content(family)
                .environment(\.colorScheme, .dark)
                .padding(family == .accessoryInline ? 2 : 8)
                .frame(width: size.width, height: size.height)
                .background(Color.black, in: RoundedRectangle(cornerRadius: family == .accessoryCircular ? size.width / 2 : 14))
        }
    }
}
#endif
