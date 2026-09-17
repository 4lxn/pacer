import SwiftUI
import WidgetKit

@main
struct AutopilotoWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowNextWidget()
        DayProgressWidget()
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

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: DayTimeline.Snapshot
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

// MARK: - Now / Next

struct NowNextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    private var snap: DayTimeline.Snapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // Lock Screen, one line: "Gym · 12 min left" / "Next: Dinner 20:30"
    private var inline: some View {
        switch snap.state {
        case .now(let block, let missed):
            if missed { return Text("\(Image(systemName: "exclamationmark.circle")) \(block.label) missed") }
            if let end = block.endDate(on: entry.date, calendar: .current) {
                return Text("\(Image(systemName: "circle.fill")) \(block.label) · \(Text(end, style: .timer)) left")
            }
            return Text("\(Image(systemName: "circle.fill")) \(block.label)")
        case .next(let block):
            return Text("\(Image(systemName: "arrow.right.circle")) \(block.label) at \(block.start.map(DayLogic.clock) ?? "")")
        case .allDone: return Text("\(Image(systemName: "checkmark.seal.fill")) All done · \(snap.done)/\(snap.total)")
        case .nothingLeft: return Text("\(Image(systemName: "moon.fill")) Nothing left · \(snap.done)/\(snap.total)")
        case .noPlan: return Text("Pacer: build your day")
        }
    }

    // Lock Screen rectangular: eyebrow, block, time + progress.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch snap.state {
            case .now(let block, let missed):
                Text(missed ? "OVERDUE" : "NOW").font(.caption2.weight(.bold)).widgetAccentable()
                Text(block.label).font(.headline).lineLimit(1)
                if !missed, let end = block.endDate(on: entry.date, calendar: .current) {
                    Text("\(Text(end, style: .timer)) left · \(snap.done)/\(snap.total) done").font(.caption2).foregroundStyle(.secondary)
                } else if let s = block.start, let e = block.end {
                    Text("\(DayLogic.clock(s)) – \(DayLogic.clock(e)) · \(snap.done)/\(snap.total) done").font(.caption2).foregroundStyle(.secondary)
                }
            case .next(let block):
                Text("NEXT").font(.caption2.weight(.bold)).widgetAccentable()
                Text(block.label).font(.headline).lineLimit(1)
                Text("at \(block.start.map(DayLogic.clock) ?? "") · \(snap.done)/\(snap.total) done").font(.caption2).foregroundStyle(.secondary)
            case .allDone:
                Text("TODAY").font(.caption2.weight(.bold)).widgetAccentable()
                Text("All done").font(.headline)
                Text("\(snap.done)/\(snap.total) blocks").font(.caption2).foregroundStyle(.secondary)
            case .nothingLeft:
                Text("TODAY").font(.caption2.weight(.bold)).widgetAccentable()
                Text("Nothing left").font(.headline)
                Text("\(snap.done)/\(snap.total) done · see you tomorrow").font(.caption2).foregroundStyle(.secondary)
            case .noPlan:
                Text("PACER").font(.caption2.weight(.bold)).widgetAccentable()
                Text("Build your day").font(.headline)
                Text("Open the app to start").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            nowBlock
            Spacer(minLength: 0)
            if snap.total > 0 {
                Text("\(snap.done) / \(snap.total) done").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                nowBlock
                Spacer(minLength: 0)
                progressBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                eyebrow("NEXT", color: .secondary)
                if snap.upcoming.isEmpty {
                    Text("Nothing more today").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(snap.upcoming.prefix(3)) { block in upcomingRow(block) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            nowBlock
            progressBar
            Divider()
            eyebrow("NEXT", color: .secondary)
            if snap.upcoming.isEmpty {
                Text("Nothing more today").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(snap.upcoming.prefix(6)) { block in upcomingRow(block) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var nowBlock: some View {
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
            eyebrow("PACER", color: .secondary)
            title("Build your day")
            Text("Open the app to start").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: Double(snap.done), total: Double(max(snap.total, 1))).tint(.accentColor)
            Text("\(snap.done) / \(snap.total) done").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func upcomingRow(_ block: Block) -> some View {
        HStack(spacing: 8) {
            Text(block.start.map(DayLogic.clock) ?? "any").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Text(block.label).font(.subheadline).lineLimit(1)
        }
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(color).tracking(0.5)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Day progress

struct DayProgressView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    private var snap: DayTimeline.Snapshot { entry.snapshot }
    private var fraction: Double { snap.total > 0 ? Double(snap.done) / Double(snap.total) : 0 }

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: fraction) {
                Image(systemName: "sun.max")
            } currentValueLabel: {
                Text("\(snap.done)").font(.title3.weight(.semibold)).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            VStack(spacing: 6) {
                Gauge(value: fraction) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int((fraction * 100).rounded()))%").font(.headline).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.accentColor)
                .scaleEffect(1.4)
                .frame(height: 80)
                Text("\(snap.done) of \(snap.total) done").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if case .now(let block, _) = snap.state { Text(block.label).font(.caption).lineLimit(1) }
                else if case .next(let block) = snap.state { Text("Next: \(block.label)").font(.caption).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension Entry {
    static let sample: Entry = {
        let block = Block(id: "p", label: "Deep work", kind: .fixed, start: .hm(9, 0), end: .hm(11, 0))
        let next = [Block(id: "n1", label: "Lunch", kind: .window, start: .hm(13, 0), end: .hm(13, 40)), Block(id: "n2", label: "Gym", kind: .window, start: .hm(19, 0), end: .hm(20, 0))]
        return Entry(date: .now, snapshot: .init(date: .now, state: .now(block, missed: false), done: 3, total: 12, upcoming: next))
    }()
}

#Preview("Small", as: .systemSmall) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Medium", as: .systemMedium) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Large", as: .systemLarge) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Rectangular", as: .accessoryRectangular) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Inline", as: .accessoryInline) { NowNextWidget() } timeline: { Entry.sample }
#Preview("Circular", as: .accessoryCircular) { DayProgressWidget() } timeline: { Entry.sample }
