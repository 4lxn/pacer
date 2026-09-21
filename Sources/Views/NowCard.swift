import SwiftUI

struct NowCard: View {
    let block: Block?
    let allDone: Bool
    var behind = false
    let now: Date
    let completed: Set<String>
    let calendar: Calendar
    let onDone: (String) -> Void
    var onSkip: ((String) -> Void)? = nil
    var onReplan: ((String) -> Void)? = nil
    @State private var closing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaceLine(behind: behind && !allDone)
            if let block {
                let status = block.status(now: now, completed: completed, calendar: calendar)
                Text(status == .missed ? "OVERDUE" : "NOW")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(status == .missed ? .red : .accentColor)
                Text(block.label)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let start = block.start, let end = block.end {
                    HStack(spacing: 8) {
                        Text("\(NotificationScheduler.clock(start)) – \(NotificationScheduler.clock(end))")
                        if status == .current, let endDate = block.endDate(on: now, calendar: calendar) {
                            let minutes = max(0, Int(endDate.timeIntervalSince(now) / 60))
                            Text("· \(minutes) min left").contentTransition(.numericText())
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                Button {
                    // Closing is the reward: a beat of green and a checkmark before the card moves on.
                    guard !closing else { return }
                    withAnimation(.snappy(duration: 0.3)) { closing = true }
                    Task {
                        try? await Task.sleep(for: .milliseconds(420))
                        onDone(block.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if closing { Image(systemName: "checkmark").transition(.scale.combined(with: .opacity)) }
                        Text(closing ? "Closed" : "Done").contentTransition(.numericText())
                    }
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(closing ? .green : status == .missed ? .red : .accentColor)
                .scaleEffect(closing ? 1.03 : 1)
                .sensoryFeedback(.success, trigger: closing)
                if status == .missed {
                    HStack(spacing: 10) {
                        if let onReplan, block.kind != .free, !block.isAnchor {
                            Button { onReplan(block.id) } label: {
                                Label("Move it later", systemImage: "arrow.right.circle").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                        if let onSkip {
                            Button { onSkip(block.id) } label: {
                                Label("Skip today", systemImage: "minus.circle").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                }
            } else if allDone {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, options: .nonRepeating)
                Text("Day on pace").font(.largeTitle.weight(.bold))
                Text("Everything on the plan is closed. See you tomorrow.").foregroundStyle(.secondary)
            } else {
                Text("Nothing right now").font(.largeTitle.weight(.bold))
                Text("Next block is below.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
