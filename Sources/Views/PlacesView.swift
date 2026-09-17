import SwiftUI

/// Where things happen and how long it takes to get between them.
struct PlacesView: View {
    @Bindable var days: DayStore
    @State private var newName = ""
    @State private var editing: Place?

    private var places: [Place] { days.places.list }

    var body: some View {
        List {
            Section {
                ForEach(places) { place in
                    Button { editing = place } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(Color.primary)
                            if !place.note.isEmpty { Text(place.note).font(.caption).foregroundStyle(.secondary) }
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
                    ForEach(pairs, id: \.key) { pair in
                        Stepper(value: Binding(
                            get: { days.places.minutes(from: pair.a.id, to: pair.b.id) },
                            set: { days.places.setTravel(pair.a.id, pair.b.id, minutes: $0) }
                        ), in: 0...180, step: 5) {
                            HStack {
                                Text("\(pair.a.name) ↔ \(pair.b.name)")
                                Spacer()
                                let m = days.places.minutes(from: pair.a.id, to: pair.b.id)
                                Text(m == 0 ? "—" : "\(m) min").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                } header: { Text("Travel time") } footer: {
                    Text("Door to door, including changing or parking. The planner keeps this time free between blocks at different places and reminds you when to leave.")
                }
            }
        }
        .navigationTitle("Places & travel").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { place in
            PlaceForm(place: place) { days.places.upsert($0) }
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
        days.places.upsert(Place(name: name))
        newName = ""
    }
}

struct PlaceForm: View {
    @State var place: Place
    let onSave: (Place) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $place.name)
                TextField("Address or how to get there (optional)", text: $place.note, axis: .vertical).lineLimit(1...3)
            }
            .navigationTitle(place.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(place); dismiss() } }
            }
        }
    }
}
