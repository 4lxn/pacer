import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var days: DayStore
    @Bindable var metrics: MetricsStore
    @Bindable var health: HealthStore
    @Bindable var account: CoachAccount
    let plan: PlanStore
    @Bindable var sections: SectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPlaces = false
    @State private var telemetry = Telemetry.isEnabled

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
                    NavigationLink { SectionsView(sections: sections) } label: {
                        LabeledContent("Sections", value: sections.enabled.map(\.title).joined(separator: " · "))
                    }
                } footer: { Text("Turn sections on or off and set their order in the tab bar.") }

                Section {
                    DatePicker("Day ends at", selection: dayEnd, displayedComponents: .hourAndMinute)
                    Toggle("End-of-block check-ins", isOn: $days.checkInsEnabled)
                    NavigationLink { PlacesView(days: days) } label: {
                        LabeledContent("Places & travel", value: "\(days.places.list.count)")
                    }
                    Toggle("Calendar events are busy time", isOn: Binding(get: { days.useCalendar }, set: { on in
                        if on { Task { days.useCalendar = await CalendarBusy.shared.requestAccess(); CalendarBusy.shared.refresh() } } else { days.useCalendar = false }
                    }))
                    if CalendarBusy.shared.denied || (days.useCalendar && !CalendarBusy.shared.isAuthorized) {
                        Button("Calendar access is off in iOS Settings") { open(URL(string: UIApplication.openSettingsURLString)) }.font(.footnote)
                    }
                } header: { Text("Day") } footer: {
                    Text("A moved block is never placed after the day end or on top of a calendar event. Events are read on this phone and never sent anywhere. Check-ins ask “Did it happen?” five minutes after a block ends; you can also turn them off per block.")
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
                    Toggle("Morning brief", isOn: $days.morningBrief)
                    Toggle("“Ends in 5 min” for long blocks", isOn: $days.endNudges)
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

                Section("Ask Pacer") {
                    Button("About you", systemImage: "person.text.rectangle") { editingProfile = true }
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

                Section {
                    ShareLink(item: DataExport.file(), preview: SharePreview("Pacer data", image: Image(systemName: "doc.zipper"))) {
                        Label("Export my data", systemImage: "square.and.arrow.up")
                    }
                } footer: { Text("Every JSON file the app keeps (plan, days, food, focus, money, closet, places, chats) in one file you own.") }

                Section {
                    Toggle("Share anonymous usage counts", isOn: $telemetry)
                        .onChange(of: telemetry) { _, on in Telemetry.isEnabled = on }
                    Button("Send feedback", systemImage: "envelope") {
                        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                        open(URL(string: "mailto:alangibrancs@icloud.com?subject=Pacer%20feedback%20(build%20\(build))"))
                    }
                } header: { Text("Privacy") } footer: {
                    Text("Your plan, health data and places stay on this phone. Ask sends only what a question needs, and it isn't stored. Usage counts are a random id and a few numbers a day (opened, blocks closed, check-ins answered) so we can tell whether Pacer works; never what the blocks are.")
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
        var telemetryID: String? = nil
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
        Usage counts: \(i.telemetryID.map { "on, id \($0)" } ?? "off")
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
            dayEnd: days.dayEnd, week: metrics.week(), files: files,
            telemetryID: Telemetry.isEnabled ? Telemetry.id : nil
        ))
    }
}


/// Which tabs show, in what order. Data is kept when a section is off.
struct SectionsView: View {
    @Bindable var sections: SectionStore

    var body: some View {
        List {
            Section {
                ForEach(sections.enabled) { s in row(s, on: true) }
                    .onMove { sections.move(from: $0, to: $1) }
            } header: { Text("On") } footer: { Text("Drag to reorder. Today always comes first; past five tabs iOS adds “More”.") }
            let off = AppSection.allCases.filter { !sections.isOn($0) }
            if !off.isEmpty {
                Section("Off") { ForEach(off) { s in row(s, on: false) } }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Sections").navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ s: AppSection, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.symbol).foregroundStyle(s.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title)
                Text(s.pitch).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if s.isCore {
                Text("always").font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: Binding(get: { on }, set: { sections.set(s, on: $0) })).labelsHidden()
            }
        }
    }
}


/// One JSON document with every store's file, for backups and moving phones.
enum DataExport {
    @MainActor
    static func file() -> URL {
        var bundle: [String: Any] = ["exportedAt": ISO8601DateFormatter().string(from: .now), "app": "Pacer \(Diagnostics.version)"]
        let dir = AppFiles.directory
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in names where name.hasSuffix(".json") {
                if let data = try? Data(contentsOf: dir.appendingPathComponent(name)), let json = try? JSONSerialization.jsonObject(with: data) {
                    bundle[String(name.dropLast(5))] = json
                }
            }
            let chats = dir.appendingPathComponent("chats")
            if let chatFiles = try? FileManager.default.contentsOfDirectory(atPath: chats.path) {
                var all: [String: Any] = [:]
                for f in chatFiles where f.hasSuffix(".json") {
                    if let data = try? Data(contentsOf: chats.appendingPathComponent(f)), let json = try? JSONSerialization.jsonObject(with: data) { all[String(f.dropLast(5))] = json }
                }
                bundle["chatMessages"] = all
            }
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("pacer-export.json")
        if let data = try? JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: out) }
        return out
    }
}
