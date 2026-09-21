import SwiftUI

/// Everything about one block today: times, note, last 7 days, and the actions.
struct BlockDetailSheet: View {
    let block: Block
    let now: Date
    @Bindable var mutator: DayMutator
    let onEditPlan: (Block) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var editingTime = false
    @State private var start = Date.now
    @State private var end = Date.now
    @FocusState private var noteFocused: Bool

    private var calendar: Calendar { mutator.calendar }
    private var dayKey: String { mutator.dayKey(now) }
    private var isToday: Bool { calendar.isDate(now, inSameDayAs: mutator.now()) }
    private var dayWord: String { isToday ? "today" : now.formatted(.dateTime.weekday(.abbreviated).day()) }
    private var status: BlockStatus {
        block.status(now: now, completed: mutator.completions.completed(dayKey: dayKey), skipped: mutator.completions.skipped(dayKey: dayKey), calendar: calendar)
    }
    private var isExtra: Bool { mutator.days.override(dayKey: dayKey).extras.contains { $0.id == block.id } }
    private var isMoved: Bool { mutator.days.override(dayKey: dayKey).moved[block.id] != nil }
    private var canMove: Bool { block.kind != .free && !block.isAnchor && status != .done && status != .skipped }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(block.label).font(.title2.weight(.bold))
                            if block.isAnchor { Image(systemName: "anchor").foregroundStyle(.secondary) }
                        }
                        HStack(spacing: 6) {
                            if let s = block.start, let e = block.end {
                                Text("\(DayLogic.clock(s)) – \(DayLogic.clock(e))").monospacedDigit()
                                Text("· \(block.durationMinutes ?? 0) min")
                            } else {
                                Text("Anytime today")
                            }
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            chip(block.kind.rawValue)
                            if isExtra { chip("today only") }
                            if isMoved { chip("moved") }
                            if block.quiet { chip("quiet") }
                            if let weekday = block.note(on: now, calendar: calendar) { chip(weekday) }
                            chip(statusText, tint: status == .missed ? .red : status == .done ? .accentColor : nil)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !isExtra {
                    Section("Last 7 days") {
                        HStack(spacing: 10) {
                            ForEach(DayLogic.history(of: block, days: 7, now: now, completed: { mutator.completions.completed(dayKey: $0) }, skipped: { mutator.completions.skipped(dayKey: $0) }, calendar: calendar), id: \.dayKey) { day in
                                VStack(spacing: 4) {
                                    Circle().fill(color(day.mark)).frame(width: 22, height: 22)
                                        .overlay { if day.mark == .done { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white) } }
                                    Text(weekdayLetter(day.dayKey)).font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(isToday ? "Note for today" : "Note for \(dayWord)") {
                    TextField("What to do in this block…", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($noteFocused)
                        .onChange(of: noteFocused) { _, focused in if !focused { save(note) } }
                }

                Section {
                    if status == .done {
                        Button("Mark not done", systemImage: "arrow.uturn.backward") { mutator.setDone(block.id, false, dayKey: dayKey); dismiss() }
                    } else {
                        Button("Done", systemImage: "checkmark.circle.fill") { mutator.setDone(block.id, true, dayKey: dayKey); dismiss() }
                    }
                    if canMove && mutator.isEditable(now) {
                        if isToday { Button("Move it later today", systemImage: "arrow.right.circle") { mutator.replan(block.id, on: now); dismiss() } }
                        Button(isToday ? "Set today's time…" : "Set the time for \(dayWord)…", systemImage: "clock") { editingTime = true }
                    }
                    if status == .skipped {
                        Button(isToday ? "Back on today's plan" : "Back on the plan for \(dayWord)", systemImage: "arrow.uturn.backward") { mutator.unskip(block.id, on: now); dismiss() }
                    } else if status != .done {
                        Button(isToday ? "Skip today" : "Skip on \(dayWord)", systemImage: "minus.circle") { mutator.skipToday(block.id, dayKey: dayKey); dismiss() }
                    }
                }

                Section {
                    if isExtra {
                        Button(isToday ? "Remove from today" : "Remove from \(dayWord)", systemImage: "trash", role: .destructive) { mutator.removeExtra(block.id, dayKey: dayKey); dismiss() }
                    } else {
                        Button("Edit in the weekly plan", systemImage: "slider.horizontal.3") { onEditPlan(block); dismiss() }
                    }
                }
            }
            .navigationTitle("Block").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(note); dismiss() } } }
            .onAppear {
                note = mutator.days.override(dayKey: dayKey).notes[block.id] ?? ""
                start = block.startDate(on: now, calendar: calendar) ?? now
                end = block.endDate(on: now, calendar: calendar) ?? now
            }
            .sheet(isPresented: $editingTime) { timeSheet }
        }
        .presentationDetents([.medium, .large])
    }

    private var timeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                if let change = mutator.lastChange, !change.undoable { Text(change.summary).foregroundStyle(.red) }
            }
            .navigationTitle(isToday ? "Today's time" : "Time on \(dayWord)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingTime = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        let s = calendar.dateComponents([.hour, .minute], from: start)
                        if case .rejected = mutator.move(block.id, to: .hm(s.hour ?? 0, s.minute ?? 0), on: now) { return }
                        editingTime = false; dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save(_ text: String) { mutator.days.setNote(text, blockID: block.id, dayKey: dayKey) }

    private var statusText: String {
        switch status {
        case .done: "done"
        case .skipped: "skipped"
        case .current: "now"
        case .upcoming: "upcoming"
        case .missed: "missed"
        case .free: "anytime"
        }
    }

    private func chip(_ text: String, tint: Color? = nil) -> some View {
        Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.map { $0.opacity(0.12) } ?? Color(uiColor: .tertiarySystemFill), in: Capsule())
            .foregroundStyle(tint ?? .secondary)
    }

    private func color(_ mark: DayLogic.HistoryMark) -> Color {
        switch mark {
        case .done: .accentColor
        case .skipped: Color(uiColor: .tertiaryLabel)
        case .missed: .red.opacity(0.7)
        case .off: Color(uiColor: .quaternarySystemFill)
        case .pending: Color(uiColor: .tertiarySystemFill)
        }
    }

    private func weekdayLetter(_ dayKey: String) -> String {
        guard let date = mutator.date(dayKey) else { return "" }
        return String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
    }
}

