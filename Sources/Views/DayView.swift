import SwiftUI
import UIKit

struct DayView: View {
    @Bindable var store: CompletionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now
    @State private var notificationsDenied = false
    @State private var bannerDismissed = false
    @State private var showCoach = false

    private let calendar = Calendar.current
    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var blocks: [Block] { DayLogic.sorted(Plan.today(on: now, calendar: calendar)) }
    private var completed: Set<String> { store.completed(on: now) }
    private var doneCount: Int { blocks.filter { completed.contains($0.id) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if notificationsDenied && !bannerDismissed { permissionBanner }
                NowCard(
                    block: DayLogic.currentBlock(blocks, now: now, completed: completed, calendar: calendar),
                    allDone: doneCount == blocks.count,
                    now: now,
                    completed: completed,
                    calendar: calendar,
                    onDone: { store.markDone($0, on: now) }
                )
                upNext
                dayList
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onReceive(tick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = .now
                store.reload()
                Task { await refreshNotifications() }
            }
        }
        .task {
            let granted = await NotificationScheduler.requestAuthorization()
            notificationsDenied = !granted
            await NotificationScheduler.register(Plan.blocks)
        }
        .sheet(isPresented: $showCoach) {
            CoachSheet(blocks: blocks, now: now, completed: completed)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.title2.weight(.semibold))
                Text("\(doneCount) / \(blocks.count) done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                showCoach = true
            } label: {
                Label("Coach", systemImage: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(.bordered)
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are off").font(.headline)
                Text("Blocks will not alert you when they start. The rest of the app works as usual.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
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
                        status: block.status(now: now, completed: completed, calendar: calendar),
                        subtitle: block.id == Plan.gymBlockID ? Plan.gymSession(on: now, calendar: calendar) : nil,
                        onToggle: { store.toggle(block.id, on: now) }
                    )
                    if block.id != blocks.last?.id { Divider().padding(.leading, 72) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func refreshNotifications() async {
        notificationsDenied = await NotificationScheduler.isDenied()
        await NotificationScheduler.register(Plan.blocks)
    }
}
