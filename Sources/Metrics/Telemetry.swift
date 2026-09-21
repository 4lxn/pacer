import Foundation

/// Anonymous usage counts, once a day, so the fail-fast gates (docs/PRODUCT.md) have numbers:
/// a random id, the day, and a few integers from `MetricsStore`. No content, no health data, no
/// places, no account. Off with one switch in Settings; the id resets when it's turned off.
@MainActor
enum Telemetry {
    static let enabledKey = "telemetryEnabled"
    static let idKey = "telemetryID"
    private static let sentKey = "telemetrySent"   // dayKey -> hash of what was sent

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { UserDefaults.standard.removeObject(forKey: idKey); UserDefaults.standard.removeObject(forKey: sentKey) }
        }
    }

    static var id: String {
        if let id = UserDefaults.standard.string(forKey: idKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    /// What one day's ping carries. Pure so it can be tested.
    static func events(metrics: MetricsStore, dayKey: String, onPace: Bool) -> [String: Int] {
        func n(_ e: MetricsStore.Event) -> Int { metrics.count(e, dayKey: dayKey) }
        return [
            "opened": n(.appOpen),
            "closed": n(.doneApp) + n(.doneNotification) + n(.doneHealth),
            "closedHealth": n(.doneHealth),
            "checkInNotif": n(.checkInDone) + n(.checkInSkip) + n(.checkInReplan),
            "moved": n(.replanApp) + n(.replanNotification),
            "onPace": onPace ? 1 : 0,
        ]
    }

    /// Sends yesterday and today if their counts changed since the last send. Release builds only.
    static func ping(metrics: MetricsStore, mutator: DayMutator, now: Date = .now, session: URLSession = .shared) async {
        #if DEBUG
        return
        #else
        guard isEnabled, let base = CoachClient.proxyURL else { return }
        var sent = UserDefaults.standard.dictionary(forKey: sentKey) as? [String: Int] ?? [:]
        for offset in [1, 0] {
            guard let day = mutator.calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = mutator.dayKey(day)
            let events = events(metrics: metrics, dayKey: key, onPace: (mutator.score(on: day) ?? 0) >= DayLogic.paceThreshold)
            let hash = events.sorted { $0.key < $1.key }.description.hashValue
            if sent[key] == hash { continue }
            var request = URLRequest(url: base.appendingPathComponent("v1/ping"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id, "day": key, "events": events, "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""])
            if let (_, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 { sent[key] = hash }
        }
        if sent.count > 4 { sent = Dictionary(uniqueKeysWithValues: sent.sorted { $0.key > $1.key }.prefix(4).map { ($0.key, $0.value) }) }
        UserDefaults.standard.set(sent, forKey: sentKey)
        #endif
    }
}
