import Charts
import SwiftUI

struct TrainView: View {
    @Bindable var health: HealthStore
    @State private var weightDraft = ""
    @State private var now = Date.now

    private let calendar = Calendar.current

    private var todayWorkouts: [WorkoutSummary] { health.workouts.filter { calendar.isDate($0.start, inSameDayAs: now) } }
    private var week: WeekTotals { WeekTotals.make(health.workouts, weekOf: now, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Train").font(.title2.weight(.semibold))
                if !health.isAvailable {
                    card { Text("Apple Health is not available on this device.").foregroundStyle(.secondary) }
                } else {
                    todayCard
                    weekCard
                    weightCard
                    if let error = health.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        now = .now
        if !health.isAuthorized { await health.requestAuthorization() }
        await health.refresh(now: now, calendar: calendar)
    }

    // MARK: - Cards

    private var todayCard: some View {
        card {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Text("\(health.stepsToday) steps").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            if todayWorkouts.isEmpty {
                Text("No workouts yet.").foregroundStyle(.secondary)
                Text("Garmin Connect: More → Settings → Connected Apps → Apple Health. Strava: Settings → Applications, Services and Devices → Health.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(todayWorkouts) { workoutRow($0) }
            }
            #if DEBUG
            Button("Add test run") { Task { await health.addTestRun() } }
                .font(.caption)
            #endif
        }
    }

    private var weekCard: some View {
        card {
            Text("This week").font(.headline)
            HStack(spacing: 0) {
                stat("\(week.runs)", "runs")
                stat(String(format: "%.1f", week.runKilometers), "km")
                stat("\(week.lifts)", "lifts")
                stat("\(week.minutes)", "min")
            }
            let earlier = health.workouts.filter { !calendar.isDate($0.start, inSameDayAs: now) }
            if !earlier.isEmpty {
                Divider()
                ForEach(earlier.prefix(7)) { workoutRow($0, showDay: true) }
            }
        }
    }

    private var weightCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight").font(.headline)
                Spacer()
                if let last = health.weights.last {
                    Text(String(format: "%.1f kg", last.kg)).font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
            if health.weights.count >= 2 {
                Chart(health.weights) { sample in
                    LineMark(x: .value("Date", sample.date), y: .value("kg", sample.kg))
                    PointMark(x: .value("Date", sample.date), y: .value("kg", sample.kg))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
            } else {
                Text("Log two weigh-ins to see the trend.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("kg", text: $weightDraft)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("Log weight") {
                    guard let kg = Double(weightDraft.replacingOccurrences(of: ",", with: ".")), kg > 20, kg < 300 else { return }
                    weightDraft = ""
                    Task { await health.saveWeight(kg: kg) }
                }
                .buttonStyle(.bordered)
                .disabled(weightDraft.isEmpty)
            }
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
        if showDay { parts.append(w.start.formatted(.dateTime.weekday(.abbreviated))) }
        parts.append(w.start.formatted(date: .omitted, time: .shortened))
        parts.append("\(Int(w.duration / 60)) min")
        if let m = w.distanceMeters, m > 0 { parts.append(String(format: "%.1f km", m / 1000)) }
        if let kcal = w.kcal, kcal > 0 { parts.append("\(Int(kcal)) kcal") }
        return parts.joined(separator: " · ")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
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
