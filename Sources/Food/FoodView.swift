import SwiftUI

struct FoodView: View {
    @Bindable var food: FoodStore
    @State private var now = Date.now
    @State private var addingMeal = false
    @State private var editingItem: PantryItem?
    @State private var addingItem = false
    @State private var editingTargets = false

    var body: some View {
        NavigationStack {
            List {
                todaySection
                presetsSection
                mealsSection
                pantrySection
            }
            .navigationTitle("Food")
            .toolbar {
                Menu {
                    Button("Log a meal", systemImage: "fork.knife") { addingMeal = true }
                    Button("Add pantry item", systemImage: "basket") { addingItem = true }
                    Button("Targets", systemImage: "target") { editingTargets = true }
                } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $addingMeal) { MealForm { name, kcal, p, keep in food.log(name: name, kcal: kcal, proteinGrams: p, saveAsPreset: keep) } }
            .sheet(isPresented: $addingItem) { PantryForm(item: PantryItem(name: "", quantity: 1, unit: "pcs", minQuantity: 1)) { food.upsert($0) } }
            .sheet(item: $editingItem) { item in PantryForm(item: item) { food.upsert($0) } }
            .sheet(isPresented: $editingTargets) { TargetsForm(targets: food.targets) { food.targets = $0 } }
            .onAppear { now = .now }
        }
    }

    private var todaySection: some View {
        Section {
            let m = food.macros(on: now)
            macroRow("Calories", m.kcal, food.targets.kcal, "kcal")
            macroRow("Protein", m.proteinGrams, food.targets.proteinGrams, "g")
        } header: { Text("Today") }
    }

    private func macroRow(_ label: String, _ value: Int, _ target: Int, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value) / \(target) \(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(value, target)), total: Double(max(target, 1)))
                .tint(value >= target ? .green : .accentColor)
        }
    }

    private var presetsSection: some View {
        Section("Quick log") {
            if food.presets.isEmpty {
                Text("Log a meal and tick “save as quick log”.").foregroundStyle(.secondary)
            }
            ForEach(food.presets) { preset in
                Button { food.log(preset) } label: {
                    HStack {
                        Text(preset.name)
                        Spacer()
                        Text("\(preset.kcal) kcal · \(preset.proteinGrams) g").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions { Button(role: .destructive) { food.deletePreset(id: preset.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        }
    }

    private var mealsSection: some View {
        Section("Logged today") {
            let meals = food.meals(on: now)
            if meals.isEmpty { Text("Nothing yet.").foregroundStyle(.secondary) }
            ForEach(meals) { meal in
                HStack {
                    Text(meal.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    Text(meal.name)
                    Spacer()
                    Text("\(meal.kcal) · \(meal.proteinGrams) g").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .swipeActions { Button(role: .destructive) { food.deleteMeal(id: meal.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        }
    }

    private var pantrySection: some View {
        Section {
            let low = food.groceryList
            if !low.isEmpty {
                ShareLink(item: "Groceries\n" + food.groceryText()) {
                    Label("Need groceries: \(low.count) item\(low.count == 1 ? "" : "s") — share list", systemImage: "cart")
                }
            }
            if food.pantry.isEmpty {
                Text("Nothing in the pantry yet. Add items with + or ask the Coach: “add 1 kg of rice”.").foregroundStyle(.secondary)
            }
            ForEach(food.pantry.sorted { $0.name < $1.name }) { item in
                HStack {
                    Button { editingItem = item } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(item.isLow ? .red : .primary)
                            Text("\(FoodStore.format(item.quantity)) \(item.unit) · min \(FoodStore.format(item.minQuantity))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Stepper("", onIncrement: { food.adjust(id: item.id, by: step(item)) }, onDecrement: { food.adjust(id: item.id, by: -step(item)) })
                        .labelsHidden()
                }
                .swipeActions { Button(role: .destructive) { food.deleteItem(id: item.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        } header: { Text("Pantry") }
    }

    private func step(_ item: PantryItem) -> Double {
        switch item.unit {
        case "g", "ml": 100
        case "L", "kg": 0.5
        default: 1
        }
    }
}

struct MealForm: View {
    let onSave: (String, Int, Int, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var keep = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Meal", text: $name)
                TextField("kcal", text: $kcal).keyboardType(.numberPad)
                TextField("Protein (g)", text: $protein).keyboardType(.numberPad)
                Toggle("Save as quick log", isOn: $keep)
            }
            .navigationTitle("Log a meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        onSave(name.isEmpty ? "Meal" : name, Int(kcal) ?? 0, Int(protein) ?? 0, keep)
                        dismiss()
                    }
                    .disabled(Int(kcal) == nil)
                }
            }
        }
    }
}

struct PantryForm: View {
    @State var item: PantryItem
    let onSave: (PantryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var minimum = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $item.name)
                TextField("Unit (g, pcs, L, scoops)", text: $item.unit)
                TextField("Quantity", text: $quantity).keyboardType(.decimalPad)
                TextField("Minimum before it goes on the list", text: $minimum).keyboardType(.decimalPad)
            }
            .navigationTitle(item.name.isEmpty ? "New item" : item.name).navigationBarTitleDisplayMode(.inline)
            .onAppear {
                quantity = FoodStore.format(item.quantity)
                minimum = FoodStore.format(item.minQuantity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = item
                        saved.quantity = Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? saved.quantity
                        saved.minQuantity = Double(minimum.replacingOccurrences(of: ",", with: ".")) ?? saved.minQuantity
                        if saved.name.trimmingCharacters(in: .whitespaces).isEmpty { saved.name = "Item" }
                        if saved.unit.isEmpty { saved.unit = "pcs" }
                        onSave(saved)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TargetsForm: View {
    @State var targets: MacroTargets
    let onSave: (MacroTargets) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Calories: \(targets.kcal) kcal", value: $targets.kcal, in: 1200...5000, step: 50)
                Stepper("Protein: \(targets.proteinGrams) g", value: $targets.proteinGrams, in: 50...300, step: 5)
            }
            .navigationTitle("Daily targets").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(targets); dismiss() } }
            }
        }
    }
}
