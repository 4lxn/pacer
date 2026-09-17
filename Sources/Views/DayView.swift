import SwiftUI
import UIKit

struct DayView: View {
    @Bindable var store: CompletionStore
    @Bindable var plan: PlanStore
    @Bindable var days: DayStore
    @Bindable var mutator: DayMutator
    @Bindable var metrics: MetricsStore
    @Bindable var health: HealthStore
    @Bindable var track: TrackStore
    @Bindable var account: CoachAccount
    @Bindable var sections: SectionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now
    @State private var notificationsDenied = false
    @State private var bannerDismissed = false
    @State private var editingPlan = false
    @State private var showingSettings = false
    @State private var detail: Block?
    @State private var editingBlock: Block?
    @State private var addingToday = false
    @State private var showTomorrow = false
    @State private var showingDays = false
    @State private var openDay: Date?
    private var persistence: PersistenceState { PersistenceState.shared }

    private let calendar = Calendar.current
    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var blocks: [Block] { DayLogic.sorted(mutator.effectivePlan(on: now)) }
    private var moved: Set<String> { Set(days.override(dayKey: mutator.dayKey(now)).moved.keys) }
    private var dayNotes: [String: String] { days.override(dayKey: mutator.dayKey(now)).notes }
    private var legs: [String: (minutes: Int, from: String)] { DayLogic.travelLegs(blocks, places: days.places, overrides: days.legMinutes(dayKey: mutator.dayKey(now))) }
    private var completed: Set<String> { store.completed(on: now) }
    private var skipped: Set<String> { store.skipped(on: now) }
    /// Skipped blocks leave the denominator: "n / N today" counts what is still on the plan.
    private var counted: [Block] { blocks.filter { !skipped.contains($0.id) } }
    private var doneCount: Int { counted.filter { completed.contains($0.id) }.count }

