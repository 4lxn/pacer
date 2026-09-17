import SwiftUI

struct BlockRow: View {
    let block: Block
    let status: BlockStatus
    let subtitle: String?
    let onToggle: () -> Void
    var onSkip: (() -> Void)? = nil
    var onUnskip: (() -> Void)? = nil

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: status == .done ? "checkmark.circle.fill" : status == .skipped ? "minus.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(status == .done ? Color.accentColor : .secondary)
                Text(timeText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(block.label)
                            .strikethrough(status == .done || status == .skipped)
                            .fontWeight(status == .current ? .semibold : .regular)
                        if block.isAnchor {
                            Image(systemName: "anchor").font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Anchor")
                        }
                    }
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                kindChip
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .foregroundStyle(status == .done || status == .skipped ? .secondary : .primary)
            .opacity(status == .done || status == .skipped ? 0.6 : 1)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if status == .skipped, let onUnskip {
                Button("Back on today's plan", systemImage: "arrow.uturn.backward") { onUnskip() }
            } else if status != .done, let onSkip {
                Button("Skip today", systemImage: "minus.circle") { onSkip() }
            }
        }
        .accessibilityValue(accessibilityStatus)
    }

    private var timeText: String {
        guard let start = block.start else { return "any" }
        return NotificationScheduler.clock(start)
    }

    private var kindChip: some View {
        Text(status == .skipped ? "skipped" : block.kind.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var rowBackground: some View {
        switch status {
        case .current: Color.accentColor.opacity(0.14)
        case .missed: Color.red.opacity(0.10)
        default: Color.clear
        }
    }

    private var accessibilityStatus: String {
        switch status {
        case .done: "done"
        case .skipped: "skipped today"
        case .current: "current"
        case .upcoming: "upcoming"
        case .missed: "missed"
        case .free: "anytime"
        }
    }
}
