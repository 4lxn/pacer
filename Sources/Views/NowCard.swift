import SwiftUI

struct NowCard: View {
    let block: Block?
    let allDone: Bool
    let now: Date
    let completed: Set<String>
    let calendar: Calendar
    let onDone: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            Text("· \(minutes) min left")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                Button {
                    onDone(block.id)
                } label: {
                    Text("Done")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(status == .missed ? .red : .accentColor)
            } else if allDone {
                Text("All done for today").font(.largeTitle.weight(.bold))
                Text("Nothing left on the plan.").foregroundStyle(.secondary)
            } else {
                Text("Nothing right now").font(.largeTitle.weight(.bold))
                Text("Next block is below.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
