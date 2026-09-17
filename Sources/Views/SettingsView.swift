import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var days: DayStore
    @Bindable var metrics: MetricsStore
    @Bindable var health: HealthStore
    @Bindable var account: CoachAccount
    let plan: PlanStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPlaces = false

    private var dayEnd: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: days.dayEnd) ?? .now },
            set: { days.dayEnd = Calendar.current.dateComponents([.hour, .minute], from: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day ends at", selection: dayEnd, displayedComponents: .hourAndMinute)
                    Toggle("End-of-block check-ins", isOn: $days.checkInsEnabled)
                    NavigationLink { PlacesView(days: days) } label: {
                        LabeledContent("Places & travel", value: "\(days.places.list.count)")
                    }
                } header: { Text("Day") } footer: {
                    Text("A moved block is never placed after the day end. Check-ins ask “Did it happen?” five minutes after a block ends; you can also turn them off per block.")
                }

                Section("Your week") {
                    let week = metrics.week()
                    LabeledContent("Blocks done", value: "\(week.done)")
                    LabeledContent("Closed by Apple Health", value: "\(week.healthClosed)")
                    LabeledContent("Moved later", value: "\(week.replans)")
                    LabeledContent("Skipped", value: "\(week.skipped)")
                }

                Section("Notifications") {
                    LabeledContent("Permission", value: statusText)
                    Picker("Sound", selection: $days.sound) {
                        Text("Pacer chime").tag("pacer")
                        Text("System default").tag("system")
                    }
                    Button("Play the chime", systemImage: "speaker.wave.2") { SoundPreview.play() }
                    Toggle("Live Activity for the current block", isOn: $days.liveActivity)
                    if notificationStatus == .denied {
                        Button("Open iOS Settings") { open(URL(string: UIApplication.openSettingsURLString)) }
                    }
                }

                Section {
                    LabeledContent("Apple Health", value: !health.isAvailable ? "Not available" : health.isAuthorized ? "Connected" : "Not connected")
                    if health.isAvailable && !health.isAuthorized {
                        Button("Connect Apple Health") { Task { await health.requestAuthorization(); await health.refresh() } }
                    }
                } footer: {
                    Text("Runs and strength workouts in Health close their blocks, even while the app is closed.")
                }

                Section("Coach") {
                    Button("Coach profile", systemImage: "person.text.rectangle") { editingProfile = true }
                    if account.isSignedIn {
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { account.signOut() }
                    }
                }

                Section {
                    Label("Now / Next — Home Screen, small · medium · large", systemImage: "square.grid.2x2")
                    Label("Today's plan — Home Screen, medium · large", systemImage: "list.bullet.rectangle")
                    Label("Now / Next — Lock Screen, rectangular · inline", systemImage: "lock.rectangle")
                    Label("Day progress — Lock Screen circular · Home Screen small", systemImage: "circle.dotted.circle")
                } header: { Text("Widgets") } footer: {
                    Text("Home Screen: touch and hold → Edit → Add Widget → Pacer. Lock Screen: touch and hold the Lock Screen → Customize → tap the widget area → Pacer.")
                }

                Section("About") {
                    LabeledContent("Version", value: Diagnostics.version)
                    NavigationLink("Diagnostics") { DiagnosticsView(days: days, metrics: metrics, health: health, plan: plan) }
                    Link("Privacy policy", destination: URL(string: "https://github.com/4lxn/autopiloto/blob/main/docs/privacy.md")!)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editingProfile) { ProfileEditor() }
            .task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
            .navigationDestination(isPresented: $showPlaces) { PlacesView(days: days) }
            .onAppear {
                #if DEBUG
                if CoachAccount.screenshotMode == "places" || CoachAccount.screenshotMode == "placeform" { showPlaces = true }
                #endif
            }
            .onChange(of: days.sound) { _, sound in
                NotificationScheduler.soundName = sound == "pacer" ? "pacer.caf" : nil
                Task { await NotificationScheduler.register(plan.blocks) }   // repeating starts carry the sound
            }
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Off"
        default: "Not asked yet"
        }
    }

    private func open(_ url: URL?) { if let url { UIApplication.shared.open(url) } }
}

import AVFoundation

