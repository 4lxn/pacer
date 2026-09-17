import CoreLocation
import Foundation
import OSLog
import WeatherKit

/// Today's weather for the pinned Home place (Apple WeatherKit, on device, no key). Sets the
/// closet's weather bucket so the outfit matches the day.
@Observable
@MainActor
final class WeatherNow {
    struct Summary: Equatable {
        var tempC: Double
        var highC: Double
        var lowC: Double
        var condition: String
        var symbol: String
        var rainChance: Double   // 0…1 for today
        var fetchedAt: Date

        var bucket: Weather { highC >= 27 ? .hot : highC <= 17 ? .cold : .mild }
        var line: String {
            let rain = rainChance >= 0.3 ? " · \(Int((rainChance * 100).rounded()))% rain" : ""
            return "\(Int(tempC.rounded()))° now · \(Int(lowC.rounded()))–\(Int(highC.rounded()))° · \(condition)\(rain)"
        }
    }

    private(set) var summary: Summary?
    private(set) var lastError: String?
    private let log = Logger(subsystem: "com.alan.autopiloto", category: "weather")

    /// Refreshes at most every 30 minutes.
    func refresh(latitude: Double, longitude: Double, now: Date = .now) async {
        if let s = summary, now.timeIntervalSince(s.fetchedAt) < 1800 { return }
        do {
            let weather = try await WeatherService.shared.weather(for: CLLocation(latitude: latitude, longitude: longitude), including: .current, .daily)
            let today = weather.1.first
            summary = Summary(
                tempC: weather.0.temperature.converted(to: .celsius).value,
                highC: today?.highTemperature.converted(to: .celsius).value ?? weather.0.temperature.converted(to: .celsius).value,
                lowC: today?.lowTemperature.converted(to: .celsius).value ?? weather.0.temperature.converted(to: .celsius).value,
                condition: weather.0.condition.description,
                symbol: weather.0.symbolName,
                rainChance: today?.precipitationChance ?? 0,
                fetchedAt: now
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("WeatherKit: \(error.localizedDescription)")
        }
    }
}
