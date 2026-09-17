import SwiftUI

struct BlockEditor: View {
    @State var block: Block
    let isNew: Bool
    var places: [Place] = [.home]
    let onSave: (Block) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $block.label)
                    Picker("Kind", selection: $block.kind) {
                        Text("Fixed — notifies at start").tag(BlockKind.fixed)
                        Text("Window — anytime in range").tag(BlockKind.window)
                        Text("Free — anytime today").tag(BlockKind.free)
                    }
                }
                if block.kind != .free {
                    Section("Time") {
                        DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    Picker("Place", selection: Binding(get: { block.place ?? "" }, set: { block.place = $0.isEmpty ? nil : $0 })) {
                        Text("Wherever I am").tag("")
                        ForEach(places) { Text($0.name).tag($0.id) }
                    }
                } footer: { Text("Travel time to and from the place is kept free around the block. Add places in Settings.") }
                Section("Days") {
                    HStack {
                        ForEach(Weekdays.all, id: \.self) { day in
                            let on = block.weekdays?.contains(day) ?? true
                            Button(Weekdays.short[day]?.prefix(1).description ?? "") { toggle(day) }
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(on ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: Circle())
                                .foregroundStyle(on ? .white : .secondary)
                                .buttonStyle(.plain)
                                .accessibilityLabel(Weekdays.short[day] ?? "")
                                .accessibilityValue(on ? "on" : "off")
                        }
                    }
                }
                Section {
                    if block.kind != .free && !block.isAnchor {
                        Toggle("Check-in 5 min after it ends", isOn: $block.checkIn)
                    }
                    Toggle("Anchor (never droppable, breaks through Focus)", isOn: $block.isAnchor)
                    Picker("Auto-complete", selection: autoBinding) {
                        Text("Off").tag("")
                        Text("Run").tag(WorkoutMatch.run.rawValue)
                        Text("Strength").tag(WorkoutMatch.strength.rawValue)
                        Text("Study session (20+ min)").tag(WorkoutMatch.study.rawValue)
                    }
                }
                if !isNew && !block.isAnchor {
                    Section {
                        Button("Delete block", role: .destructive) {
                            onDelete(block.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New block" : "Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = block
                        if saved.kind == .free { saved.start = nil; saved.end = nil }
                        if saved.label.trimmingCharacters(in: .whitespaces).isEmpty { saved.label = "Untitled" }
                        onSave(saved)
                        dismiss()
                    }
                }
            }
            .onChange(of: block.kind) { _, kind in
                if kind != .free, block.start == nil { block.start = .hm(12, 0); block.end = .hm(12, 30) }
                if kind == .free || block.isAnchor { block.checkIn = false }
            }
            .onChange(of: block.isAnchor) { _, anchor in if anchor { block.checkIn = false } }
        }
    }

    private var startBinding: Binding<Date> { timeBinding(\.start, fallback: .hm(12, 0)) }
    private var endBinding: Binding<Date> { timeBinding(\.end, fallback: .hm(12, 30)) }

    private func timeBinding(_ key: WritableKeyPath<Block, DateComponents?>, fallback: DateComponents) -> Binding<Date> {
        Binding(
            get: {
                let c = block[keyPath: key] ?? fallback
                return calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: .now) ?? .now
            },
            set: { date in
                block[keyPath: key] = .hm(calendar.component(.hour, from: date), calendar.component(.minute, from: date))
            }
        )
    }

    private var autoBinding: Binding<String> {
        Binding(get: { block.autoComplete?.rawValue ?? "" }, set: { block.autoComplete = WorkoutMatch(rawValue: $0) })
    }

    private func toggle(_ day: Int) {
        var days = block.weekdays ?? Set(Weekdays.all)
        if days.contains(day) { if days.count > 1 { days.remove(day) } } else { days.insert(day) }
        block.weekdays = days.count == 7 ? nil : days
    }
}