/// Plays the bundled chime once, for the Settings button.
@MainActor
enum SoundPreview {
    private static var player: AVAudioPlayer?
    static func play() {
        guard let url = Bundle.main.url(forResource: "pacer", withExtension: "caf") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

/// Everything needed to debug a report from a tester, as text. Pure over its inputs.
enum Diagnostics {
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
    }

    struct Input {
        var now: Date
        var version: String
        var notificationStatus: String
        var pending: [String]
        var lastRearm: Date?
        var healthAvailable: Bool
        var healthAuthorized: Bool
        var lastHealthDelivery: Date?
        var persistenceErrors: Int
        var lastPersistenceError: String?
        var blocks: Int
        var checkInBlocks: Int
        var checkInsEnabled: Bool
        var dayEnd: DateComponents
        var week: MetricsStore.Week
        var files: [(String, Int)]
    }

    static func report(_ i: Input) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        func when(_ d: Date?) -> String { d.map(f.string(from:)) ?? "never" }
        let starts = i.pending.filter { !NotificationScheduler.isOneShot($0) && !$0.hasSuffix("-snooze") }.count
        let checkIns = i.pending.filter { $0.hasPrefix(NotificationScheduler.checkInPrefix) }.count
        let moved = i.pending.filter { $0.hasPrefix(NotificationScheduler.movedPrefix) }.count
        let pct = { (v: Double?) in v.map { String(format: "%.0f%%", $0 * 100) } ?? "—" }
        return """
        Pacer \(i.version) — \(f.string(from: i.now))
        Plan: \(i.blocks) blocks, \(i.checkInBlocks) with check-ins (\(i.checkInsEnabled ? "on" : "off")), day ends \(DayLogic.clock(i.dayEnd))
        Notifications: \(i.notificationStatus); pending \(i.pending.count)/\(NotificationScheduler.maxPending) (starts \(starts), check-ins \(checkIns), moved \(moved)); last re-arm \(when(i.lastRearm))
        Health: \(i.healthAvailable ? (i.healthAuthorized ? "connected" : "not connected") : "unavailable"); last delivery \(when(i.lastHealthDelivery))
        Persistence: \(i.persistenceErrors) errors\(i.lastPersistenceError.map { " — last: \($0)" } ?? "")
        Files: \(i.files.map { "\($0.0) \($0.1) B" }.joined(separator: ", "))
        Week: done \(i.week.done) (health \(i.week.healthClosed)), skipped \(i.week.skipped), replans \(i.week.replans), undone \(i.week.undone)
        Replan criterion: check-ins acted \(i.week.checkInsActed), replan share \(pct(i.week.replanShare)) (keep ≥ 30%), replans kept \(pct(i.week.replanKept)) (keep ≥ 70%)
        """
    }
}

struct DiagnosticsView: View {
    let days: DayStore
    let metrics: MetricsStore
    let health: HealthStore
    let plan: PlanStore
    @State private var report = "Collecting…"
    @State private var copied = false

    var body: some View {
        ScrollView {
            Text(report)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Diagnostics").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                UIPasteboard.general.string = report
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .sensoryFeedback(.success, trigger: copied)
            .padding()
        }
        .task { report = await collect() }
    }

    private func collect() async -> String {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let files = ["plan", "completions", "overrides", "undo", "settings", "metrics", "food", "track", "wardrobe", "chat"].compactMap { name -> (String, Int)? in
            let url = AppFiles.url("\(name).json")
            guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else { return nil }
            return (name, size)
        }
        return Diagnostics.report(.init(
            now: .now, version: Diagnostics.version,
            notificationStatus: status == .authorized ? "allowed" : status == .denied ? "denied" : "not determined",
            pending: pending, lastRearm: metrics.lastRearm,
            healthAvailable: health.isAvailable, healthAuthorized: health.isAuthorized, lastHealthDelivery: metrics.lastHealthDelivery,
            persistenceErrors: PersistenceState.shared.errorCount, lastPersistenceError: PersistenceState.shared.lastError,
            blocks: plan.blocks.count, checkInBlocks: plan.blocks.filter(\.checkIn).count, checkInsEnabled: days.checkInsEnabled,
            dayEnd: days.dayEnd, week: metrics.week(), files: files
        ))
    }
}