/// "Just for today": a one-off block that never touches the weekly plan.
struct TodayOnlySheet: View {
    let now: Date
    let onAdd: (Block) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var kind: BlockKind = .window
    @State private var start = Date.now
    @State private var end = Date.now.addingTimeInterval(1800)
    @State private var quick = ""
    @FocusState private var labelFocused: Bool
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("gym 7pm 45m", text: $quick).focused($labelFocused)
                        .autocorrectionDisabled()
                        .onChange(of: quick) { _, text in applyQuick(text) }
                } footer: { Text("One line: what, when, how long. The fields below follow.") }
                TextField("What?", text: $label)
                Picker("Kind", selection: $kind) {
                    Text("Window — anytime in range").tag(BlockKind.window)
                    Text("Fixed — notifies at start").tag(BlockKind.fixed)
                    Text("Free — anytime today").tag(BlockKind.free)
                }
                if kind != .free {
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Just for today").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let s = calendar.dateComponents([.hour, .minute], from: start), e = calendar.dateComponents([.hour, .minute], from: max(end, start.addingTimeInterval(300)))
                        let block = Block(id: "today-\(UUID().uuidString.prefix(8))", label: label.trimmingCharacters(in: .whitespaces),
                                          kind: kind, start: kind == .free ? nil : .hm(s.hour ?? 0, s.minute ?? 0), end: kind == .free ? nil : .hm(e.hour ?? 0, e.minute ?? 0))
                        onAdd(block); dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // Default to the next round quarter hour.
                let m = calendar.component(.minute, from: now)
                start = calendar.date(byAdding: .minute, value: (15 - m % 15) % 15, to: now) ?? now
                end = start.addingTimeInterval(1800)
                labelFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The typed line fills label, kind and times; the pickers stay editable.
    private func applyQuick(_ text: String) {
        guard let parsed = QuickAdd.parse(text) else { return }
        label = parsed.label
        if let s = parsed.start, let e = parsed.end {
            kind = .window
            start = calendar.date(bySettingHour: s.hour ?? 0, minute: s.minute ?? 0, second: 0, of: now) ?? start
            end = calendar.date(bySettingHour: e.hour ?? 0, minute: e.minute ?? 0, second: 0, of: now) ?? end
        } else {
            kind = .free
        }
    }
}
