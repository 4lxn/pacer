import Charts
import PhotosUI
import SwiftUI

struct FoodView: View {
    @Bindable var food: FoodStore
    @Bindable var account: CoachAccount
    @Bindable var agent: CoachAgent
    @State private var now = Date.now
    @State private var addingMeal = false
    @State private var estimating = false
    @State private var editingItem: PantryItem?
    @State private var addingItem = false
    @State private var editingTargets = false
    @State private var editingRecipe: Recipe?
    @State private var addingRecipe = false

    var body: some View {
        NavigationStack {
            List {
                todaySection
                presetsSection
                mealsSection
                recipesSection
                grocerySection
                pantrySection
            }
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { estimating = true } label: { Label("Describe a meal", systemImage: "sparkles") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Log a meal", systemImage: "fork.knife") { addingMeal = true }
                        Button("Describe a meal (AI)", systemImage: "sparkles") { estimating = true }
                        Button("Add recipe", systemImage: "frying.pan") { addingRecipe = true }
                        Button("Add pantry item", systemImage: "basket") { addingItem = true }
                        Button("Targets", systemImage: "target") { editingTargets = true }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $addingMeal) { MealForm { food.log(name: $0.name, kcal: $0.kcal, proteinGrams: $0.proteinGrams, carbsGrams: $0.carbsGrams, fatGrams: $0.fatGrams, saveAsPreset: $0.keep) } }
            .sheet(isPresented: $estimating) { MealEstimateSheet(account: account) { food.log(name: $0.name, kcal: $0.kcal, proteinGrams: $0.proteinGrams, carbsGrams: $0.carbsGrams, fatGrams: $0.fatGrams, saveAsPreset: $0.keep) } }
            .sheet(isPresented: $addingItem) { PantryForm(item: PantryItem(name: "", quantity: 1, unit: "pcs", minQuantity: 1)) { food.upsert($0) } }
            .sheet(item: $editingItem) { item in PantryForm(item: item) { food.upsert($0) } }
            .sheet(isPresented: $editingTargets) { TargetsForm(targets: food.targets, water: food.waterTarget) { food.targets = $0 } onWater: { food.waterTarget = $0 } }
            .sheet(isPresented: $addingRecipe) { RecipeForm(recipe: Recipe(name: "", ingredients: [], kcal: 0, proteinGrams: 0), pantry: food.pantry) { food.upsertRecipe($0) } }
            .sheet(item: $editingRecipe) { r in RecipeForm(recipe: r, pantry: food.pantry) { food.upsertRecipe($0) } }
            .onAppear { now = .now }
        }
    }

    // MARK: - Today

    private var todaySection: some View {
        Section {
            let m = food.macros(on: now)
            macroRow("Calories", m.kcal, food.targets.kcal, "kcal")
            macroRow("Protein", m.proteinGrams, food.targets.proteinGrams, "g")
            if food.targets.carbsGrams > 0 { macroRow("Carbs", m.carbsGrams, food.targets.carbsGrams, "g") }
            if food.targets.fatGrams > 0 { macroRow("Fat", m.fatGrams, food.targets.fatGrams, "g") }
            waterRow
            Button {
                let m = food.macros(on: now)
                agent.queued = "Plan my meals for the rest of today. I have \(max(0, food.targets.kcal - m.kcal)) kcal and \(max(0, food.targets.proteinGrams - m.proteinGrams)) g protein left. Use my pantry, recipes and quick-log presets, and my food rules; list each meal with a time and macros. Don't log anything yet."
            } label: {
                Label("Plan my meals with the Coach", systemImage: "sparkles")
            }
            weekChart
        } header: { Text("Today") } footer: {
            let left = food.targets.kcal - food.macros(on: now).kcal
            let avg = food.averages(days: 7, now: now)
            Text((left > 0 ? "\(left) kcal left · \(max(0, food.targets.proteinGrams - food.macros(on: now).proteinGrams)) g protein to go" : "Calories for today are in.")
                 + (avg.loggedDays > 1 ? "\n7-day average: \(avg.kcal) kcal · \(avg.protein) g protein" : ""))
        }
    }

