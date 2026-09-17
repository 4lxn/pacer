import SwiftUI
import WidgetKit

@main
struct AutopilotoWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowNextWidget()
        DayListWidget()
        DayProgressWidget()
        PacerLiveActivity()
    }
}

/// Now / Next: home screen small · medium · large, Lock Screen rectangular and inline.
struct NowNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "now-next", provider: Provider()) { entry in
            NowNextView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
                .widgetURL(URL(string: "autopiloto://today"))
        }
        .configurationDisplayName("Now / Next")
        .description("What's on right now and what comes next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

/// The whole day at a glance: every block with its state, current one highlighted.
struct DayListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "day-list", provider: Provider()) { entry in
            DayListView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
                .widgetURL(URL(string: "autopiloto://today"))
        }
        .configurationDisplayName("Today's plan")
        .description("Every block of the day, with what's done, what's on and what's left.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Day progress: Lock Screen circular gauge and a small home screen ring.
struct DayProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "day-progress", provider: Provider()) { entry in
            DayProgressView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
                .widgetURL(URL(string: "autopiloto://today"))
        }
        .configurationDisplayName("Day progress")
        .description("How much of today's plan is done.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { .sample }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void) {
        let fallback = placeholder(in: context)
        if context.isPreview { completion(fallback); return }
        Task { @MainActor in completion(Self.entries(now: .now).first ?? fallback) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void) {
        Task { @MainActor in completion(Timeline(entries: Self.entries(now: .now), policy: .atEnd)) }
    }

    /// Reads the same JSON files as the app (App Group) and turns them into timeline entries.
    @MainActor
    static func entries(now: Date) -> [Entry] {
        let plan = PlanStore(), completions = CompletionStore(), days = DayStore()
        let calendar = Calendar.current
        return DayTimeline.snapshots(
            now: now,
            plan: { day in
                DayLogic.effectivePlan(plan.blocks, override: days.override(dayKey: DayLogic.dayKey(day, calendar: calendar)), on: day, calendar: calendar)
            },
            completed: { completions.completed(dayKey: $0) }, skipped: { completions.skipped(dayKey: $0) },
            hasPlan: !plan.needsOnboarding, calendar: calendar
        ).map { Entry(date: $0.date, snapshot: $0) }
    }
}

#Preview("Small", as: .systemSmall) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Medium", as: .systemMedium) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Large", as: .systemLarge) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Rectangular", as: .accessoryRectangular) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Inline", as: .accessoryInline) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Circular", as: .accessoryCircular) { DayProgressWidget() } timeline: { Entry.sample }
#Preview("Day list", as: .systemLarge) { DayListWidget() } timeline: { Entry.sample }
