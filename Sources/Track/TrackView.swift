import SwiftUI

struct TrackView: View {
    @Bindable var track: TrackStore
    @State private var now = Date.now
    @State private var topic = ""
    @State private var addingIncome = false
    @State private var editingGoal = false

    private let calendar = Calendar.current
    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    private var currency: String { Locale.current.currency?.identifier ?? "MXN" }

    var body: some View {
        NavigationStack {
            List {
                studySection
                incomeSection
            }
            .navigationTitle("Track")
            .onReceive(tick) { now = $0 }
            .onAppear { now = .now }
            .sheet(isPresented: $addingIncome) { IncomeForm(currency: currency) { track.addIncome(source: $0, amount: $1, on: $2) } }
            .sheet(isPresented: $editingGoal) {
                GoalForm(minutes: track.weeklyStudyGoalMinutes) { track.weeklyStudyGoalMinutes = $0 }
            }
        }
    }

    // MARK: - Study

    private var studySection: some View {
        Section {
            if let since = track.runningSince {
                HStack {
                    VStack(alignment: .leading) {
                        Text(track.runningTopic.isEmpty ? "Studying" : track.runningTopic).fontWeight(.semibold)
                        Text("since \(since.formatted(date: .omitted, time: .shortened)) · \(Int(now.timeIntervalSince(since) / 60)) min")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Button("Stop") { track.stopStudy() }.buttonStyle(.borderedProminent).tint(.red)
                }
            } else {
                HStack {
                    TextField("Topic (optional)", text: $topic)
                    Button("Start") {
                        track.startStudy(topic: topic)
                        topic = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            let week = track.studyMinutes(weekOf: now)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("This week")
                    Spacer()
                    Text("\(hm(week)) / \(hm(track.weeklyStudyGoalMinutes))").monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(week, track.weeklyStudyGoalMinutes)), total: Double(max(track.weeklyStudyGoalMinutes, 1)))
                    .tint(week >= track.weeklyStudyGoalMinutes ? .green : .accentColor)
                Text("Today: \(hm(track.studyMinutes(on: now)))").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { editingGoal = true }
            ForEach(track.recentSessions(limit: 5)) { s in
                HStack {
                    Text(s.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(s.topic)
                    Spacer()
                    Text(hm(s.minutes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .swipeActions { Button(role: .destructive) { track.deleteSession(id: s.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        } header: { Text("Study") }
    }

    // MARK: - Income

    private var incomeSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.formatted(.dateTime.month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                    Text(track.incomeTotal(monthOf: now), format: .currency(code: currency)).font(.title2.weight(.semibold)).monospacedDigit()
                    Text("Year: ") .font(.caption).foregroundStyle(.secondary)
                    + Text(track.incomeTotal(yearOf: now), format: .currency(code: currency)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { addingIncome = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(.bordered)
            }
            ForEach(track.incomeBySource(monthOf: now), id: \.source) { row in
                HStack {
                    Text(row.source)
                    Spacer()
                    Text(row.amount, format: .currency(code: currency)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ForEach(track.incomeEntries(monthOf: now).prefix(8)) { e in
                HStack {
                    Text(e.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    Text(e.source).font(.subheadline)
                    Spacer()
                    Text(e.amount, format: .currency(code: currency)).font(.subheadline).monospacedDigit()
                }
                .swipeActions { Button(role: .destructive) { track.deleteIncome(id: e.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        } header: { Text("Income") }
    }

    private func hm(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

struct IncomeForm: View {
    let currency: String
    let onSave: (String, Decimal, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var amount = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                TextField("Source (salary, freelance…)", text: $source)
                TextField("Amount (\(currency))", text: $amount).keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Add income").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Decimal(string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) {
                            onSave(source, value, date)
                        }
                        dismiss()
                    }
                    .disabled(Decimal(string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) == nil)
                }
            }
        }
    }
}

struct GoalForm: View {
    @State var minutes: Int
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Weekly study goal: \(minutes / 60) h \(minutes % 60) min", value: $minutes, in: 30...3000, step: 30)
            }
            .navigationTitle("Study goal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(minutes); dismiss() } }
            }
        }
    }
}
