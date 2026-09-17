import CoreLocation
import Foundation
import MapKit
import OSLog

/// Apple Maps for places: search → coordinates, and door-to-door minutes between pinned places.
/// No key, no server: MapKit on the device.
@MainActor
enum TravelEstimator {
    private static let log = Logger(subsystem: "com.alan.autopiloto", category: "maps")

    static func transport(_ mode: String) -> MKDirectionsTransportType {
        switch mode {
        case "walking": .walking
        case "transit": .transit
        default: .automobile
        }
    }

    /// Expected travel time (now, or leaving at `departure`), rounded up to 5 minutes, plus 5 for
    /// parking / finding the door.
    static func minutes(from a: Place, to b: Place, mode: String, departure: Date? = nil) async throws -> Int {
        guard let la = a.latitude, let lo = a.longitude, let lb = b.latitude, let lob = b.longitude else { throw EstimateError.notPinned }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: la, longitude: lo), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: lb, longitude: lob), address: nil)
        request.transportType = transport(mode)
        if let departure, departure > .now { request.departureDate = departure }
        let eta = try await MKDirections(request: request).calculateETA()
        let raw = Int(eta.expectedTravelTime / 60)
        return ((raw + 4) / 5) * 5 + 5
    }

    /// Re-asks Maps for every leg of today and tomorrow, leaving at (block start − the flat
    /// estimate), so rush hour counts. Only pinned pairs; typed matrix values stay the floor.
    static func refreshLegs(_ mutator: DayMutator, now: Date = .now) async {
        let days = mutator.days
        let calendar = mutator.calendar
        let todayKey = mutator.dayKey(now)
        for offset in 0..<2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let key = mutator.dayKey(day)
            var minutes: [String: Int] = [:]
            for (block, fromID, toID) in DayLogic.travelPairs(mutator.effectivePlan(on: day), places: days.places) {
                guard let from = days.places.place(id: fromID), let to = days.places.place(id: toID), from.isPinned, to.isPinned,
                      let start = block.startDate(on: day, calendar: calendar), start > now else { continue }
                let flat = days.places.minutes(from: fromID, to: toID)
                let departure = start.addingTimeInterval(-Double(flat) * 60)
                if let m = try? await self.minutes(from: from, to: to, mode: days.places.mode, departure: departure) {
                    minutes[block.id] = max(m, days.places.estimated.contains(Places.key(fromID, toID)) ? 0 : flat)
                }
            }
            days.setLegs(minutes, dayKey: key, keepFrom: todayKey)
        }
        await mutator.rearm()
    }

    /// Fills every estimable pair; typed values are left alone. Returns how many were set.
    @discardableResult
    static func estimateAll(_ days: DayStore) async -> Int {
        var count = 0
        for (a, b) in days.places.estimablePairs {
            do {
                let m = try await minutes(from: a, to: b, mode: days.places.mode)
                days.places.setTravel(a.id, b.id, minutes: m, estimated: true)
                count += 1
            } catch {
                log.error("ETA \(a.name) → \(b.name): \(error.localizedDescription)")
            }
        }
        return count
    }

    /// First Maps hit for a free-text address / name near the user's region.
    static func geocode(_ query: String) async throws -> (CLLocationCoordinate2D, String)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { return nil }
        return (item.location.coordinate, item.address?.shortAddress ?? item.name ?? query)
    }

    enum EstimateError: Error { case notPinned }
}

/// Search for the place form. MKLocalSearch (not the completer, which returns nothing for street
/// addresses in practice), debounced, biased to the area of the places already pinned.
@Observable
@MainActor
final class PlaceSearch {
    struct Hit: Identifiable, Hashable, Sendable {
        var id: String { "\(latitude),\(longitude)" }
        var name: String
        var address: String
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    private(set) var results: [Hit] = []
    private(set) var searching = false
    private(set) var lastError: String?
    var region: MKCoordinateRegion?
    private var task: Task<Void, Never>?

    func update(_ query: String) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { results = []; searching = false; return }
        searching = true
        task = Task { [region] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            request.resultTypes = [.address, .pointOfInterest]
            if let region { request.region = region }
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems.prefix(8).map { item in
                    Hit(name: item.name ?? q, address: item.address?.shortAddress ?? item.address?.fullAddress ?? "",
                        latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
                }
                lastError = results.isEmpty ? "No matches. Try a fuller address." : nil
            } catch {
                if !Task.isCancelled { lastError = error.localizedDescription; results = [] }
            }
            searching = false
        }
    }
}

/// One-shot "where am I" for pinning Home.
@MainActor
final class LocationOnce: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func request() async -> CLLocationCoordinate2D? {
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        return await withCheckedContinuation { c in
            continuation = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.continuation?.resume(returning: coordinate); self.continuation = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.continuation?.resume(returning: nil); self.continuation = nil }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
}
