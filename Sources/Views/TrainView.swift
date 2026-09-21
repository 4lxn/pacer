import Charts
import SwiftUI

struct TrainView: View {
    @Bindable var health: HealthStore
    let mutator: DayMutator
    var agent: CoachAgent? = nil
    @State private var weightDraft = ""
    @State private var now = Date.now
    @State private var weightRange = 30
    @State private var editingGoal = false
    @State private var goalDraft = ""
    @AppStorage("weightGoalKg") private var weightGoal = 0.0
    @AppStorage("trainGoalRuns") private var goalRuns = 3
    @AppStorage("trainGoalLifts") private var goalLifts = 3
    @AppStorage("trainGoalMinutes") private var goalMinutes = 300
    @State private var editingGoals = false
    @FocusState private var weightFocused: Bool

    private let calendar = Calendar.current

    private var todayWorkouts: [WorkoutSummary] { health.workouts.filter { calendar.isDate($0.start, inSameDayAs: now) } }
    private var week: WeekTotals { WeekTotals.make(health.workouts, weekOf: now, calendar: calendar) }
    private var weeks: [WeekBar] { WeekBar.make(health.workouts, weeks: 8, now: now, calendar: calendar) }
    private var plannedToday: [Block] {
        DayLogic.sorted(mutator.effectivePlan(on: now)).filter { $0.autoComplete == .run || $0.autoComplete == .strength }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !health.isAvailable {
                        card { Text("Apple Health is not available on this device.").foregroundStyle(.secondary) }
                    } else {
                        todayCard
                        weekCard
                        bestsCard
                        weightCard
                        if !health.stepsByDay.isEmpty { stepsCard }
                        recentCard
                        if let error = health.lastError {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Train")
            .toolbar { if let agent { ToolbarItem(placement: .topBarTrailing) { Button { agent.queued = "How is my training week going, and what should I do next?" } label: { Label("Ask Pacer", systemImage: "sparkles") } } } }
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(isPresented: $editingGoals) { TrainGoalsForm(runs: $goalRuns, lifts: $goalLifts, minutes: $goalMinutes) }
            .alert("Weight goal (kg)", isPresented: $editingGoal) {
                TextField("kg", text: $goalDraft).keyboardType(.decimalPad)
                Button("Save") { weightGoal = Double(goalDraft.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func reload() async {
        now = .now
        #if DEBUG
        if CoachAccount.screenshotMode != nil { health.seedForScreenshots(now: now, calendar: calendar); return }
        #endif
        if !health.isAuthorized { await health.requestAuthorization() }
        await health.refresh(now: now, calendar: calendar)
    }

    // MARK: - Today

    private var todayCard: some View {
        card {
            Text("Today").font(.headline)
            let readiness = Readiness.line(sleepMinutes: health.sleepLastNightMinutes, restingHR: health.restingHeartRate)
            Label(readiness.text, systemImage: readiness.good ? "bolt.heart.fill" : "tortoise.fill")
                .font(.subheadline).foregroundStyle(readiness.good ? Color.green : Color.orange)
            HStack(spacing: 0) {
                stat("\(health.stepsToday.formatted())", "steps")
                stat(health.sleepLastNightMinutes.map { "\($0 / 60)h \($0 % 60)m" } ?? "—", "sleep")
                stat(health.restingHeartRate.map { "\($0)" } ?? "—", "resting HR")
            }
            if !plannedToday.isEmpty {
                Divider()
                ForEach(plannedToday) { block in
                    let status = block.status(now: now, completed: mutator.completions.completed(dayKey: mutator.dayKey(now)),
                                              skipped: mutator.completions.skipped(dayKey: mutator.dayKey(now)), calendar: calendar)
                    HStack(spacing: 10) {
                        Image(systemName: status == .done ? "checkmark.circle.fill" : block.autoComplete == .run ? "figure.run" : "dumbbell")
                            .foregroundStyle(status == .done ? Color.accentColor : .secondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.label).fontWeight(.medium)
                            Text([block.start.map(DayLogic.clock), block.note(on: now, calendar: calendar)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(status == .done ? "done" : status == .missed ? "missed" : "planned")
                            .font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                            .foregroundStyle(status == .missed ? .red : .secondary)
                    }
                }
            }
            if !todayWorkouts.isEmpty {
                Divider()
                ForEach(todayWorkouts) { workoutRow($0) }
            } else if plannedToday.isEmpty {
                Text("No workouts yet. Garmin Connect: More → Settings → Connected Apps → Apple Health.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #if DEBUG
            Button("Add test run") { Task { await health.addTestRun() } }.font(.caption)
            #endif
        }
    }

    // MARK: - Week + 8 weeks

    private var weekCard: some View {
        card {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Button("Goals") { editingGoals = true }.font(.subheadline).buttonStyle(.glass).controlSize(.small)
            }
            HStack(spacing: 0) {
                goalStat(week.runs, goalRuns, "runs")
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", week.runKilometers)).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                    Text("km").font(.caption).foregroundStyle(.secondary)
                    Color.clear.frame(width: 44, height: 4)
                }
                .frame(maxWidth: .infinity)
                goalStat(week.lifts, goalLifts, "lifts")
                goalStat(week.minutes, goalMinutes, "min")
            }
            Divider()
            Text("Last 8 weeks · minutes").font(.subheadline).foregroundStyle(.secondary)
            Chart(weeks) { bar in
                BarMark(x: .value("Week", bar.weekStart, unit: .weekOfYear), y: .value("Run", bar.runMinutes))
                    .foregroundStyle(by: .value("Kind", "Run"))
                BarMark(x: .value("Week", bar.weekStart, unit: .weekOfYear), y: .value("Strength", bar.strengthMinutes))
                    .foregroundStyle(by: .value("Kind", "Strength"))
                BarMark(x: .value("Week", bar.weekStart, unit: .weekOfYear), y: .value("Other", bar.otherMinutes))
                    .foregroundStyle(by: .value("Kind", "Other"))
            }
            .chartForegroundStyleScale(["Run": Color.accentColor, "Strength": Color.orange, "Other": Color.gray.opacity(0.5)])
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true) } }
            .chartLegend(position: .bottom, spacing: 6)
            .frame(height: 150)
            .animation(.snappy, value: weeks)
        }
    }

    // MARK: - Weight

    private var weightCard: some View {
        let samples = health.weights.filter { $0.date >= calendar.date(byAdding: .day, value: -weightRange, to: now)! }
        let average = WeightStats.movingAverage(samples, calendar: calendar)
        return card {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight").font(.headline)
                Spacer()
                Picker("Range", selection: $weightRange) { Text("30 d").tag(30); Text("90 d").tag(90) }
                    .pickerStyle(.segmented).frame(width: 120)
            }
            HStack(spacing: 0) {
                stat(health.weights.last.map { String(format: "%.1f", $0.kg) } ?? "—", "latest")
                stat(WeightStats.weeklyChange(health.weights, now: now, calendar: calendar).map { String(format: "%+.1f", $0) } ?? "—", "kg / week")
                Button { goalDraft = weightGoal > 0 ? String(format: "%.1f", weightGoal) : ""; editingGoal = true } label: {
                    stat(weightGoal > 0 ? String(format: "%.1f", weightGoal) : "set", "goal")
                }
                .buttonStyle(.plain)
                if weightGoal > 0, let last = health.weights.last {
                    stat(String(format: "%.1f", last.kg - weightGoal), "to go")
                }
            }
            if samples.count >= 2 {
                Chart {
                    ForEach(samples) { s in
                        PointMark(x: .value("Date", s.date), y: .value("kg", s.kg)).foregroundStyle(Color.accentColor.opacity(0.35)).symbolSize(20)
                    }
                    ForEach(average) { s in
                        LineMark(x: .value("Date", s.date), y: .value("7-day avg", s.kg)).foregroundStyle(Color.accentColor).interpolationMethod(.catmullRom)
                    }
                    if weightGoal > 0 {
                        RuleMark(y: .value("Goal", weightGoal)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) { Text("goal").font(.caption2).foregroundStyle(.green) }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
                .animation(.snappy, value: weightRange)
            } else {
                Text("Log two weigh-ins to see the trend.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("kg", text: $weightDraft)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: 100)
                Button("Log weight") {
                    guard let kg = Double(weightDraft.replacingOccurrences(of: ",", with: ".")), kg > 20, kg < 300 else { return }
                    weightDraft = ""; weightFocused = false
                    Task { await health.saveWeight(kg: kg) }
                }
                .buttonStyle(.glassProminent)
                .disabled(weightDraft.isEmpty)
            }
        }
    }

    private func goalStat(_ value: Int, _ goal: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                .foregroundStyle(goal > 0 && value >= goal ? Color.green : Color.primary)
            Text(goal > 0 ? "\(label) / \(goal)" : label).font(.caption).foregroundStyle(.secondary)
            if goal > 0 {
                ProgressView(value: Double(min(value, goal)), total: Double(goal)).tint(value >= goal ? .green : AppSection.train.tint).frame(width: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bestsCard: some View {
        let b = TrainingBests.make(health.workouts, calendar: calendar)
        return card {
            Text("Bests · 8 weeks").font(.headline)
            HStack(spacing: 0) {
                stat(b.fastest5kPace.map(WorkoutSummary.pace) ?? "—", "5 km pace")
                stat(b.longestRunKm.map { String(format: "%.1f km", $0) } ?? "—", "longest run")
                stat(b.longestSessionMinutes.map { "\($0) min" } ?? "—", "longest")
                stat(b.biggestWeekMinutes.map { "\($0) min" } ?? "—", "best week")
            }
        }
    }

    // MARK: - Steps

    private var stepsCard: some View {
        card {
            HStack {
                Text("Steps · 7 days").font(.headline)
                Spacer()
                let avg = health.stepsByDay.map(\.steps).reduce(0, +) / max(health.stepsByDay.count, 1)
                Text("avg \(avg.formatted())").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Chart(health.stepsByDay, id: \.date) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                    .foregroundStyle(calendar.isDate(day.date, inSameDayAs: now) ? Color.accentColor : Color.accentColor.opacity(0.45))
                    .cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true) } }
            .frame(height: 110)
        }
    }

    // MARK: - Recent

    private var recentCard: some View {
        let recent = health.workouts.filter { !calendar.isDate($0.start, inSameDayAs: now) }.prefix(10)
        return card {
            Text("Recent workouts").font(.headline)
            if recent.isEmpty {
                Text("Nothing in the last 8 weeks.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(recent)) { workoutRow($0, showDay: true) }
        }
    }

    // MARK: - Pieces

    private func workoutRow(_ w: WorkoutSummary, showDay: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(w.activity)).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(w.activity)).fontWeight(.medium)
                Text(details(w, showDay: showDay)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(w.source).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func details(_ w: WorkoutSummary, showDay: Bool) -> String {
        var parts: [String] = []
        if showDay { parts.append(w.start.formatted(.dateTime.weekday(.abbreviated).day())) }
        parts.append(w.start.formatted(date: .omitted, time: .shortened))
        parts.append("\(Int(w.duration / 60)) min")
        if let m = w.distanceMeters, m > 0 { parts.append(String(format: "%.1f km", m / 1000)) }
        if w.activity == .run, let pace = w.paceMinPerKm { parts.append(WorkoutSummary.pace(pace)) }
        if let hr = w.avgHeartRate, hr > 0 { parts.append("\(Int(hr)) bpm") }
        if let kcal = w.kcal, kcal > 0 { parts.append("\(Int(kcal)) kcal") }
        return parts.joined(separator: " · ")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func icon(_ a: WorkoutActivity) -> String {
        switch a {
        case .run: "figure.run"
        case .strength: "dumbbell"
        case .walk: "figure.walk"
        case .cycle: "bicycle"
        case .other: "figure.mixed.cardio"
        }
    }

    private func title(_ a: WorkoutActivity) -> String {
        switch a {
        case .run: "Run"
        case .strength: "Strength"
        case .walk: "Walk"
        case .cycle: "Ride"
        case .other: "Workout"
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}


struct TrainGoalsForm: View {
    @Binding var runs: Int
    @Binding var lifts: Int
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Runs per week: \(runs)", value: $runs, in: 0...14)
                Stepper("Strength sessions per week: \(lifts)", value: $lifts, in: 0...14)
                Stepper("Minutes per week: \(minutes)", value: $minutes, in: 0...2000, step: 30)
            }
            .navigationTitle("Weekly goals").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
