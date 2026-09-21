import Charts
import SwiftUI

/// Focus: start a session, watch it in the Dynamic Island, keep subjects and streaks.
struct FocusContent: View {
    @Bindable var track: TrackStore
    var agent: CoachAgent? = nil
    @State private var now = Date.now
    @State private var subjectName = ""
    @State private var focusMinutes = 25
    @State private var showTimer = false
    @State private var editingSubject: Subject?
    @State private var addingSubject = false
    @State private var showAllSessions = false
    @State private var editingGoal = false

    private let calendar = Calendar.current
    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    private let tint = AppSection.focus.tint

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                weekCard
                subjectsCard
                heatMapCard
                recentCard
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onReceive(tick) { now = $0 }
        .onAppear {
            now = .now
            if subjectName.isEmpty { subjectName = track.subjects.first?.name ?? "" }
            #if DEBUG
            if CoachAccount.screenshotMode == "focus-timer", !track.isStudying { start() }
            #endif
        }
        .toolbar { if let agent { ToolbarItem(placement: .topBarTrailing) { Button { agent.queued = "How is my focus going this week, and what should I work on next?" } label: { Label("Ask Pacer", systemImage: "sparkles") } } } }
        .fullScreenCover(isPresented: $showTimer) { FocusTimerView(track: track) }
        .sheet(item: $editingSubject) { s in SubjectForm(subject: s) { track.upsertSubject($0) } onDelete: { track.deleteSubject(id: $0) } }
        .sheet(isPresented: $addingSubject) { SubjectForm(subject: Subject(name: subjectName.isEmpty ? "" : subjectName), isNew: true) { track.upsertSubject($0) } onDelete: { _ in } }
        .sheet(isPresented: $showAllSessions) { SessionsList(track: track) }
        .sheet(isPresented: $editingGoal) { GoalForm(minutes: track.weeklyStudyGoalMinutes) { track.weeklyStudyGoalMinutes = $0 } }
        .onChange(of: track.isStudying) { _, running in if running { showTimer = true } }
        .animation(.snappy, value: track.isStudying)
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        if let since = track.runningSince {
            Button { showTimer = true } label: {
                HStack(spacing: 16) {
                    FocusRing(start: since, until: track.runningUntil, now: now, tint: tint, lineWidth: 8)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FOCUSING").font(.caption2.weight(.bold)).foregroundStyle(tint).tracking(0.5)
                        Text(track.runningTopic.isEmpty ? "Focus" : track.runningTopic).font(.title2.weight(.bold)).lineLimit(1)
                        Text(since, style: .timer).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("START A SESSION").font(.caption2.weight(.bold)).foregroundStyle(tint).tracking(0.5)
                if track.subjects.isEmpty {
                    TextField("What are you focusing on?", text: $subjectName)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(track.subjects) { s in
                                Button {
                                    subjectName = s.name
                                } label: {
                                    Label(s.name, systemImage: s.symbol).font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                }
                                .buttonStyle(.glass)
                                .tint(subjectName == s.name ? tint : .secondary)
                                .background(subjectName == s.name ? tint.opacity(0.15) : .clear, in: Capsule())
                            }
                            Button { addingSubject = true } label: { Image(systemName: "plus").padding(8) }.buttonStyle(.glass)
                        }
                    }
                }
                Picker("Length", selection: $focusMinutes) {
                    Text("25").tag(25); Text("50").tag(50); Text("90").tag(90); Text("Open").tag(0)
                }
                .pickerStyle(.segmented)
                Button { start() } label: {
                    Label("Start focus", systemImage: "play.fill").font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(tint)
                .disabled(subjectName.trimmingCharacters(in: .whitespaces).isEmpty && !track.subjects.isEmpty)
            }
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func start() {
        let name = subjectName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, track.subject(named: name) == nil { track.upsertSubject(Subject(name: name)) }
        track.startStudy(topic: name, focusMinutes: focusMinutes > 0 ? focusMinutes : nil)
        if let until = track.runningUntil { Task { await NotificationScheduler.scheduleFocusEnd(at: until, topic: name) } }
        Task { await FocusActivityController.sync(track: track) }
        showTimer = true
    }

    // MARK: - Week

    private var weekCard: some View {
        let week = track.studyMinutes(weekOf: now)
        let goal = track.weeklyStudyGoalMinutes
        let streak = track.studyStreak(now: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Text("\(hm(week)) / \(hm(goal))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary).contentTransition(.numericText())
            }
            ProgressView(value: Double(min(week, goal)), total: Double(max(goal, 1))).tint(week >= goal ? .green : tint)
            HStack {
                stat(hm(track.studyMinutes(on: now)), "today")
                stat("\(streak)", streak == 1 ? "day streak" : "day streak", icon: streak > 0 ? "flame.fill" : nil)
                stat("\(track.sessions.filter { calendar.isDate($0.start, equalTo: now, toGranularity: .weekOfYear) }.count)", "sessions")
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { editingGoal = true }
    }

    private func stat(_ value: String, _ label: String, icon: String? = nil) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).foregroundStyle(.orange).font(.subheadline) }
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Subjects

    private var subjectsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subjects").font(.headline)
                Spacer()
                Button { addingSubject = true } label: { Image(systemName: "plus") }.buttonStyle(.glass).controlSize(.small)
            }
            .padding(.horizontal, 4)
            if track.subjects.isEmpty {
                Text("Add what you work on — a language, a course, a project — and give each a weekly goal.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(track.subjects) { s in
                        let minutes = track.minutes(subject: s.name, weekOf: now)
                        Button { editingSubject = s } label: {
                            HStack(spacing: 12) {
                                Image(systemName: s.symbol).foregroundStyle(tint).frame(width: 28)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(s.name).foregroundStyle(Color.primary)
                                        Spacer()
                                        Text(s.weeklyGoalMinutes > 0 ? "\(hm(minutes)) / \(hm(s.weeklyGoalMinutes))" : hm(minutes))
                                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    if s.weeklyGoalMinutes > 0 {
                                        ProgressView(value: Double(min(minutes, s.weeklyGoalMinutes)), total: Double(max(s.weeklyGoalMinutes, 1)))
                                            .tint(minutes >= s.weeklyGoalMinutes ? .green : tint)
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if s.id != track.subjects.last?.id { Divider().padding(.leading, 56) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Heat map

    private var heatMapCard: some View {
        let days = track.studyMinutesByDay(days: 84, now: now)
        let total = days.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 12 weeks").font(.headline)
                Spacer()
                Text("\(hm(total)) total").font(.caption).foregroundStyle(.secondary)
            }
            HeatMap(days: days, now: now, tint: tint, calendar: calendar)
            HStack(spacing: 6) {
                Text("less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { f in
                    RoundedRectangle(cornerRadius: 2).fill(HeatMap.color(fraction: f, tint: tint)).frame(width: 10, height: 10)
                }
                Text("more").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                if track.sessions.count > 3 { Button("All \(track.sessions.count)") { showAllSessions = true }.font(.subheadline) }
            }
            .padding(.horizontal, 4)
            if track.sessions.isEmpty {
                Text("Your first session lands here.").font(.subheadline).foregroundStyle(.secondary).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(track.recentSessions(limit: 3)) { s in
                        HStack {
                            Text(s.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            Text(s.topic)
                            Spacer()
                            Text(hm(s.minutes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { track.deleteSession(id: s.id) } }
                        if s.id != track.recentSessions(limit: 3).last?.id { Divider().padding(.leading, 16) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func hm(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

/// 12 columns of 7 days, GitHub style.
struct HeatMap: View {
    let days: [(date: Date, minutes: Int)]
    let now: Date
    let tint: Color
    let calendar: Calendar

    static func color(fraction: Double, tint: Color) -> Color {
        fraction <= 0 ? Color(uiColor: .tertiarySystemFill) : tint.opacity(0.25 + 0.75 * min(1, fraction))
    }

    var body: some View {
        let peak = Double(max(days.map(\.minutes).max() ?? 1, 30))
        let weeks: [[(date: Date, minutes: Int)]] = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        HStack(alignment: .top, spacing: 4) {
            ForEach(weeks.indices, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(weeks[w], id: \.date) { d in
                        cell(d, peak: peak)
                    }
                }
            }
        }
    }

    private func cell(_ d: (date: Date, minutes: Int), peak: Double) -> some View {
        let isToday = calendar.isDate(d.date, inSameDayAs: now)
        return RoundedRectangle(cornerRadius: 3)
            .fill(Self.color(fraction: Double(d.minutes) / peak, tint: tint))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay { if isToday { RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1.5) } }
    }
}

/// Progress ring for a focus session: fills toward the target, or spins slowly when open.
struct FocusRing: View {
    let start: Date
    let until: Date?
    let now: Date
    var tint: Color = .indigo
    var lineWidth: CGFloat = 12

    private var fraction: Double {
        guard let until else { return 0 }
        let total = until.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            if until != nil {
                Circle().trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: fraction)
            } else {
                Circle().trim(from: 0, to: 0.25)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90 + now.timeIntervalSince(start).truncatingRemainder(dividingBy: 60) * 6))
                    .animation(.linear(duration: 20), value: now)
            }
        }
    }
}

/// The full-screen timer. Dark, one number, one ring, three buttons.
struct FocusTimerView: View {
    @Bindable var track: TrackStore
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date.now
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let tint = AppSection.focus.tint

    private var over: Bool { track.runningUntil.map { $0 <= now } ?? false }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.07, blue: 0.20), Color(red: 0.16, green: 0.12, blue: 0.36)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline).frame(width: 44, height: 44) }
                        .buttonStyle(.glass)
                    Spacer()
                    Text(over ? "FOCUS DONE" : "FOCUS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(over ? .green : tint.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer()
                if let since = track.runningSince {
                    ZStack {
                        FocusRing(start: since, until: track.runningUntil, now: now, tint: over ? .green : tint, lineWidth: 14)
                        VStack(spacing: 6) {
                            Group {
                                if let until = track.runningUntil, until > now { Text(timerInterval: since...until, countsDown: true) } else { Text(since, style: .timer) }
                            }
                            .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                            Text(track.runningTopic.isEmpty ? "Focus" : track.runningTopic).font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            if over { Text("Take five, or keep going.").font(.subheadline).foregroundStyle(.white.opacity(0.6)) }
                            else if track.runningUntil == nil { Text("Open session").font(.subheadline).foregroundStyle(.white.opacity(0.6)) }
                        }
                    }
                    .frame(width: 300, height: 300)
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.green).symbolEffect(.bounce, options: .nonRepeating)
                        Text("Logged").font(.title2.weight(.semibold))
                        Text("\(track.studyMinutes(on: now)) min today").foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                HStack(spacing: 14) {
                    if track.isStudying {
                        Button { extend() } label: { Label("+5 min", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(.glass)
                        Button { stop() } label: { Label(over ? "Done" : "Stop", systemImage: over ? "checkmark" : "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(.glassProminent).tint(over ? .green : tint)
                    } else {
                        Button { dismiss() } label: { Text("Close").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.glassProminent).tint(tint)
                    }
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .padding()
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onReceive(tick) { now = $0 }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(.success, trigger: over)
        .animation(.snappy, value: over)
        .animation(.snappy, value: track.isStudying)
    }

    private func extend() {
        track.extendFocus(by: 5, now: now)
        if let until = track.runningUntil { Task { await NotificationScheduler.scheduleFocusEnd(at: until, topic: track.runningTopic) } }
        Task { await FocusActivityController.sync(track: track) }
    }

    private func stop() {
        track.stopStudy(at: now)
        NotificationScheduler.cancelFocusEnd()
        Task { await FocusActivityController.sync(track: track) }
        Task { try? await Task.sleep(for: .seconds(1)); dismiss() }
    }
}

struct SubjectForm: View {
    @State var subject: Subject
    var isNew = false
    let onSave: (Subject) -> Void
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let symbols = ["book", "laptopcomputer", "graduationcap", "pencil", "music.note", "paintbrush", "globe", "function", "brain.head.profile", "briefcase"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Subject", text: $subject.name)
                Stepper(subject.weeklyGoalMinutes == 0 ? "Weekly goal: none" : "Weekly goal: \(subject.weeklyGoalMinutes / 60) h \(subject.weeklyGoalMinutes % 60) min", value: $subject.weeklyGoalMinutes, in: 0...3000, step: 30)
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(symbols, id: \.self) { s in
                            Button { subject.symbol = s } label: {
                                Image(systemName: s).font(.title3).frame(width: 44, height: 44)
                                    .background(subject.symbol == s ? AppSection.focus.tint.opacity(0.18) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(subject.symbol == s ? AppSection.focus.tint : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !isNew {
                    Section { Button("Delete subject", role: .destructive) { onDelete(subject.id); dismiss() } }
                }
            }
            .navigationTitle(isNew ? "New subject" : subject.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(subject); dismiss() }.disabled(subject.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
