import MapKit
import SwiftUI

/// Where things happen and how long it takes to get between them. Pin places with Apple Maps and
/// let it estimate the minutes; type over anything it gets wrong.
struct PlacesView: View {
    @Bindable var days: DayStore
    @State private var newName = ""
    @State private var editing: Place?
    @State private var estimating = false
    @State private var estimated: Int?

    private var places: [Place] { days.places.list }

    var body: some View {
        List {
            Section {
                ForEach(places) { place in
                    Button { editing = place } label: {
                        HStack {
                            Image(systemName: place.isPinned ? "mappin.circle.fill" : "mappin.circle").foregroundStyle(place.isPinned ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(Color.primary)
                                Text(place.note.isEmpty ? (place.isPinned ? "Pinned" : "Not pinned — tap to find it on the map") : place.note).font(.caption).foregroundStyle(Color.secondary).lineLimit(1)
                            }
                        }
                    }
                    .swipeActions {
                        if place.id != Place.homeID {
                            Button(role: .destructive) { days.places.remove(id: place.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                HStack {
                    TextField("New place (Office, Gym, Track…)", text: $newName)
                    Button { add() } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Places") } footer: {
                Text("Give a block a place in its editor. Blocks without a place happen wherever you already are.")
            }

            if places.count > 1 {
                Section {
                    Picker("Getting around", selection: $days.places.mode) {
                        Label("Driving", systemImage: "car").tag("driving")
                        Label("Walking", systemImage: "figure.walk").tag("walking")
                        Label("Transit", systemImage: "tram").tag("transit")
                    }
                    .pickerStyle(.segmented)
                    let pinnedPairs = days.places.estimablePairs.count
                    Button {
                        Task { estimating = true; estimated = await TravelEstimator.estimateAll(days); estimating = false }
                    } label: {
                        HStack {
                            Label(estimating ? "Asking Maps…" : "Estimate with Apple Maps", systemImage: "map")
                            Spacer()
                            if estimating { ProgressView() } else if let estimated { Text("\(estimated) updated").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(estimating || pinnedPairs == 0)
                    ForEach(pairs, id: \.key) { pair in
                        Stepper(value: Binding(
                            get: { days.places.minutes(from: pair.a.id, to: pair.b.id) },
                            set: { days.places.setTravel(pair.a.id, pair.b.id, minutes: $0) }
                        ), in: 0...180, step: 5) {
                            HStack {
                                Text("\(pair.a.name) ↔ \(pair.b.name)")
                                Spacer()
                                let m = days.places.minutes(from: pair.a.id, to: pair.b.id)
                                if days.places.estimated.contains(pair.key) { Image(systemName: "map").font(.caption2).foregroundStyle(.secondary) }
                                Text(m == 0 ? "—" : "\(m) min").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } header: { Text("Travel time") } footer: {
                    Text("Maps gives the trip now, rounded up plus 5 min for the door. Pairs with a map icon were estimated; change one by hand and it stays yours. The planner keeps this time free between blocks at different places and reminds you when to leave.")
                }
            }
        }
        .navigationTitle("Places & travel").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { place in
            PlaceForm(place: place) { saved in
                let wasPinned = days.places.place(id: saved.id)?.isPinned ?? false
                days.places.upsert(saved)
                if saved.isPinned && !wasPinned { Task { await TravelEstimator.estimateAll(days) } }
            }
        }
        .onChange(of: days.places.mode) { _, _ in Task { await TravelEstimator.estimateAll(days) } }
        .onAppear {
            #if DEBUG
            if CoachAccount.screenshotMode == "places" { Task { estimating = true; estimated = await TravelEstimator.estimateAll(days); estimating = false } }
            #endif
        }
    }

    private var pairs: [(key: String, a: Place, b: Place)] {
        var out: [(String, Place, Place)] = []
        for (i, a) in places.enumerated() {
            for b in places[(i + 1)...] { out.append((Places.key(a.id, b.id), a, b)) }
        }
        return out
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let place = Place(name: name)
        days.places.upsert(place)
        newName = ""
        editing = days.places.list.first { $0.name == name }   // straight into pinning it
    }
}

struct PlaceForm: View {
    @State var place: Place
    let onSave: (Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @State private var query = ""
    @State private var locating = false
    @State private var position: MapCameraPosition = .automatic
    @FocusState private var searchFocused: Bool

    private var coordinate: CLLocationCoordinate2D? {
        guard let la = place.latitude, let lo = place.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $place.name)
                }
                Section {
                    TextField("Search Apple Maps (address or name)", text: $query).focused($searchFocused)
                        .onChange(of: query) { _, q in search.update(q) }
                    ForEach(search.results, id: \.self) { r in
                        Button {
                            Task { await pick(r) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).foregroundStyle(Color.primary)
                                Text(r.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack { Label("Use my current location", systemImage: "location.fill"); if locating { Spacer(); ProgressView() } }
                    }
                    .disabled(locating)
                } header: { Text("Pin it") } footer: {
                    Text(place.isPinned ? "Pinned. Travel times to other pinned places can be estimated with Maps." : "Pin the place so Maps can estimate travel times; or type the minutes by hand.")
                }
                if let coordinate {
                    Section {
                        Map(position: $position) {
                            Marker(place.name.isEmpty ? "Here" : place.name, coordinate: coordinate).tint(Color.accentColor)
                        }
                        .frame(height: 180)
                        .listRowInsets(EdgeInsets())
                        .allowsHitTesting(false)
                        if !place.note.isEmpty { Text(place.note).font(.caption).foregroundStyle(.secondary) }
                        Button("Unpin", role: .destructive) { place.latitude = nil; place.longitude = nil; place.note = "" }
                    }
                }
            }
            .navigationTitle(place.name.isEmpty ? "New place" : place.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if place.name.trimmingCharacters(in: .whitespaces).isEmpty { place.name = "Place" }
                        onSave(place); dismiss()
                    }
                }
            }
            .onAppear {
                if let coordinate { position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800)) }
                else { searchFocused = true }
            }
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        guard let (coord, address) = await search.resolve(completion) else { return }
        set(coord, address: address)
        query = ""; search.update("")
        searchFocused = false
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        guard let coord = await LocationOnce().request() else { return }
        let address = (try? await TravelEstimator.geocode("\(coord.latitude), \(coord.longitude)"))?.1 ?? "Current location"
        set(coord, address: address)
    }

    private func set(_ coord: CLLocationCoordinate2D, address: String) {
        place.latitude = coord.latitude; place.longitude = coord.longitude; place.note = address
        position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800))
    }
}
