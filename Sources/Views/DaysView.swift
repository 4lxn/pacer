import SwiftUI

/// Month grid → any day's plan. Past days show their score; edited days a dot.
struct DaysView: View {
    @Bindable var mutator: DayMutator
    @Bindable var plan: PlanStore
    let now: Date
    @State private var month: Date
    @State private var selected: Date?
    private let calendar = Calendar.current

    init(mutator: DayMutator, plan: PlanStore, now: Date) {
        self.mutator = mutator
        self.plan = plan
        self.now = now
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: now)?.start ?? now)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                grid
                legend
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Days")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { day in DayPlanView(mutator: mutator, plan: plan, date: day, now: now) }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.buttonStyle(.glass)
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.semibold))
                .contentTransition(.numericText())
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }.buttonStyle(.glass)
        }
        .animation(.snappy, value: month)
    }

    private var grid: some View {
        let weeks = CalendarMonth.weeks(of: month, calendar: calendar)
        let symbols = CalendarMonth.weekdaySymbols(calendar: calendar)
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(symbols, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }
            ForEach(weeks.indices, id: \.self) { w in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        if let day = weeks[w][i] { cell(day) } else { Color.clear.frame(height: 52) }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func cell(_ day: Date) -> some View {
        let key = mutator.dayKey(day)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let isPast = day < calendar.startOfDay(for: now)
        let score = isPast || isToday ? DayLogic.dayScore(mutator.effectivePlan(on: day), completed: mutator.completions.completed(dayKey: key), skipped: mutator.completions.skipped(dayKey: key)) : nil
        let edited = !mutator.days.override(dayKey: key).isEmpty
        return Button { selected = day } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                ZStack {
                    if let score {
                        Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(width: 22, height: 4)
                            .overlay(alignment: .leading) { Capsule().fill(score >= 0.8 ? Color.green : Color.accentColor).frame(width: 22 * score, height: 4) }
                    } else if edited {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    } else {
                        Color.clear.frame(height: 4)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isToday ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(score.map { "\(Int($0 * 100)) percent done" } ?? (edited ? "edited" : ""))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label { Text("done share") } icon: { Capsule().fill(Color.accentColor).frame(width: 14, height: 4) }
            Label { Text("edited day") } icon: { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func shift(_ months: Int) {
        if let m = calendar.date(byAdding: .month, value: months, to: month) { month = m }
    }
}

/// Weeks of a month as 7-wide rows (nil = padding), respecting the calendar's first weekday.
enum CalendarMonth {
    static func weeks(of month: Date, calendar: Calendar) -> [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var days: [Date] = []
        var d = interval.start
        while d < interval.end { days.append(d); d = calendar.date(byAdding: .day, value: 1, to: d)! }
        let lead = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead) + days.map(Optional.some)
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let s = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(s[start...] + s[..<start])
    }
}

/// One day's plan, editable: move, skip, one-off blocks, notes, reset.
struct DayPlanView: View {
    @Bindable var mutator: DayMutator
    @Bindable var plan: PlanStore
    let date: Date
    let now: Date
    @State private var detail: Block?
    @State private var editingBlock: Block?
    @State private var adding = false
    private let calendar = Calendar.current

    private var clock: Date { mutator.clock(for: date) }
    private var dayKey: String { mutator.dayKey(date) }
    private var blocks: [Block] { DayLogic.sorted(mutator.effectivePlan(on: date)) }
    private var override: DayOverride { mutator.days.override(dayKey: dayKey) }
    private var isToday: Bool { calendar.isDate(date, inSameDayAs: now) }
    private var legs: [String: (minutes: Int, from: String)] { DayLogic.travelLegs(blocks, places: mutator.days.places, overrides: mutator.days.legMinutes(dayKey: dayKey)) }

    var body: some View {
        List {
            Section {
                let done = mutator.completions.completed(dayKey: dayKey), skipped = mutator.completions.skipped(dayKey: dayKey)
                let counted = blocks.filter { !skipped.contains($0.id) }
                HStack {
                    Text(isToday ? "Today" : date < now ? "Past day" : "Upcoming")
                    Spacer()
                    Text("\(counted.filter { done.contains($0.id) }.count) / \(counted.count) done").foregroundStyle(.secondary).monospacedDigit()
                }
                if !override.isEmpty {
                    Text("\(override.moved.count) moved · \(override.extras.count) one-off · \(override.notes.count) notes").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(blocks) { block in
                    let status = block.status(now: clock, completed: mutator.completions.completed(dayKey: dayKey), skipped: mutator.completions.skipped(dayKey: dayKey), calendar: calendar)
                    Button { detail = block } label: {
                        HStack(spacing: 12) {
                            Image(systemName: status == .done ? "checkmark.circle.fill" : status == .skipped ? "minus.circle" : "circle")
                                .foregroundStyle(status == .done ? Color.accentColor : .secondary)
                            Text(block.start.map(DayLogic.clock) ?? "any").font(.subheadline.monospacedDigit())
                                .foregroundStyle(status == .missed ? .red : .secondary).frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.label).strikethrough(status == .done || status == .skipped)
                                    .foregroundStyle(status == .done || status == .skipped ? Color.secondary : Color.primary)
                                let sub = [mutator.days.places.name(id: block.place), override.notes[block.id] ?? block.note(on: date, calendar: calendar)].compactMap { $0 }
                                if !sub.isEmpty { Text(sub.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                                if let leg = legs[block.id] {
                                    Text("\(leg.minutes) min from \(leg.from) · leave by \(block.start.map { DayLogic.clock(DayLogic.components(minutes: DayLogic.minutes($0) - leg.minutes)) } ?? "")")
                                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                                }
                            }
                            Spacer()
                            if override.extras.contains(where: { $0.id == block.id }) { chip("one-off") }
                            else if override.moved[block.id] != nil { chip("moved") }
                            if status == .skipped { chip("skipped") }
                        }
                        .foregroundStyle(Color.primary)
                    }
                }
            } header: {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            } footer: {
                Text(mutator.isEditable(date) ? "Tap a block to move it, skip it or add a note for this day. Changes here never touch the weekly plan." : "A past day: you can still mark things done or skipped.")
            }
            if mutator.isEditable(date) && !override.isEmpty {
                Section { Button("Reset to the weekly plan", systemImage: "arrow.counterclockwise", role: .destructive) { mutator.resetDay(date) } }
            }
        }
        .navigationTitle(date.formatted(.dateTime.day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mutator.isEditable(date) {
                Button { adding = true } label: { Label("Add for this day", systemImage: "plus") }
            }
        }
        .sheet(item: $detail) { block in
            BlockDetailSheet(block: block, now: clock, mutator: mutator) { editingBlock = $0 }
        }
        .sheet(item: $editingBlock) { block in
            BlockEditor(block: plan.block(id: block.id) ?? block, isNew: false, places: mutator.days.places.list) { plan.upsert($0) } onDelete: { plan.delete(id: $0) }
        }
        .sheet(isPresented: $adding) { TodayOnlySheet(now: clock) { mutator.addExtra($0, dayKey: dayKey) } }
        .animation(.snappy, value: override)
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule()).foregroundStyle(.secondary)
    }
}
