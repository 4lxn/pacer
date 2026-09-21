import SwiftUI

/// First launch, five screens, no typing: what a good day looks like (chips become the plan),
/// notifications, about you (chips become the profile), Health, and today already running.
struct OnboardingView: View {
    @Bindable var health: HealthStore
    /// Blocks and the day end (sleep time, clamped to the calendar day).
    let onFinish: ([Block], DateComponents) -> Void

    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: .now) ?? .now
    @State private var sleep = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now
    @State private var goals: Set<Goal> = OnboardingView.debugStep == nil ? [] : [.gym, .study, .read]
    @State private var picks: [String: Set<String>] = [:]
    @State private var extra = ""
    @State private var step = OnboardingView.debugStep ?? 0

    /// Debug-only: `AUTOPILOTO_ONBOARDING_STEP=3` opens on that screen with a few goals picked (screenshots).
    private static var debugStep: Int? {
        #if DEBUG
        ProcessInfo.processInfo.environment["AUTOPILOTO_ONBOARDING_STEP"].flatMap(Int.init)
        #else
        nil
        #endif
    }
    @FocusState private var extraFocused: Bool

    private let calendar = Calendar.current
    private static let totalSteps = 5

    private var wakeHM: DateComponents { let c = calendar.dateComponents([.hour, .minute], from: wake); return .hm(c.hour ?? 7, c.minute ?? 30) }
    private var sleepHM: DateComponents { let c = calendar.dateComponents([.hour, .minute], from: sleep); return .hm(c.hour ?? 23, c.minute ?? 0) }
    private var blocks: [Block] { Plan.plan(wake: wakeHM, sleep: sleepHM, goals: goals) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress.padding(.top, 8)
            Spacer(minLength: 0)
            ZStack {
                Group {
                    switch step {
                    case 0: goodDayStep
                    case 1: notificationsStep
                    case 2: aboutStep
                    case 3: healthStep
                    default: doneStep
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .animation(.snappy(duration: 0.35), value: step)
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
        .interactiveDismissDisabled()
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Steps

    private var goodDayStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("What does a good day look like?", "Tap what you want in it. Each one becomes blocks at sensible times; change any of them later.")
            MarqueeChips(items: Goal.allCases, selected: goals) { goal in
                withAnimation(.snappy) { if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) } }
            }
            if !goals.isEmpty {
                Text(goals.map(\.label).sorted().joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                DatePicker("I wake up at", selection: $wake, displayedComponents: .hourAndMinute).padding(.vertical, 8)
                Divider()
                DatePicker("I go to sleep at", selection: $sleep, displayedComponents: .hourAndMinute).padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            primary(goals.isEmpty ? "Start with a plain day" : "Build my day") { advance() }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("One question per block", "When a block ends, Pacer asks “did it happen?” on the lock screen. One tap answers: Done, Move it later, or Skip. No need to open the app.")
            notificationPreview
            primary("Allow notifications") {
                Task { _ = await NotificationScheduler.requestAuthorization(); advance() }
            }
            secondary("Not now") { advance() }
        }
    }

    /// A static picture of the check-in, so the permission makes sense before it's asked.
    private var notificationPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(Color.accentColor).frame(width: 28, height: 28)
                    .overlay { Image(systemName: "sun.max.fill").font(.caption).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Did Gym happen?").font(.subheadline.weight(.semibold))
                    Text("19:15 – 20:15 · Upper").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("now").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                ForEach(["Done", "Move it later", "Skip today"], id: \.self) { t in
                    Text(t).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var aboutStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title("About you", "So Ask answers with your numbers and your rules. Tap what fits; skip what doesn't.")
                ForEach(ProfileChips.groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 8) {
                            ForEach(group.options, id: \.self) { option in
                                let on = picks[group.id, default: []].contains(option)
                                Button(option) {
                                    withAnimation(.snappy) {
                                        if on { picks[group.id, default: []].remove(option) } else { picks[group.id, default: []].insert(option) }
                                    }
                                }
                                .buttonStyle(.glass).controlSize(.small)
                                .tint(on ? Color.accentColor : Color.secondary)
                                .fontWeight(on ? .semibold : .regular)
                            }
                        }
                    }
                }
                TextField("Anything else? (optional, one line)", text: $extra)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .focused($extraFocused)
                    .submitLabel(.done)
                primary("Next") { extraFocused = false; advance() }
                secondary("Skip") { picks = [:]; extra = ""; advance() }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Blocks that close themselves", "With Apple Health, a run or a gym session on your watch marks the block done — no tap. Pacer reads workouts and weight on this phone; nothing is uploaded.")
            if health.isAvailable {
                primary("Connect Apple Health") { Task { await health.requestAuthorization(); advance() } }
                secondary("Not now") { advance() }
            } else {
                primary("Next") { advance() }
            }
        }
    }

    private var doneStep: some View {
        let today = DayLogic.sorted(blocks.filter { $0.occurs(on: .now, calendar: calendar) })
        return VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(Color.green)
                .symbolEffect(.bounce, value: step)
            title("Your day is running", "\(today.count) blocks today. Pacer will tap you when each one starts and ask when it ends.")
            VStack(spacing: 0) {
                ForEach(today.prefix(4)) { block in
                    HStack(spacing: 12) {
                        Text(block.start.map(DayLogic.clock) ?? "any").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        Text(block.label)
                        Spacer()
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    if block.id != today.prefix(4).last?.id { Divider().padding(.leading, 72) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            Label("Long-press your Home Screen → + → Pacer to keep what's now on it.", systemImage: "square.grid.2x2")
                .font(.caption).foregroundStyle(.secondary)
            primary("Open Now") { finish() }
        }
    }

    // MARK: - Pieces

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    .frame(height: 4)
                    .animation(.snappy, value: step)
            }
        }
        .accessibilityLabel("Step \(step + 1) of \(Self.totalSteps)")
    }

    private func title(_ headline: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            Text(body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent).controlSize(.large)
    }

    private func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.glass).frame(maxWidth: .infinity)
    }

    private func advance() { step += 1 }

    private func finish() {
        CoachProfile.save(ProfileChips.compose(goals: goals, picks: picks, wake: wakeHM, sleep: sleepHM, extra: extra))
        onFinish(blocks, DayStore.dayEnd(fromSleep: sleepHM, wake: wakeHM))
    }
}

