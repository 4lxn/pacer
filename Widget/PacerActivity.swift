import ActivityKit
import AppIntents
import Foundation

/// The current block, live in the Dynamic Island and on the Lock Screen.
struct PacerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var blockID: String
        var label: String
        var start: Date
        var end: Date
        var place: String?
        var nextLabel: String?
        var nextStart: Date?
        var done: Int
        var total: Int
        var dayKey: String
    }
    var startedAt: Date = .now
}

/// "Done" from the Live Activity. Runs inside the app's process, so the app delegate can route it
/// through DayMutator; the notification is the hand-off.
struct MarkDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark done"
    static let isDiscoverable = false

    @Parameter(title: "Block") var blockID: String
    @Parameter(title: "Day") var dayKey: String

    init() {}
    init(blockID: String, dayKey: String) { self.blockID = blockID; self.dayKey = dayKey }

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .pacerMarkDone, object: nil, userInfo: ["blockID": blockID, "dayKey": dayKey])
        return .result()
    }
}

extension Notification.Name {
    static let pacerMarkDone = Notification.Name("com.alan.autopiloto.markDone")
}


/// A focus session: subject, when it started, when the focus target ends (nil = open).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var subject: String
        var start: Date
        var until: Date?
        var todayMinutes: Int
    }
    var startedAt: Date = .now
}

struct StopFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop focus"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .pacerStopFocus, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let pacerStopFocus = Notification.Name("com.alan.autopiloto.stopFocus")
}
