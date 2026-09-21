import SwiftUI

/// The good kind of dopamine: today's ring, days on pace, and what closed itself. Every reward
/// here is certain — close a block, close the day — never a slot machine.
struct PaceView: View {
    @Bindable var mutator: DayMutator
    @Bindable var metrics: MetricsStore
    @Bindable var plan: PlanStore
    @State private var now = Date.now
    @State private var openDay: Date?
    private var calendar: Calendar { mutator.calendar }

    private var todayScore: Double? { mutator.score(on: now) }
    private var streak: Int { DayLogic.paceStreak(now: now, calendar: calendar) { mutator.score(on: $0) } }
    private var week: MetricsStore.Week { metrics.week(now: now) }
    /// Days on pace out of days with a plan, last 7 including today.
    private var weekPace: (onPace: Int, planned: Int) {
        var on = 0, planned = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now), let s = mutator.score(on: day) else { continue }
            planned += 1
            if s >= DayLogic.paceThreshold { on += 1 }
        }
        return (on, planned)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    grid
                    thisWeek
                }
                .padding().padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Pace")
            .navigationDestination(item: $openDay) { day in DayPlanView(mutator: mutator, plan: plan, date: day, now: now) }
        }
        .onAppear { now = .now }
    }

    private var hero: some View {
        HStack(spacing: 20) {
            DayRing(progress: todayScore ?? 0).frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(streak == 0 ? "No streak yet" : "^[\(streak) day](inflect: true) on pace")
                    .font(.title2.weight(.bold)).contentTransition(.numericText())
                Text(todayLine).font(.subheadline).foregroundStyle(.secondary)
                Text("One free miss a week. Never a red zero.").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .animation(.snappy, value: streak)
    }

    private var todayLine: String {
        guard let s = todayScore else { return "Nothing planned today." }
        if s >= DayLogic.paceThreshold { return "Today is on pace." }
        return "Today \(Int((s * 100).rounded()))% · on pace at \(Int(DayLogic.paceThreshold * 100))%"
    }

    /// Five weeks of days, one cell each, aligned to the calendar's week. Tap a day to open it.
    private var grid: some View {
        let first = calendar.date(byAdding: .day, value: -34, to: now) ?? now
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 5 weeks").font(.headline)
                Spacer()
                Text("\(weekPace.onPace) of \(weekPace.planned) on pace this week").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + i) % 7]).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(0..<35, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: first) ?? first
                    cell(day)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func cell(_ day: Date) -> some View {
        let score = mutator.score(on: day)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let fill: Color = switch score {
        case .none: Color(uiColor: .quaternarySystemFill)
        case .some(let s) where s >= DayLogic.paceThreshold: .green
        case .some(let s) where s > 0: Color.accentColor.opacity(0.25 + 0.5 * s)
        default: Color(uiColor: .tertiarySystemFill)
        }
        return Button { openDay = day } label: {
            RoundedRectangle(cornerRadius: 7)
                .fill(fill)
                .frame(height: 30)
                .overlay {
                    if isToday { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.6), lineWidth: 2) }
                }
                .overlay {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(score.map { $0 >= DayLogic.paceThreshold } == true ? Color.white : Color.secondary)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month())): \(score.map { "\(Int($0 * 100)) percent" } ?? "nothing planned")")
    }

    /// Certain rewards: what got closed, what closed itself, what moved and stayed moved.
    private var thisWeek: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(.headline)
            HStack(spacing: 12) {
                stat("\(week.done)", "closed", "checkmark.circle.fill", .accentColor)
                stat("\(week.healthClosed)", "closed itself", "heart.fill", .pink)
                stat(week.replanKept.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", "moves kept", "arrow.right.circle.fill", .orange)
            }
            if week.healthClosed > 0 {
                Text("^[\(week.healthClosed) block](inflect: true) closed from Apple Health without a tap.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Today's share of the plan as a ring; turns green and shows a check once the day is on pace.
struct DayRing: View {
    let progress: Double
    private var onPace: Bool { progress >= DayLogic.paceThreshold }

    var body: some View {
        ZStack {
            Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 10)
            Circle().trim(from: 0, to: min(1, progress))
                .stroke(onPace ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy(duration: 0.6), value: progress)
            if onPace {
                Image(systemName: "checkmark").font(.title2.weight(.bold)).foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(Int((progress * 100).rounded()))%").font(.headline.monospacedDigit()).contentTransition(.numericText())
            }
        }
        .animation(.snappy, value: onPace)
        .accessibilityLabel("Today \(Int((progress * 100).rounded())) percent")
    }
}

/// Pacer's face: a calm green line while the day is on pace, a restless amber one when something
/// slipped. Same object on the Now card, the widget and the Live Activity.
struct PaceLine: View {
    let behind: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                var path = Path()
                let amplitude = behind ? 5.0 : 2.5
                let speed = behind ? 2.4 : 0.9
                let mid = size.height / 2
                path.move(to: CGPoint(x: 0, y: mid))
                var x = 0.0
                while x <= size.width {
                    path.addLine(to: CGPoint(x: x, y: mid + sin(x / 26 + t * speed) * amplitude))
                    x += 2
                }
                ctx.stroke(path, with: .color(behind ? .orange : .green), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .frame(height: 16)
        .animation(.easeInOut(duration: 0.6), value: behind)
        .accessibilityHidden(true)
    }
}
