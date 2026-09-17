import ActivityKit
import SwiftUI
import WidgetKit

struct PacerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PacerActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(Color(uiColor: .systemBackground).opacity(0.85))
                .activitySystemActionForegroundColor(Color.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                        Text(context.state.label).font(.headline).lineLimit(1)
                        if let place = context.state.place { Text(place).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: context.state.start...context.state.end, countsDown: true)
                            .font(.title3.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing)
                        Text("until \(context.state.end, style: .time)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if let next = context.state.nextLabel, let at = context.state.nextStart {
                                Text("Next: \(next) at \(at, style: .time)").font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                                .tint(.accentColor)
                        }
                        Button(intent: MarkDoneIntent(blockID: context.state.blockID, dayKey: context.state.dayKey)) {
                            Label("Done", systemImage: "checkmark").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent).tint(.accentColor)
                    }
                }
            } compactLeading: {
                Image(systemName: "circle.inset.filled").foregroundStyle(Color.accentColor)
            } compactTrailing: {
                Text(timerInterval: context.state.start...context.state.end, countsDown: true)
                    .font(.caption.monospacedDigit()).frame(maxWidth: 52).multilineTextAlignment(.trailing)
            } minimal: {
                ProgressView(timerInterval: context.state.start...context.state.end, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.circular).tint(.accentColor)
            }
            .widgetURL(URL(string: "autopiloto://today"))
            .keylineTint(Color.accentColor)
        }
    }
}

struct LockScreenActivityView: View {
    let state: PacerActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                Text(state.label).font(.title3.weight(.bold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(state.start, style: .time) – \(state.end, style: .time)")
                    if let place = state.place { Text("· \(place)") }
                }
                .font(.caption).foregroundStyle(.secondary)
                ProgressView(timerInterval: state.start...state.end, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .tint(.accentColor)
                if let next = state.nextLabel, let at = state.nextStart {
                    Text("Next: \(next) at \(at, style: .time) · \(state.done)/\(state.total) done").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(timerInterval: state.start...state.end, countsDown: true)
                    .font(.title2.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                Button(intent: MarkDoneIntent(blockID: state.blockID, dayKey: state.dayKey)) {
                    Label("Done", systemImage: "checkmark").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).tint(.accentColor)
            }
        }
        .padding(16)
    }
}


struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreenView(state: context.state)
                .activityBackgroundTint(Color(uiColor: .systemBackground).opacity(0.85))
                .activitySystemActionForegroundColor(.indigo)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FOCUS").font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                        Text(context.state.subject).font(.headline).lineLimit(1)
                        Text("since \(context.state.start, style: .time)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    focusClock(context.state).font(.title3.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let until = context.state.until {
                            ProgressView(timerInterval: context.state.start...until, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() }).tint(.indigo)
                        } else {
                            Text("Open session · \(context.state.todayMinutes) min today").font(.caption).foregroundStyle(.secondary)
                        }
                        Button(intent: StopFocusIntent()) { Label("Stop", systemImage: "stop.fill").font(.subheadline.weight(.semibold)) }
                            .buttonStyle(.borderedProminent).tint(.indigo)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.indigo)
            } compactTrailing: {
                focusClock(context.state).font(.caption.monospacedDigit()).frame(maxWidth: 52).multilineTextAlignment(.trailing)
            } minimal: {
                if let until = context.state.until {
                    ProgressView(timerInterval: context.state.start...until, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.circular).tint(.indigo)
                } else {
                    Image(systemName: "timer").foregroundStyle(.indigo)
                }
            }
            .widgetURL(URL(string: "autopiloto://focus"))
            .keylineTint(.indigo)
        }
    }

    @ViewBuilder
    private func focusClock(_ state: FocusActivityAttributes.ContentState) -> some View {
        if let until = state.until, until > .now {
            Text(timerInterval: state.start...until, countsDown: true)
        } else {
            Text(state.start, style: .timer)
        }
    }
}

struct FocusLockScreenView: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FOCUS").font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                Text(state.subject).font(.title3.weight(.bold)).lineLimit(1)
                Text("since \(state.start, style: .time) · \(state.todayMinutes) min today").font(.caption).foregroundStyle(.secondary)
                if let until = state.until {
                    ProgressView(timerInterval: state.start...until, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() }).tint(.indigo)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Group {
                    if let until = state.until, until > .now { Text(timerInterval: state.start...until, countsDown: true) } else { Text(state.start, style: .timer) }
                }
                .font(.title2.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                Button(intent: StopFocusIntent()) { Label("Stop", systemImage: "stop.fill").font(.subheadline.weight(.semibold)) }
                    .buttonStyle(.borderedProminent).tint(.indigo)
            }
        }
        .padding(16)
    }
}
