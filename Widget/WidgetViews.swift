import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: DayTimeline.Snapshot
}

// MARK: - Now / Next

struct NowNextView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: Entry
    var familyOverride: WidgetFamily? = nil   // debug gallery
    private var family: WidgetFamily { familyOverride ?? envFamily }
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
            Text(block.label).font(family == .systemLarge ? .subheadline : .footnote).lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(color).tracking(0.5)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Today's plan

struct DayListView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: Entry
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var snap: DayTimeline.Snapshot { entry.snapshot }
    private var calendar: Calendar { .current }

    /// Medium shows the window around now; large shows as much of the day as fits.
    private var rows: [Block] {
        let limit = family == .systemLarge ? 12 : 5
        let blocks = snap.blocks
        guard blocks.count > limit else { return blocks }
        // Start a little before the current/next block so the past isn't the whole widget.
        let anchor = blocks.firstIndex { status($0) == .current || status($0) == .upcoming || status($0) == .missed } ?? 0
        let start = max(0, min(anchor - 1, blocks.count - limit))
        return Array(blocks[start..<min(blocks.count, start + limit)])
    }

    private func status(_ block: Block) -> BlockStatus {
        block.status(now: entry.date, completed: snap.completed, skipped: snap.skipped, calendar: calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 5 : 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(snap.done) / \(snap.total) done").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(snap.done), total: Double(max(snap.total, 1))).tint(.accentColor)
            if snap.blocks.isEmpty {
                Spacer(minLength: 0)
                Text(snap.state == .noPlan ? "Open Pacer to build your day" : "Nothing planned today").font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { block in row(block) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ block: Block) -> some View {
        let st = status(block)
        return HStack(spacing: 8) {
            Image(systemName: st == .done ? "checkmark.circle.fill" : st == .skipped ? "minus.circle" : st == .current ? "circle.inset.filled" : "circle")
                .font(.caption)
                .foregroundStyle(st == .done || st == .current ? Color.accentColor : st == .missed ? .red : .secondary)
            Text(block.start.map(DayLogic.clock) ?? "any")
                .font(.caption.monospacedDigit())
                .foregroundStyle(st == .missed ? .red : .secondary)
                .frame(width: 38, alignment: .leading)
            Text(block.label)
                .font(family == .systemLarge ? .footnote : .caption)
                .fontWeight(st == .current ? .semibold : .regular)
                .strikethrough(st == .done || st == .skipped)
                .foregroundStyle(st == .done || st == .skipped ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if st == .current, let end = block.endDate(on: entry.date, calendar: calendar) {
                Text(end, style: .timer).font(.caption2.monospacedDigit()).foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, family == .systemLarge ? 2 : 0)
        .background(st == .current ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Day progress

struct DayProgressView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: Entry
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? envFamily }
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
        let all = [Block(id: "w", label: "Wake up", kind: .fixed, start: .hm(7, 0), end: .hm(7, 10), isAnchor: true),
                   Block(id: "b", label: "Breakfast", kind: .window, start: .hm(7, 30), end: .hm(8, 0)), block] + next
        return Entry(date: .now, snapshot: .init(date: .now, state: .now(block, missed: false), done: 3, total: 12, upcoming: next, blocks: all, completed: ["w", "b"]))
    }()
}

