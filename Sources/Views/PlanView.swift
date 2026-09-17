import SwiftUI

struct PlanView: View {
    @Bindable var plan: PlanStore
    var places: [Place] = [.home]
    @State private var editing: Block?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(DayLogic.sorted(plan.blocks)) { block in
                    Button { editing = block } label: { row(block) }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .trailing) {
                            if !block.isAnchor {
                                Button(role: .destructive) { plan.delete(id: block.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                Button { adding = true } label: { Label("Add block", systemImage: "plus") }
            }
            .sheet(item: $editing) { block in
                BlockEditor(block: block, isNew: false, places: places) { plan.upsert($0) } onDelete: { plan.delete(id: $0) }
            }
            .sheet(isPresented: $adding) {
                BlockEditor(block: Block(id: UUID().uuidString, label: "", kind: .window, start: .hm(12, 0), end: .hm(12, 30)), isNew: true, places: places) { plan.upsert($0) } onDelete: { _ in }
            }
        }
    }

    private func row(_ block: Block) -> some View {
        HStack(spacing: 12) {
            Text(block.start.map(NotificationScheduler.clock) ?? "any")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(block.label.isEmpty ? "Untitled" : block.label)
                    if block.isAnchor { Image(systemName: "anchor").font(.caption).foregroundStyle(.secondary) }
                }
                Text(subtitle(block)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(block.kind.rawValue).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule()).foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ block: Block) -> String {
        var parts: [String] = []
        if let end = block.end { parts.append("until \(NotificationScheduler.clock(end))") }
        parts.append(Weekdays.summary(block.weekdays))
        if let match = block.autoComplete { parts.append("auto: \(match.rawValue)") }
        return parts.joined(separator: " · ")
    }
}

enum Weekdays {
    static let all: [Int] = [2, 3, 4, 5, 6, 7, 1] // Mon…Sun
    static let short: [Int: String] = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]

    static func summary(_ days: Set<Int>?) -> String {
        guard let days, days.count < 7 else { return "every day" }
        if days == [2, 3, 4, 5, 6] { return "Mon–Fri" }
        if days == [1, 7] { return "weekends" }
        return all.filter(days.contains).compactMap { short[$0] }.joined(separator: " ")
    }
}
