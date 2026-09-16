import SwiftUI

/// First launch: wake and sleep times build a starter plan; then the notification permission.
struct OnboardingView: View {
    let onFinish: ([Block]) -> Void
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: .now) ?? .now
    @State private var sleep = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now) ?? .now
    @State private var step = 0

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            if step == 0 {
                Text("Your day on rails").font(.largeTitle.weight(.bold))
                Text("Autopiloto tells you what to do next and takes one tap to confirm. Start with two times; edit everything later in the Plan tab.")
                    .foregroundStyle(.secondary)
                DatePicker("I wake up at", selection: $wake, displayedComponents: .hourAndMinute)
                DatePicker("I go to sleep at", selection: $sleep, displayedComponents: .hourAndMinute)
                Button("Build my day") { step = 1 }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            } else {
                Text("Let it tap you on the shoulder").font(.largeTitle.weight(.bold))
                Text("Each fixed block sends a notification when it starts. Done and Snooze work from the lock screen.")
                    .foregroundStyle(.secondary)
                Button("Allow notifications") {
                    Task {
                        _ = await NotificationScheduler.requestAuthorization()
                        finish()
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                Button("Not now") { finish() }.frame(maxWidth: .infinity)
            }
            Spacer()
        }
        .padding(24)
        .interactiveDismissDisabled()
    }

    private func finish() {
        let w = calendar.dateComponents([.hour, .minute], from: wake)
        let s = calendar.dateComponents([.hour, .minute], from: sleep)
        onFinish(Plan.starter(wake: .hm(w.hour ?? 7, w.minute ?? 30), sleep: .hm(s.hour ?? 23, s.minute ?? 0)))
    }
}
