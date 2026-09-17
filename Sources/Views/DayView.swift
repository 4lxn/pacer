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
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now
    @State private var notificationsDenied = false
    @State private var bannerDismissed = false
    @State private var editingPlan = false
    @State private var showingSettings = false
    private var persistence: PersistenceState { PersistenceState.shared }

    private let calendar = Calendar.current
    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var blocks: [Block] { DayLogic.sorted(mutator.effectivePlan(on: now)) }
    private var moved: Set<String> { Set(days.override(dayKey: mutator.dayKey(now)).moved.keys) }
    private var completed: Set<String> { store.completed(on: now) }
    private var skipped: Set<String> { store.skipped(on: now) }
    /// Skipped blocks leave the denominator: "n / N today" counts what is still on the plan.
    private var counted: [Block] { blocks.filter { !skipped.contains($0.id) } }
    private var doneCount: Int { counted.filter { completed.contains($0.id) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let error = persistence.lastError { persistenceBanner(error) }
                if notificationsDenied && !bannerDismissed { permissionBanner }
                NowCard(
                    block: DayLogic.currentBlock(blocks, now: now, completed: completed, skipped: skipped, calendar: calendar),
                    allDone: doneCount == counted.count,
                    now: now,
                    completed: completed,
                    calendar: calendar,
                    onDone: { id in mutator.setDone(id, true, dayKey: mutator.dayKey(now)) },
                    onSkip: { id in mutator.skipToday(id, dayKey: mutator.dayKey(now)) },
                    onReplan: { id in mutator.replan(id, on: now) }
                )
                upNext
                dayList
            }
            .padding()
            .padding(.bottom, 72)   // room for the undo toast
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) { undoToast }
        .animation(.snappy(duration: 0.35), value: mutator.lastChange)
        .animation(.snappy(duration: 0.35), value: moved)
        .onReceive(tick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = .now
                store.reload()
                Task {
                    await refreshNotifications()
                    await autoCompleteFromHealth()
                    await rearmCheckIns()
                }
            }
        }
        .sheet(isPresented: $editingPlan) { PlanView(plan: plan) }
        .onAppear {
            #if DEBUG
            if CoachAccount.screenshotMode == "settings" { showingSettings = true }
            #endif
        }
        .sheet(isPresented: $showingSettings) { SettingsView(days: days, metrics: metrics, health: health, account: account, plan: plan) }
        .onChange(of: track.sessions) { _, _ in Task { await autoCompleteFromHealth() } }
        .task(id: plan.needsOnboarding) {
            // Onboarding asks for the permission itself; don't double-prompt behind the cover.
            guard !plan.needsOnboarding, CoachAccount.screenshotMode == nil else { return }
            let granted = await NotificationScheduler.requestAuthorization()
            notificationsDenied = !granted
            await NotificationScheduler.register(plan.blocks)
            await autoCompleteFromHealth()
            await rearmCheckIns()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.title2.weight(.semibold))
                Text("\(doneCount) / \(counted.count) done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { editingPlan = true } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Edit plan")
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape").frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Settings")
                }
                .buttonStyle(.glass)
            }
        }
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
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
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
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var upNext: some View {
        if let next = DayLogic.nextUp(blocks, now: now, completed: completed, calendar: calendar), let start = next.start {
            HStack(spacing: 6) {
                Text("Up next:").foregroundStyle(.secondary)
                Text(next.label).fontWeight(.medium)
                Text("at \(NotificationScheduler.clock(start))").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.subheadline)
        }
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The day").font(.headline)
            VStack(spacing: 0) {
                ForEach(blocks) { block in
                    BlockRow(
                        block: block,
                        status: block.status(now: now, completed: completed, skipped: skipped, calendar: calendar),
                        subtitle: block.note(on: now, calendar: calendar),
                        moved: moved.contains(block.id),
                        onToggle: { mutator.toggleDone(block.id, on: now) },
                        onSkip: { mutator.skipToday(block.id, dayKey: mutator.dayKey(now)) },
                        onUnskip: { mutator.unskip(block.id, on: now) },
                        onReplan: { mutator.replan(block.id, on: now) }
                    )
                    if block.id != blocks.last?.id { Divider().padding(.leading, 72) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func refreshNotifications() async {
        notificationsDenied = await NotificationScheduler.isDenied()
        await NotificationScheduler.register(plan.blocks)
    }

    /// Check-ins are one-shot (today + tomorrow); re-arm after anything that changes what's done.
    private func rearmCheckIns() async { mutator.now = { .now }; await mutator.rearm() }

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