    /// Tap a drop to fill it (and everything before it); tap the last filled one to undo.
    private var waterRow: some View {
        let glasses = food.water(on: now), target = max(food.waterTarget, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Water")
                Spacer()
                Text("\(glasses) / \(target) glasses").monospacedDigit().foregroundStyle(.secondary).contentTransition(.numericText())
            }
            HStack(spacing: 6) {
                ForEach(1...max(target, glasses), id: \.self) { i in
                    Button {
                        food.logWater(i <= glasses ? (i == glasses ? -1 : i - glasses) : i - glasses, on: now)
                    } label: {
                        Image(systemName: i <= glasses ? "drop.fill" : "drop")
                            .font(.title3)
                            .foregroundStyle(i <= glasses ? Color.cyan : Color(uiColor: .tertiaryLabel))
                            .frame(maxWidth: .infinity)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.increase, trigger: glasses)
        }
        .animation(.snappy, value: glasses)
    }

    private func macroRow(_ label: String, _ value: Int, _ target: Int, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value) / \(target) \(unit)").monospacedDigit().foregroundStyle(.secondary).contentTransition(.numericText())
            }
            ProgressView(value: Double(min(value, target)), total: Double(max(target, 1)))
                .tint(value >= target ? .green : .accentColor)
                .animation(.snappy, value: value)
        }
    }

    private var weekChart: some View {
        let days = food.kcalByDay(days: 7, now: now)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Last 7 days · kcal").font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(days, id: \.date) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.kcal))
                        .foregroundStyle(Calendar.current.isDate(day.date, inSameDayAs: now) ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", food.targets.kcal)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true) } }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 90)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Meals

    private var presetsSection: some View {
        Section("Quick log") {
            if food.presets.isEmpty {
                Text("Log a meal and tick “save as quick log”, or ask the Coach.").foregroundStyle(.secondary)
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
                .sensoryFeedback(.increase, trigger: food.meals.count)
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
                    Text(macroText(meal.kcal, meal.proteinGrams, meal.carbsGrams, meal.fatGrams)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .swipeActions { Button(role: .destructive) { food.deleteMeal(id: meal.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        }
    }

    private func macroText(_ kcal: Int, _ p: Int, _ c: Int, _ f: Int) -> String {
        var s = "\(kcal) · \(p) g"
        if c > 0 || f > 0 { s += " · \(c)C \(f)F" }
        return s
    }

    // MARK: - Recipes

    private var recipesSection: some View {
        Section {
            if food.recipes.isEmpty {
                Text("Save what you usually cook; “Cook” takes the ingredients from the pantry and logs the meal. The Coach can add recipes too.").foregroundStyle(.secondary)
            }
            let sorted = food.recipes.sorted { a, b in
                let ca = food.canCook(a), cb = food.canCook(b)
                return ca != cb ? ca : a.name < b.name
            }
            ForEach(sorted) { recipe in
                let missing = food.missing(for: recipe)
                HStack {
                    Button { editingRecipe = recipe } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name).foregroundStyle(.primary)
                            Text(missing.isEmpty ? "\(recipe.kcal) kcal · \(recipe.proteinGrams) g · ready to cook" : "missing \(missing.map(\.name).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(missing.isEmpty ? Color.secondary : Color.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("Cook") { food.cook(recipe, force: true) }
                        .buttonStyle(.glassProminent)
                        .tint(missing.isEmpty ? Color.accentColor : Color.gray)
                        .controlSize(.small)
                }
                .swipeActions { Button(role: .destructive) { food.deleteRecipe(id: recipe.id) } label: { Label("Delete", systemImage: "trash") } }
            }
        } header: {
            HStack {
                Text("Recipes")
                Spacer()
                let ready = food.recipes.filter(food.canCook).count
                if !food.recipes.isEmpty { Text("\(ready) ready").textCase(nil) }
            }
        }
    }

    // MARK: - Grocery + pantry

    private var grocerySection: some View {
        let low = food.groceryList
        return Section {
            if low.isEmpty {
                Text("Nothing to buy.").foregroundStyle(.secondary)
            }
            ForEach(low) { item in
                Button { food.restock(id: item.id) } label: {
                    HStack {
                        Image(systemName: "circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(.primary)
                            Text("have \(FoodStore.format(item.quantity)) \(item.unit) · want \(FoodStore.format(item.minQuantity * 2))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .accessibilityHint("Mark as bought")
            }
            if !low.isEmpty {
                ShareLink(item: "Groceries\n" + food.groceryText()) { Label("Share list", systemImage: "square.and.arrow.up") }
            }
        } header: {
            HStack { Text("Groceries"); Spacer(); if !low.isEmpty { Text("\(low.count) to buy · tap when bought").textCase(nil) } }
        }
    }

    private var pantrySection: some View {
        Section {
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

struct LoggedMeal {
    var name: String
    var kcal: Int
    var proteinGrams: Int
    var carbsGrams = 0
    var fatGrams = 0
    var keep = false
}

struct MealForm: View {
    let onSave: (LoggedMeal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var keep = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Meal", text: $name)
                TextField("kcal", text: $kcal).keyboardType(.numberPad)
                TextField("Protein (g)", text: $protein).keyboardType(.numberPad)
                TextField("Carbs (g, optional)", text: $carbs).keyboardType(.numberPad)
                TextField("Fat (g, optional)", text: $fat).keyboardType(.numberPad)
                Toggle("Save as quick log", isOn: $keep)
            }
            .navigationTitle("Log a meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        onSave(LoggedMeal(name: name.isEmpty ? "Meal" : name, kcal: Int(kcal) ?? 0, proteinGrams: Int(protein) ?? 0, carbsGrams: Int(carbs) ?? 0, fatGrams: Int(fat) ?? 0, keep: keep))
                        dismiss()
                    }
                    .disabled(Int(kcal) == nil)
                }
            }
        }
    }
}

/// "2 eggs, toast with avocado" or a photo → the model estimates → you fix → Log.
struct MealEstimateSheet: View {
    @Bindable var account: CoachAccount
    let onLog: (LoggedMeal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var picked: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var guess: MealGuess?
    @State private var busy = false
    @State private var error: String?
    @State private var keep = false
    @FocusState private var focused: Bool

    private var client: CoachClient? {
        if let key = APIKeyStore.load(), !key.isEmpty { return CoachClient(apiKey: key) }
        if let proxy = CoachClient.proxyURL, let token = account.sessionToken, account.isSubscribed { return CoachClient(proxy: proxy, sessionToken: token) }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you eat? e.g. 2 eggs, toast with avocado", text: $text, axis: .vertical).lineLimit(2...4).focused($focused)
                    let photoLabel = photo == nil ? "Add a photo" : "Change photo"
                    HStack {
                        PhotosPicker(selection: $picked, matching: .images) { Label(photoLabel, systemImage: "photo") }
                        Spacer()
                        if let photo { Image(uiImage: photo).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    }
                    Button {
                        Task { await estimate() }
                    } label: {
                        HStack { if busy { ProgressView() }; Text(busy ? "Estimating…" : "Estimate") }
                    }
                    .disabled(busy || (text.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil) || client == nil)
                } footer: {
                    Text(client == nil ? "Set up the Coach (key or subscription) to estimate meals." : "The model guesses portions; adjust before logging.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if guess != nil {
                    Section("Estimate") {
                        TextField("Name", text: Binding(get: { guess?.name ?? "" }, set: { guess?.name = $0 }))
                        Stepper("\(guess?.kcal ?? 0) kcal", value: Binding(get: { guess?.kcal ?? 0 }, set: { guess?.kcal = $0 }), in: 0...3000, step: 10)
                        Stepper("\(guess?.proteinGrams ?? 0) g protein", value: Binding(get: { guess?.proteinGrams ?? 0 }, set: { guess?.proteinGrams = $0 }), in: 0...300, step: 1)
                        Stepper("\(guess?.carbsGrams ?? 0) g carbs", value: Binding(get: { guess?.carbsGrams ?? 0 }, set: { guess?.carbsGrams = $0 }), in: 0...500, step: 1)
                        Stepper("\(guess?.fatGrams ?? 0) g fat", value: Binding(get: { guess?.fatGrams ?? 0 }, set: { guess?.fatGrams = $0 }), in: 0...300, step: 1)
                        if let note = guess?.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                        Toggle("Save as quick log", isOn: $keep)
                    }
                }
            }
            .navigationTitle("Describe a meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        if let g = guess { onLog(LoggedMeal(name: g.name, kcal: g.kcal, proteinGrams: g.proteinGrams, carbsGrams: g.carbsGrams ?? 0, fatGrams: g.fatGrams ?? 0, keep: keep)) }
                        dismiss()
                    }
                    .disabled(guess == nil)
                }
            }
            .task(id: picked) {
                if let picked, let data = try? await picked.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
            }
            .onAppear { focused = true }
        }
    }

    private func estimate() async {
        guard let client else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let description = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let reply: String
            if let photo, let jpeg = photo.jpegData(compressionQuality: 0.6) {
                reply = try await client.describe(jpeg: jpeg, prompt: MealGuess.prompt + (description.isEmpty ? "" : "\nThe user says: \(description)"))
            } else {
                reply = try await client.ask("Meal: \(description)", staticSystem: "You estimate nutrition. " + MealGuess.prompt, snapshot: "")
            }
            guess = MealGuess.parse(reply)
            if guess == nil { error = "Couldn't read the estimate; try again or log by hand." }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RecipeForm: View {
    @State var recipe: Recipe
    let pantry: [PantryItem]
    let onSave: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var newAmount = ""
    @State private var newUnit = "g"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Recipe name", text: $recipe.name)
                    TextField("How to make it (optional)", text: $recipe.note, axis: .vertical).lineLimit(1...3)
                }
                Section("Per serving") {
                    Stepper("\(recipe.kcal) kcal", value: $recipe.kcal, in: 0...3000, step: 10)
                    Stepper("\(recipe.proteinGrams) g protein", value: $recipe.proteinGrams, in: 0...300, step: 1)
                    Stepper("\(recipe.carbsGrams) g carbs", value: $recipe.carbsGrams, in: 0...500, step: 1)
                    Stepper("\(recipe.fatGrams) g fat", value: $recipe.fatGrams, in: 0...300, step: 1)
                }
                Section("Ingredients (from the pantry)") {
                    ForEach(recipe.ingredients.indices, id: \.self) { i in
                        let ing = recipe.ingredients[i]
                        HStack {
                            Text(ing.name)
                            Spacer()
                            Text("\(FoodStore.format(ing.amount)) \(ing.unit)").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { recipe.ingredients.remove(atOffsets: $0) }
                    HStack {
                        TextField("Item", text: $newName)
                        TextField("Amount", text: $newAmount).keyboardType(.decimalPad).frame(width: 70)
                        TextField("Unit", text: $newUnit).frame(width: 50)
                        Button { addIngredient() } label: { Image(systemName: "plus.circle.fill") }
                            .disabled(newName.isEmpty || Double(newAmount.replacingOccurrences(of: ",", with: ".")) == nil)
                    }
                    if !pantry.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(pantry.sorted { $0.name < $1.name }) { item in
                                    Button(item.name) { newName = item.name; newUnit = item.unit }
                                        .buttonStyle(.glass).controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(recipe.name.isEmpty ? "New recipe" : recipe.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var r = recipe
                        if r.name.trimmingCharacters(in: .whitespaces).isEmpty { r.name = "Recipe" }
                        onSave(r); dismiss()
                    }
                }
            }
        }
    }

    private func addIngredient() {
        guard let amount = Double(newAmount.replacingOccurrences(of: ",", with: ".")) else { return }
        recipe.ingredients.append(Recipe.Ingredient(name: newName, amount: amount, unit: newUnit.isEmpty ? "pcs" : newUnit))
        newName = ""; newAmount = ""
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
    @State var water: Int = 8
    let onSave: (MacroTargets) -> Void
    var onWater: ((Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Calories: \(targets.kcal) kcal", value: $targets.kcal, in: 1200...5000, step: 50)
                Stepper("Protein: \(targets.proteinGrams) g", value: $targets.proteinGrams, in: 50...300, step: 5)
                Stepper(targets.carbsGrams == 0 ? "Carbs: not tracked" : "Carbs: \(targets.carbsGrams) g", value: $targets.carbsGrams, in: 0...600, step: 10)
                Stepper(targets.fatGrams == 0 ? "Fat: not tracked" : "Fat: \(targets.fatGrams) g", value: $targets.fatGrams, in: 0...300, step: 5)
                Stepper("Water: \(water) glasses", value: $water, in: 2...20)
            }
            .navigationTitle("Daily targets").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(targets); onWater?(water); dismiss() } }
            }
        }
    }
}
