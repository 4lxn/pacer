import SwiftUI

struct BlockRow: View {
    let block: Block
    let status: BlockStatus
    let subtitle: String?
    var moved = false
    let onToggle: () -> Void
    var onOpen: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var onUnskip: (() -> Void)? = nil
    var onReplan: (() -> Void)? = nil

    var body: some View {
        Button(action: { (onOpen ?? onToggle)() }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: status == .done ? "checkmark.circle.fill" : status == .skipped ? "minus.circle" : "circle")
                        .font(.title3)
                        .foregroundStyle(status == .done ? Color.accentColor : .secondary)
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .symbolEffect(.bounce, value: status == .done)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(status == .done ? "Mark not done" : "Mark done")
                Text(timeText)
                    .font(.subheadline.monospacedDigit().weight(status == .missed ? .semibold : .regular))
                    .foregroundStyle(status == .missed ? .red : .secondary)
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
                        if moved {
                            Image(systemName: "arrow.right.circle").font(.caption).foregroundStyle(Color.accentColor)
                                .accessibilityLabel("Moved today")
                                .transition(.scale.combined(with: .opacity))
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
            } else if status != .done {
                if (status == .missed || status == .upcoming), block.kind != .free, !block.isAnchor, let onReplan {
                    Button("Move it later today", systemImage: "arrow.right.circle") { onReplan() }
                }
                if let onSkip { Button("Skip today", systemImage: "minus.circle") { onSkip() } }
            }
        }
        .accessibilityValue(accessibilityStatus)
    }

    private var timeText: String {
        guard let start = block.start else { return "any" }
        return NotificationScheduler.clock(start)
    }

    private var kindChip: some View {
        let text = status == .skipped ? "skipped" : status == .missed ? "missed" : block.kind.rawValue
        return Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status == .missed ? Color.red.opacity(0.12) : Color(uiColor: .tertiarySystemFill), in: Capsule())
            .foregroundStyle(status == .missed ? .red : .secondary)
            .contentTransition(.interpolate)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if status == .current { Color.accentColor.opacity(0.14) } else { Color.clear }
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
