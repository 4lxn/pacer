import SwiftUI

/// First launch: wake and sleep times build a starter plan, the notification permission, then five
/// short questions that become the Coach profile. Every step can be skipped.
struct OnboardingView: View {
    let onFinish: ([Block]) -> Void

    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: .now) ?? .now
    @State private var sleep = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now
    @State private var step = 0
    @State private var answers: [String: String] = [:]
    @FocusState private var answerFocused: Bool

    private let calendar = Calendar.current
    private var questionCount: Int { CoachProfile.questions.count }
    /// 0 times · 1 notifications · 2 coach intro · 3…(3+n-1) questions · last done
    private var totalSteps: Int { 3 + questionCount + 1 }
    private var isQuestion: Bool { step >= 3 && step < 3 + questionCount }
    private var question: CoachProfile.Question? { isQuestion ? CoachProfile.questions[step - 3] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
                .padding(.top, 8)
            Spacer(minLength: 0)
            ZStack {
                Group {
                    switch step {
                    case 0: timesStep
                    case 1: notificationsStep
                    case 2: coachIntroStep
                    case totalSteps - 1: doneStep
                    default: questionStep
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

    private var timesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Your day, on pace", "Pacer tells you what to do next and takes one tap to confirm. Start with two times; edit everything later.")
            VStack(spacing: 0) {
                DatePicker("I wake up at", selection: $wake, displayedComponents: .hourAndMinute)
                    .padding(.vertical, 8)
                Divider()
                DatePicker("I go to sleep at", selection: $sleep, displayedComponents: .hourAndMinute)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            primary("Build my day") { advance() }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Let it tap you on the shoulder", "Each fixed block sends a notification when it starts, and longer blocks ask “did it happen?” when they end. Press and hold a notification to see Done, Snooze or Skip — no need to open the app.")
            primary("Allow notifications") {
                Task {
                    _ = await NotificationScheduler.requestAuthorization()
                    advance()
                }
            }
            secondary("Not now") { advance() }
        }
    }

    private var coachIntroStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Meet your coach", "Five short questions so it knows your goals, your training and how you eat. It can then plan meals, move blocks and answer with your numbers. You can change all of it later.")
            primary("Let's go") { advance(); answerFocused = true }
            secondary("Skip for now") { finish() }
        }
    }

    private var questionStep: some View {
        let q = question!
        return VStack(alignment: .leading, spacing: 16) {
            Text("\(step - 2) of \(questionCount)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            title(q.title, q.hint)
            TextField(q.placeholder, text: binding(q.id), axis: .vertical)
                .lineLimit(3...6)
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .focused($answerFocused)
                .submitLabel(.next)
                .onSubmit { advance() }
            primary(step == 3 + questionCount - 1 ? "Build my coach" : "Next") { advance() }
            secondary("Skip this one") { answers[q.id] = ""; advance() }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: step)
            title("You're set", "Your day is planned, your coach knows you. Today is one tap away.")
            primary("Open today") { finish() }
        }
    }

    // MARK: - Pieces

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    .frame(height: 4)
                    .animation(.snappy, value: step)
            }
        }
        .accessibilityLabel("Step \(step + 1) of \(totalSteps)")
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

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { answers[id] ?? "" }, set: { answers[id] = $0 })
    }

    private func advance() {
        if step == 3 + questionCount - 1 {
            CoachProfile.save(CoachProfile.compose(answers: answers))
            answerFocused = false
        }
        step += 1
        if isQuestion { answerFocused = true }
    }

    private func finish() {
        let w = calendar.dateComponents([.hour, .minute], from: wake)
        let s = calendar.dateComponents([.hour, .minute], from: sleep)
        onFinish(Plan.starter(wake: .hm(w.hour ?? 7, w.minute ?? 30), sleep: .hm(s.hour ?? 23, s.minute ?? 0)))
    }
}