    private func status(_ block: Block) -> BlockStatus { block.status(now: now, completed: completed, skipped: skipped, calendar: calendar) }
    /// Ahead of you: current, upcoming and anytime blocks. Missed ones need a decision, so they get their own section.
    private var leftToday: [Block] { blocks.filter { [.current, .upcoming, .free].contains(status($0)) } }
    private var missed: [Block] { blocks.filter { status($0) == .missed } }
    private var finished: [Block] { blocks.filter { completed.contains($0.id) || skipped.contains($0.id) } }
    private var current: Block? { DayLogic.currentBlock(blocks, now: now, completed: completed, skipped: skipped, calendar: calendar) }
    private func score(_ day: Date) -> Double? {
        let key = mutator.dayKey(day)
        return DayLogic.dayScore(mutator.effectivePlan(on: day), completed: store.completed(dayKey: key), skipped: store.skipped(dayKey: key))
    }
    private var streak: Int { DayLogic.dayStreak(now: now, calendar: calendar, score: score) }
    /// The day is winding down: every timed block has ended, or it's the last hour before day end.
    private var isEvening: Bool {
        let lastEnd = blocks.compactMap { $0.endDate(on: now, calendar: calendar) }.max()
        let dayEnd = calendar.date(bySettingHour: days.dayEnd.hour ?? 23, minute: days.dayEnd.minute ?? 0, second: 0, of: now) ?? now
        return (lastEnd.map { now > $0 } ?? false) || now > dayEnd.addingTimeInterval(-3600)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    progress
                    historyStrip
                    if let error = persistence.lastError { persistenceBanner(error) }
                    if notificationsDenied && !bannerDismissed { permissionBanner }
                    NowCard(
                        block: current,
                        allDone: doneCount == counted.count,
                        now: now,
                        completed: completed,
                        calendar: calendar,
                        onDone: { id in mutator.setDone(id, true, dayKey: mutator.dayKey(now)) },
                        onSkip: { id in mutator.skipToday(id, dayKey: mutator.dayKey(now)) },
                        onReplan: { id in mutator.replan(id, on: now) }
                    )
                    .id(current?.id ?? "none")
                    .transition(.blurReplace)
                    upNext
                    section("Left today", count: leftToday.count, blocks: leftToday, empty: "Nothing left on the plan.")
                    if isEvening && !missed.isEmpty { review }
                    else if !missed.isEmpty {
                        section("Missed", count: missed.count, blocks: missed, empty: nil, hint: "Hold a row to move it later or skip it today.")
                    }
                    if !finished.isEmpty { section("Done", count: nil, blocks: finished, empty: nil) }
                    tomorrow
                }
                .padding()
                .padding(.bottom, 72)   // room for the undo toast
                .animation(.snappy(duration: 0.4), value: completed)
                .animation(.snappy(duration: 0.4), value: skipped)
                .animation(.snappy(duration: 0.4), value: moved)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Today")
            .navigationSubtitle(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingDays = true } label: { Label("Days", systemImage: "calendar") }
                    Button { addingToday = true } label: { Label("Just for today", systemImage: "plus") }
                    Button { editingPlan = true } label: { Label("Edit plan", systemImage: "slider.horizontal.3") }
                    Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .navigationDestination(isPresented: $showingDays) { DaysView(mutator: mutator, plan: plan, now: now) }
            .navigationDestination(item: $openDay) { day in DayPlanView(mutator: mutator, plan: plan, date: day, now: now) }
            .sheet(item: $detail) { block in
                BlockDetailSheet(block: block, now: now, mutator: mutator) { editingBlock = $0 }
            }
            .sheet(item: $editingBlock) { block in
                BlockEditor(block: plan.block(id: block.id) ?? block, isNew: false, places: mutator.days.places.list) { plan.upsert($0) } onDelete: { plan.delete(id: $0) }
            }
            .sheet(isPresented: $addingToday) {
                TodayOnlySheet(now: now) { mutator.addExtra($0, dayKey: mutator.dayKey(now)) }
            }
        }
        .overlay(alignment: .bottom) { undoToast }
        .animation(.snappy(duration: 0.35), value: mutator.lastChange)
        .sensoryFeedback(trigger: doneCount) { old, new in new > old ? .success : nil }
        .onReceive(tick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = .now
                store.reload()
                Task {
                    await refreshNotifications()
                    await autoCompleteFromHealth()
                    await rearmCheckIns()
                    await TravelEstimator.refreshLegs(mutator)
                }
            }
        }
        .sheet(isPresented: $editingPlan) { PlanView(plan: plan, places: days.places.list) }
        .onAppear {
            #if DEBUG
            if ["settings", "places", "placeform"].contains(CoachAccount.screenshotMode ?? "") { showingSettings = true }
            if CoachAccount.screenshotMode == "detail" { detail = current ?? blocks.first }
            if CoachAccount.screenshotMode == "days" { showingDays = true }
            if CoachAccount.screenshotMode == "tomorrow" { openDay = calendar.date(byAdding: .day, value: 1, to: now) }
            #endif
        }
        .sheet(isPresented: $showingSettings) { SettingsView(days: days, metrics: metrics, health: health, account: account, plan: plan, sections: sections) }
        .onChange(of: track.sessions) { _, _ in Task { await autoCompleteFromHealth() } }
        .task(id: plan.needsOnboarding) {
            // Onboarding asks for the permission itself; don't double-prompt behind the cover.
            guard !plan.needsOnboarding, CoachAccount.screenshotMode == nil else { return }
            let granted = await NotificationScheduler.requestAuthorization()
            notificationsDenied = !granted
            await NotificationScheduler.register(plan.blocks)
            await autoCompleteFromHealth()
            await rearmCheckIns()
            await TravelEstimator.refreshLegs(mutator)
        }
        .onChange(of: moved) { _, _ in Task { await TravelEstimator.refreshLegs(mutator) } }
    }

    /// "8 / 21 done" with a bar that fills as the day goes; visible progress is the point.
    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(doneCount) / \(counted.count) done")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                if counted.count > 0 {
                    Text("\(Int((Double(doneCount) / Double(counted.count) * 100).rounded()))%")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            ProgressView(value: Double(doneCount), total: Double(max(counted.count, 1)))
                .tint(.accentColor)
        }
        .animation(.snappy, value: doneCount)
    }

    private func persistenceBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't save your data").font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { persistence.clear() } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                .accessibilityLabel("Dismiss")
        }
        .padding()
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are off").font(.headline)
                Text("No start alerts or end-of-block check-ins. Mark blocks done or skipped here instead; everything else works as usual.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.glass).controlSize(.small)
            }
            Spacer()
            Button {
                bannerDismissed = true
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var upNext: some View {
        if let next = DayLogic.nextUp(blocks, now: now, completed: completed, calendar: calendar), let start = next.start {
            HStack(spacing: 6) {
                Text("Up next:").foregroundStyle(.secondary)
                Text(next.label).fontWeight(.medium)
                Text("at \(NotificationScheduler.clock(start))").foregroundStyle(.secondary).monospacedDigit()
                if let leg = legs[next.id] {
                    Text("· leave by \(DayLogic.clock(DayLogic.components(minutes: DayLogic.minutes(start) - leg.minutes)))")
                        .foregroundStyle(Color.accentColor).monospacedDigit()
                }
            }
            .font(.subheadline)
        }
    }

    private func section(_ title: String, count: Int?, blocks: [Block], empty: String?, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.headline)
                if let count {
                    Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(title == "Missed" ? Color.red.opacity(0.12) : Color(uiColor: .tertiarySystemFill), in: Capsule())
                        .foregroundStyle(title == "Missed" ? .red : .secondary)
                        .contentTransition(.numericText())
                }
                if let hint {
                    Spacer()
                    Text(hint).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 4)
            if blocks.isEmpty, let empty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(blocks) { block in
                        if let leg = legs[block.id], title != "Done" {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.walk.motion").font(.caption2)
                                Text("\(leg.minutes) min from \(leg.from) · leave by \(block.start.map { DayLogic.clock(DayLogic.components(minutes: DayLogic.minutes($0) - leg.minutes)) } ?? "")")
                                    .font(.caption).monospacedDigit()
                            }
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 116).padding(.top, 6)
                        }
                        BlockRow(
                            block: block,
                            status: block.status(now: now, completed: completed, skipped: skipped, calendar: calendar),
                            subtitle: [days.places.name(id: block.place), dayNotes[block.id] ?? block.note(on: now, calendar: calendar)].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                            moved: moved.contains(block.id),
                            onToggle: { mutator.toggleDone(block.id, on: now) },
                            onOpen: { detail = block },
                            onSkip: { mutator.skipToday(block.id, dayKey: mutator.dayKey(now)) },
                            onUnskip: { mutator.unskip(block.id, on: now) },
                            onReplan: { mutator.replan(block.id, on: now) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        if block.id != blocks.last?.id { Divider().padding(.leading, 116) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func refreshNotifications() async {
        notificationsDenied = await NotificationScheduler.isDenied()
        await NotificationScheduler.register(plan.blocks)
    }

    /// Check-ins are one-shot (today + tomorrow); re-arm after anything that changes what's done.
    private func rearmCheckIns() async { mutator.now = { .now }; await mutator.rearm() }

    /// Two weeks of day scores, oldest first; today last. Taller = more of the plan done.
    private var historyStrip: some View {
        let days: [(key: String, score: Double?)] = (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = mutator.dayKey(day)
            return (key, DayLogic.dayScore(mutator.effectivePlan(on: day), completed: store.completed(dayKey: key), skipped: store.skipped(dayKey: key)))
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Last 14 days").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill").font(.caption.weight(.medium)).foregroundStyle(.orange)
                        .contentTransition(.numericText())
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days, id: \.key) { day in
                    let score = day.score ?? 0
                    let isToday = day.key == mutator.dayKey(now)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.55))
                                .frame(height: max(score > 0 ? 3 : 0, 24 * score))
                        }
                        .frame(height: 24)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(day.key): \(Int(score * 100)) percent")
                }
            }
            .animation(.snappy, value: doneCount)
        }
    }

    /// End of day: what slipped, one decision per row. Blocks that aren't daily can move to tomorrow.
    private var review: some View {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Day review").font(.headline)
                Text("\(missed.count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.red.opacity(0.12), in: Capsule()).foregroundStyle(.red)
                Spacer()
                Text("\(doneCount) of \(counted.count) done").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(missed) { block in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.label).lineLimit(1)
                            Text(block.start.map(DayLogic.clock) ?? "any").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Button { mutator.setDone(block.id, true, dayKey: mutator.dayKey(now)) } label: { Image(systemName: "checkmark").frame(width: 30, height: 30) }
                            .buttonStyle(.glassProminent).controlSize(.small).accessibilityLabel("Did it")
                        if !block.occurs(on: tomorrow, calendar: calendar) {
                            Button {
                                mutator.addExtra(Block(id: "carry-\(block.id)-\(mutator.dayKey(tomorrow))", label: block.label, kind: block.kind, start: block.start, end: block.end, place: block.place), dayKey: mutator.dayKey(tomorrow))
                                mutator.skipToday(block.id, dayKey: mutator.dayKey(now))
                            } label: { Image(systemName: "arrow.uturn.forward").frame(width: 30, height: 30) }
                            .buttonStyle(.glass).controlSize(.small).accessibilityLabel("Move to tomorrow")
                        }
                        Button { mutator.skipToday(block.id, dayKey: mutator.dayKey(now)) } label: { Image(systemName: "minus").frame(width: 30, height: 30) }
                            .buttonStyle(.glass).controlSize(.small).accessibilityLabel("Skip today")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    if block.id != missed.last?.id { Divider().padding(.leading, 16) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            Text("✓ did it · ↪ tomorrow (blocks that aren't daily) · − skip. Skipped blocks leave today's count.").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
        }
    }

    /// Tomorrow's plan, folded; a glance at what's coming.
    private var tomorrow: some View {
        let day = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let blocks = DayLogic.sorted(mutator.effectivePlan(on: day))
        return DisclosureGroup(isExpanded: $showTomorrow) {
            VStack(spacing: 0) {
                ForEach(blocks) { block in
                    HStack(spacing: 12) {
                        Text(block.start.map(DayLogic.clock) ?? "any").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        Text(block.label)
                        if let note = block.note(on: day, calendar: calendar) { Text(note).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    if block.id != blocks.last?.id { Divider().padding(.leading, 72) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Text("Tomorrow").font(.headline)
                Text("\(blocks.count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule()).foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.weekday(.wide))).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Edit") { openDay = day }.font(.subheadline).buttonStyle(.glass).controlSize(.small)
            }
        }
        .tint(.secondary)
        .padding(.horizontal, 4)
    }

    /// One line + Undo, bottom of the screen, gone after a few seconds or a tap.
    @ViewBuilder
    private var undoToast: some View {
        if let change = mutator.lastChange {
            HStack(spacing: 12) {
                Image(systemName: change.undoable ? "arrow.triangle.2.circlepath" : "exclamationmark.circle")
                    .foregroundStyle(change.undoable ? Color.accentColor : .orange)
                Text(change.summary).font(.subheadline).lineLimit(2)
                Spacer(minLength: 4)
                if change.undoable {
                    Button("Undo") { mutator.undo() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sensoryFeedback(change.undoable ? .success : .warning, trigger: change)
            .onTapGesture { mutator.clearLastChange() }
            .task(id: change) {
                try? await Task.sleep(for: .seconds(6))
                if mutator.lastChange == change { mutator.clearLastChange() }
            }
        }
    }

    /// A run or strength workout in Apple Health today, or 20+ min of study, closes the matching blocks.
    private func autoCompleteFromHealth() async {
        if health.isAvailable { await health.refresh(now: now, calendar: calendar) }
        mutator.autoClose(workouts: health.workouts, studyMinutesToday: track.studyMinutes(on: now), on: now)
    }
}
