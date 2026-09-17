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

    /// Expected travel time now, rounded up to 5 minutes, plus 5 for parking / finding the door.
    static func minutes(from a: Place, to b: Place, mode: String) async throws -> Int {
        guard let la = a.latitude, let lo = a.longitude, let lb = b.latitude, let lob = b.longitude else { throw EstimateError.notPinned }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: la, longitude: lo), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: lb, longitude: lob), address: nil)
        request.transportType = transport(mode)
        let eta = try await MKDirections(request: request).calculateETA()
        let raw = Int(eta.expectedTravelTime / 60)
        return ((raw + 4) / 5) * 5 + 5
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

/// Autocomplete for the place form.
@Observable
@MainActor
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ query: String) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { results = []; completer.cancel() } else { completer.queryFragment = query }
    }

    /// Resolve a suggestion to coordinates + a short address.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (CLLocationCoordinate2D, String)? {
        guard let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start(),
              let item = response.mapItems.first else { return nil }
        return (item.location.coordinate, item.address?.shortAddress ?? completion.title)
    }

    // The completer calls back on the main thread (preconcurrency conformance keeps this isolated).
    func completer(_ completer: MKLocalSearchCompleter, didUpdateResults results: [MKLocalSearchCompletion]) {
        self.results = results
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
