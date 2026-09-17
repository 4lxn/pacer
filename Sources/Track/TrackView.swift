import Charts
import SwiftUI

struct TrackContent: View {
    @Bindable var track: TrackStore
    @State private var now = Date.now
    @State private var topic = ""
    @State private var focusMinutes = 25
    @State private var addingIncome = false
    @State private var editingGoal = false
    @State private var editingIncomeGoal = false
    @State private var incomeGoalDraft = ""
    @State private var showAllSessions = false

    private let calendar = Calendar.current
    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    private var currency: String { Locale.current.currency?.identifier ?? "MXN" }

    var body: some View {
        List {
            studySection
            studyHistorySection
            incomeSection
        }
        .onReceive(tick) { now = $0 }
        .onAppear { now = .now }
        .sheet(isPresented: $addingIncome) { IncomeForm(currency: currency) { track.addIncome(source: $0, amount: $1, on: $2) } }
        .sheet(isPresented: $editingGoal) {
            GoalForm(minutes: track.weeklyStudyGoalMinutes) { track.weeklyStudyGoalMinutes = $0 }
        }
        .sheet(isPresented: $showAllSessions) { SessionsList(track: track) }
        .alert("Monthly income goal (\(currency))", isPresented: $editingIncomeGoal) {
            TextField("Amount", text: $incomeGoalDraft).keyboardType(.decimalPad)
            Button("Save") { track.monthlyIncomeGoal = Decimal(string: incomeGoalDraft.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Study

    private var studySection: some View {
        Section {
            if let since = track.runningSince {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.runningTopic.isEmpty ? "Studying" : track.runningTopic).fontWeight(.semibold)
                            Text("since \(since.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(since, style: .timer).font(.title2.weight(.semibold).monospacedDigit())
                    }
                    if let until = track.runningUntil {
                        if until > now {
                            ProgressView(timerInterval: since...until, countsDown: false) { EmptyView() } currentValueLabel: {
                                Text("focus ends in \(Text(until, style: .timer))")
                            }
                            .tint(.accentColor)
                        } else {
                            Label("Focus block done — take five, then stop or keep going.", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                        }
                    }
                    Button("Stop") { track.stopStudy(); Task { NotificationScheduler.cancelFocusEnd() } }
                        .buttonStyle(.glassProminent).tint(.red).frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
            } else {
                TextField("Topic (optional)", text: $topic)
                HStack {
                    Picker("Focus", selection: $focusMinutes) {
                        Text("25 min").tag(25); Text("50 min").tag(50); Text("Open").tag(0)
                    }
                    .pickerStyle(.segmented)
                    Button("Start") {
                        let minutes = focusMinutes > 0 ? focusMinutes : nil
                        track.startStudy(topic: topic, focusMinutes: minutes)
                        if let until = track.runningUntil { Task { await NotificationScheduler.scheduleFocusEnd(at: until, topic: topic) } }
                        topic = ""
                    }
                    .buttonStyle(.glassProminent)
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
                HStack {
                    Text("Today: \(hm(track.studyMinutes(on: now)))")
                    Spacer()
                    let streak = track.studyStreak(now: now)
                    if streak > 0 { Label("\(streak)-day streak", systemImage: "flame.fill").foregroundStyle(.orange) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { editingGoal = true }
        } header: { Text("Study") } footer: { Text("Tap the week bar to change the goal. Focus blocks ping you when time is up; the timer keeps running until you stop.") }
    }

    private var studyHistorySection: some View {
        Section {
            let days = track.studyMinutesByDay(days: 14, now: now)
            Chart {
                ForEach(days, id: \.date) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("min", d.minutes))
                        .foregroundStyle(calendar.isDate(d.date, inSameDayAs: now) ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Daily goal", Double(track.weeklyStudyGoalMinutes) / 7)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day(), centered: true) } }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 110)
            .padding(.vertical, 4)
            let topics = track.studyByTopic(weekOf: now)
            if !topics.isEmpty {
                ForEach(topics, id: \.topic) { t in
                    HStack {
                        Text(t.topic)
                        Spacer()
                        Text(hm(t.minutes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            ForEach(track.recentSessions(limit: 3)) { s in sessionRow(s) }
            if track.sessions.count > 3 {
                Button("All sessions (\(track.sessions.count))") { showAllSessions = true }
            }
        } header: { Text("Last 14 days") }
    }

    private func sessionRow(_ s: StudySession) -> some View {
        HStack {
            Text(s.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(s.topic)
            Spacer()
            Text(hm(s.minutes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .swipeActions { Button(role: .destructive) { track.deleteSession(id: s.id) } label: { Label("Delete", systemImage: "trash") } }
    }

    // MARK: - Income

    private var incomeSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now.formatted(.dateTime.month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                    Text(track.incomeTotal(monthOf: now), format: .currency(code: currency)).font(.title2.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                    Text("Year: \(track.incomeTotal(yearOf: now), format: .currency(code: currency))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { addingIncome = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(.glassProminent)
            }
            let goal = track.monthlyIncomeGoal
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(goal > 0 ? "Goal" : "Set a monthly goal")
                    Spacer()
                    if goal > 0 { Text(goal, format: .currency(code: currency)).monospacedDigit().foregroundStyle(.secondary) }
                }
                if goal > 0 {
                    let total = NSDecimalNumber(decimal: track.incomeTotal(monthOf: now)).doubleValue
                    let target = NSDecimalNumber(decimal: goal).doubleValue
                    ProgressView(value: min(total, target), total: max(target, 1)).tint(total >= target ? .green : .accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { incomeGoalDraft = goal > 0 ? "\(goal)" : ""; editingIncomeGoal = true }
            let months = track.incomeByMonth(months: 6, now: now)
            Chart(months, id: \.month) { m in
                BarMark(x: .value("Month", m.month, unit: .month), y: .value("Amount", NSDecimalNumber(decimal: m.amount).doubleValue))
                    .foregroundStyle(calendar.isDate(m.month, equalTo: now, toGranularity: .month) ? Color.accentColor : Color.accentColor.opacity(0.45))
                    .cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow), centered: true) } }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 100)
            .padding(.vertical, 4)
            ForEach(track.incomeBySource(monthOf: now), id: \.source) { row in
                HStack {
                    Text(row.source)
                    Spacer()
                    Text(row.amount, format: .currency(code: currency)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ForEach(track.incomeEntries(monthOf: now)) { e in
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

/// Every study session, grouped by day.
struct SessionsList: View {
    @Bindable var track: TrackStore
    @Environment(\.dismiss) private var dismiss
    private let calendar = Calendar.current

    var body: some View {
        let grouped = Dictionary(grouping: track.sessions.sorted { $0.start > $1.start }) { calendar.startOfDay(for: $0.start) }
        NavigationStack {
            List {
                ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                    Section {
                        ForEach(grouped[day] ?? []) { s in
                            HStack {
                                Text(s.start.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                                Text(s.topic)
                                Spacer()
                                Text("\(s.minutes) min").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .swipeActions { Button(role: .destructive) { track.deleteSession(id: s.id) } label: { Label("Delete", systemImage: "trash") } }
                        }
                    } header: {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            Spacer()
                            Text("\((grouped[day] ?? []).reduce(0) { $0 + $1.minutes }) min").textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Study sessions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