/// Two rows of chips drifting in opposite directions; tap one to pick it. Selected chips fill.
struct MarqueeChips: View {
    let items: [Goal]
    let selected: Set<Goal>
    let onTap: (Goal) -> Void

    var body: some View {
        let half = items.count / 2
        VStack(spacing: 10) {
            row(Array(items[..<half]), reverse: false)
            row(Array(items[half...]), reverse: true)
        }
        .frame(height: 96)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06), .init(color: .black, location: 0.94), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }

    private func row(_ items: [Goal], reverse: Bool) -> some View {
        MarqueeRow(reverse: reverse) {
            HStack(spacing: 8) {
                ForEach(items) { goal in
                    let on = selected.contains(goal)
                    Button { onTap(goal) } label: {
                        Label(goal.label, systemImage: goal.symbol).fixedSize()
                    }
                    .buttonStyle(.glass).controlSize(.small)
                    .tint(on ? Color.accentColor : Color.secondary)
                    .fontWeight(on ? .semibold : .regular)
                }
            }
        }
    }
}

/// Scrolls `content` sideways forever by drawing it twice and sliding one width. The moving
/// strip is an overlay, so the row never widens its parent.
private struct MarqueeRow<Content: View>: View {
    let reverse: Bool
    @ViewBuilder let content: Content
    @State private var width: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(height: 40)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    content
                }
                .fixedSize()
                .offset(x: reverse ? -(width + 8) + offset : offset)
            }
            .clipped()
            .onChange(of: width) { _, w in
                guard w > 0 else { return }
                offset = 0
                withAnimation(.linear(duration: Double(w) / 28).repeatForever(autoreverses: false)) {
                    offset = reverse ? w + 8 : -(w + 8)
                }
            }
            .accessibilityElement(children: .contain)
    }
}
