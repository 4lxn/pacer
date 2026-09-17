import SwiftUI
import WidgetKit

@main
struct AutopilotoWidgetBundle: WidgetBundle {
    var body: some Widget { NowNextWidget() }
}

struct NowNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "now-next", provider: Provider()) { entry in
            NowNextView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
                .widgetURL(URL(string: "autopiloto://today"))
        }
        .configurationDisplayName("Now / Next")
        .description("What's on right now and what comes next.")
        .supportedFamilies([.systemSmall])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: DayTimeline.Snapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        let block = Block(id: "p", label: "Deep work", kind: .fixed, start: .hm(9, 0), end: .hm(11, 0))
        return Entry(date: .now, snapshot: .init(date: .now, state: .now(block, missed: false), done: 3, total: 12))
    }

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

struct NowNextView: View {
    let entry: Entry
    private var snap: DayTimeline.Snapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch snap.state {
            case .now(let block, let missed):
                eyebrow(missed ? "OVERDUE" : "NOW", color: missed ? .red : .accentColor)
                title(block.label)
                if let start = block.start, let end = block.end {
                    Text("\(DayLogic.clock(start)) – \(DayLogic.clock(end))").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                if !missed, let end = block.endDate(on: entry.date, calendar: .current) {
                    ProgressView(timerInterval: entry.date...max(end, entry.date), countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .tint(.accentColor)
                        .padding(.top, 2)
                }
            case .next(let block):
                eyebrow("NEXT", color: .secondary)
                title(block.label)
                if let start = block.start {
                    Text("at \(DayLogic.clock(start))").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            case .allDone:
                eyebrow("TODAY", color: .accentColor)
                title("All done")
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
            case .nothingLeft:
                eyebrow("TODAY", color: .secondary)
                title("Nothing left")
                Text("See you tomorrow").font(.footnote).foregroundStyle(.secondary)
            case .noPlan:
                eyebrow("AUTOPILOTO", color: .secondary)
                title("Build your day")
                Text("Open the app to start").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if snap.total > 0 {
                Text("\(snap.done) / \(snap.total) done").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(color).tracking(0.5)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
    }
}

#Preview(as: .systemSmall) {
    NowNextWidget()
} timeline: {
    Entry(date: .now, snapshot: .init(date: .now, state: .now(Block(id: "a", label: "Gym", kind: .window, start: .hm(19, 15), end: .hm(20, 15)), missed: false), done: 8, total: 21))
    Entry(date: .now, snapshot: .init(date: .now, state: .now(Block(id: "a", label: "Lunch", kind: .window, start: .hm(13, 0), end: .hm(13, 40)), missed: true), done: 8, total: 21))
    Entry(date: .now, snapshot: .init(date: .now, state: .next(Block(id: "b", label: "Dinner", kind: .window, start: .hm(20, 30), end: .hm(21, 0))), done: 9, total: 21))
    Entry(date: .now, snapshot: .init(date: .now, state: .allDone, done: 21, total: 21))
    Entry(date: .now, snapshot: .init(date: .now, state: .noPlan, done: 0, total: 0))
}
