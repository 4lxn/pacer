import Foundation

/// Tools the Coach can call. Definitions are plain JSON schemas; `run` executes on the main actor
/// against the app's stores and returns text for the model plus an optional one-line summary for
/// the transcript (writes only).
@MainActor
struct CoachTools {
    let plan: PlanStore
    let completions: CompletionStore
    let food: FoodStore
    let wardrobe: WardrobeStore
    let health: HealthStore
    let track: TrackStore
    let mutator: DayMutator
    var calendar: Calendar = .current
    var now: () -> Date = { .now }

    struct Result {
        var output: String
        var summary: String?
        var isError = false
    }

    // MARK: - Definitions

    static let definitions: [[String: Any]] = [
        // Plan
        tool("get_plan", "Today's blocks with ids, times and status (done, current, upcoming, missed, skipped). Blocks moved for today only are marked 'moved'.", [:]),
        tool("add_block", "Add a block to the weekly plan, or with today_only=true a one-off block for today only (the plan is unchanged). Times are HH:MM 24h. kind: fixed (notifies at start), window (anytime in range), free (no clock).", [
            "label": str("Short label"), "kind": enumOf(["fixed", "window", "free"]),
            "start": str("HH:MM, omit for free"), "end": str("HH:MM, omit for free"),
            "weekdays": ["type": "array", "items": ["type": "integer"], "description": "1=Sunday…7=Saturday; omit for every day"],
            "today_only": ["type": "boolean", "description": "true = just for today"],
        ], required: ["label", "kind"]),
        tool("set_block_note", "Attach a short note to a block for today only (e.g. what to do in that block). Empty note removes it.", [
            "id": str("Block id"), "note": str("The note"),
        ], required: ["id", "note"]),
        tool("update_block", "Change a block's label, times, kind or weekdays. Only pass the fields to change.", [
            "id": str("Block id from get_plan"), "label": str(""), "kind": enumOf(["fixed", "window", "free"]),
            "start": str("HH:MM"), "end": str("HH:MM"),
            "weekdays": ["type": "array", "items": ["type": "integer"], "description": "1=Sunday…7=Saturday"],
        ], required: ["id"]),
        tool("delete_block", "Delete a block. Ask the user first; then call with confirm=true. The anchor cannot be deleted.", [
            "id": str("Block id"), "confirm": ["type": "boolean"],
        ], required: ["id", "confirm"]),
        tool("mark_done", "Mark a block done for today (or undo with done=false).", [
            "id": str("Block id"), "done": ["type": "boolean", "description": "default true"],
        ], required: ["id"]),
        tool("skip_today", "Skip a block for today only (it leaves today's count; the plan is unchanged). undo=true puts it back.", [
            "id": str("Block id"), "undo": ["type": "boolean"],
        ], required: ["id"]),
        tool("move_today", "Move a missed or upcoming block to later TODAY only (the weekly plan is unchanged). Omit start to let the app find the first free slot after now; pass start (HH:MM) to place it there. Later windows are pushed forward if needed. Use update_block instead to change the plan permanently.", [
            "id": str("Block id"), "start": str("HH:MM; omit for the first free slot"),
        ], required: ["id"]),
        tool("undo_replan", "Undo the last move_today or skip_today made today.", [:]),
        // Food
        tool("get_pantry", "Pantry items with quantity, unit and minimum; items below minimum are on the grocery list.", [:]),
        tool("add_pantry_item", "Add a pantry item, or set quantity/unit/minimum of an existing one with the same name.", [
            "name": str("Item name"), "quantity": num("Amount on hand"), "unit": str("g, pcs, L, scoops…"),
            "min_quantity": num("Below this it goes on the grocery list; default = half of quantity"),
        ], required: ["name", "quantity", "unit"]),
        tool("adjust_pantry", "Add (positive) or remove (negative) an amount from a pantry item, e.g. after cooking or shopping.", [
            "name": str("Item name"), "delta": num("Amount to add; negative to remove"),
        ], required: ["name", "delta"]),
        tool("delete_pantry_item", "Remove an item from the pantry entirely.", ["name": str("Item name")], required: ["name"]),
        tool("get_grocery_list", "Items below their minimum, with how much to buy.", [:]),
        tool("get_meals_today", "Meals logged today with ids, plus totals vs targets, and the quick-log presets.", [:]),
        tool("log_meal", "Log a meal eaten today. Estimate calories and macros from the description when the user doesn't give them (say what you assumed).", [
            "name": str("Meal name"), "kcal": ["type": "integer"], "protein_grams": ["type": "integer"],
            "carbs_grams": ["type": "integer"], "fat_grams": ["type": "integer"],
        ], required: ["name", "kcal", "protein_grams"]),
        tool("get_recipes", "Saved recipes with ingredients, macros and whether the pantry can cook them now.", [:]),
        tool("add_recipe", "Save or update a recipe: ingredients matched to pantry items by name.", [
            "name": str("Recipe name"), "kcal": ["type": "integer"], "protein_grams": ["type": "integer"],
            "carbs_grams": ["type": "integer"], "fat_grams": ["type": "integer"], "note": str("How to make it, one line"),
            "ingredients": ["type": "array", "items": ["type": "object", "properties": ["name": str("Pantry item name"), "amount": num(""), "unit": str("")], "required": ["name", "amount", "unit"]]],
        ], required: ["name", "kcal", "protein_grams", "ingredients"]),
        tool("cook_recipe", "Cook a recipe now: deducts its ingredients from the pantry and logs the meal. Fails if something is missing unless force=true.", [
            "name": str("Recipe name"), "force": ["type": "boolean"],
        ], required: ["name"]),
        tool("delete_recipe", "Delete a recipe by name.", ["name": str("")], required: ["name"]),
        tool("delete_meal", "Delete a logged meal by id (from get_meals_today).", ["id": str("Meal id")], required: ["id"]),
        tool("set_targets", "Set the daily calorie / protein / carbs / fat targets (carbs and fat 0 = not tracked).", [
            "kcal": ["type": "integer"], "protein_grams": ["type": "integer"], "carbs_grams": ["type": "integer"], "fat_grams": ["type": "integer"],
        ]),
        tool("add_preset", "Add or update a quick-log meal preset.", [
            "name": str(""), "kcal": ["type": "integer"], "protein_grams": ["type": "integer"],
        ], required: ["name", "kcal", "protein_grams"]),
        tool("delete_preset", "Delete a quick-log preset by name.", ["name": str("")], required: ["name"]),
        // Closet
        tool("get_closet", "All garments with category, color, warmth, style, wear count and laundry status. Also the current weather/style setting.", [:]),
        tool("add_garment", "Add a garment to the closet from a description (no photo).", [
            "name": str("e.g. navy hoodie"), "category": enumOf(["top", "bottom", "shoes", "outer", "accessory"]),
            "color": str(""), "warmth": ["type": "integer", "description": "1 light, 2 mid, 3 warm"],
            "formality": enumOf(["sport", "casual", "smart"]), "wash_after": ["type": "integer", "description": "wears before washing; 0 never"],
        ], required: ["name", "category", "color"]),
        tool("update_garment", "Change a garment's fields. Only pass what changes.", [
            "name": str("Current name"), "new_name": str(""), "category": enumOf(["top", "bottom", "shoes", "outer", "accessory"]),
            "color": str(""), "warmth": ["type": "integer"], "formality": enumOf(["sport", "casual", "smart"]),
            "wash_after": ["type": "integer"],
        ], required: ["name"]),
        tool("delete_garment", "Remove a garment from the closet.", ["name": str("")], required: ["name"]),
        tool("wear_outfit", "Log that the user is wearing these garments today (bumps wear counts).", [
            "names": ["type": "array", "items": ["type": "string"], "description": "Garment names"],
        ], required: ["names"]),
        tool("mark_washed", "Reset wear count after washing. Pass names, or all=true for the whole laundry pile.", [
            "names": ["type": "array", "items": ["type": "string"]], "all": ["type": "boolean"],
        ]),
        tool("set_closet_context", "Set today's weather and/or style used for outfit suggestions.", [
            "weather": enumOf(["cold", "mild", "hot"]), "style": enumOf(["sport", "casual", "smart"]),
        ]),
        // Study & income
        tool("get_study", "Study minutes today and this week vs goal, running session, recent sessions with ids.", [:]),
        tool("add_study_session", "Log a study session after the fact.", [
            "minutes": ["type": "integer"], "topic": str(""), "start": str("HH:MM today; default = now minus minutes"),
        ], required: ["minutes"]),
        tool("delete_study_session", "Delete a study session by id (from get_study).", ["id": str("")], required: ["id"]),
        tool("set_study_goal", "Set the weekly study goal in minutes.", ["minutes": ["type": "integer"]], required: ["minutes"]),
        tool("get_income", "This month's income entries with ids, per-source totals, month and year totals.", [:]),
        tool("add_income", "Log income.", [
            "source": str("salary, freelance…"), "amount": num("In the user's currency"), "date": str("YYYY-MM-DD; default today"),
        ], required: ["source", "amount"]),
        tool("delete_income", "Delete an income entry by id (from get_income).", ["id": str("")], required: ["id"]),
        // Memory
        tool("remember", "Save a durable fact or preference about the user to the Coach profile's Memory section.", [
            "note": str("One line, e.g. 'hates broccoli' or 'gym closed on Sundays'"),
        ], required: ["note"]),
        tool("forget", "Remove Memory lines containing this text.", ["text": str("")], required: ["text"]),
    ]

    private static func tool(_ name: String, _ description: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "input_schema": ["type": "object", "properties": props, "required": required]]
    }
    private static func str(_ d: String) -> [String: Any] { d.isEmpty ? ["type": "string"] : ["type": "string", "description": d] }
    private static func num(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
    private static func enumOf(_ v: [String]) -> [String: Any] { ["type": "string", "enum": v] }

    // MARK: - Execution

    func run(name: String, input: [String: Any]) -> Result {
        let today = now()
        switch name {
        case "get_plan":
            let blocks = DayLogic.sorted(mutator.effectivePlan(on: today))
            let completed = completions.completed(on: today)
            let skipped = completions.skipped(on: today)
            let override = mutator.days.override(dayKey: mutator.dayKey(today))
            let extras = Set(override.extras.map(\.id))
            let lines = blocks.map { b -> String in
                let time = b.start.map { NotificationScheduler.clock($0) + "–" + NotificationScheduler.clock(b.end ?? $0) } ?? "anytime"
                let status = b.status(now: today, completed: completed, skipped: skipped, calendar: calendar)
                var line = "\(b.id) | \(time) | \(b.label) | \(b.kind.rawValue) | \(status)"
                if b.isAnchor { line += " | anchor" }
                if override.moved[b.id] != nil { line += " | moved" }
                if extras.contains(b.id) { line += " | today only" }
                if let note = override.notes[b.id] { line += " | note: \(note)" }
                return line
            }
            return Result(output: lines.isEmpty ? "No blocks today." : lines.joined(separator: "\n"))

        case "add_block":
            guard let label = input["label"] as? String, let kindRaw = input["kind"] as? String, let kind = BlockKind(rawValue: kindRaw) else {
                return Result(output: "label and kind are required", isError: true)
            }
            var block = Block(id: UUID().uuidString, label: label, kind: kind)
            if kind != .free {
                guard let start = Self.hm(input["start"]), let end = Self.hm(input["end"]) else {
                    return Result(output: "start and end (HH:MM) are required for fixed/window blocks", isError: true)
                }
                block.start = start; block.end = end
                block.checkIn = Block.defaultCheckIn(kind: kind, start: start, end: end, isAnchor: false)
            }
            block.weekdays = Self.weekdays(input["weekdays"])
            if input["today_only"] as? Bool == true {
                block.weekdays = nil
                mutator.addExtra(block, dayKey: mutator.dayKey(today))
                return Result(output: "Added \(block.label) for today only (\(block.id))", summary: "Added \(block.label) for today")
            }
            plan.upsert(block)
            return Result(output: "Added block \(block.id): \(label)", summary: "Added block “\(label)”")

        case "update_block":
            guard let id = input["id"] as? String, var block = plan.block(id: id) else {
                return Result(output: "No block with that id", isError: true)
            }
            if let label = input["label"] as? String { block.label = label }
            if let kindRaw = input["kind"] as? String, let kind = BlockKind(rawValue: kindRaw) { block.kind = kind }
            if let start = Self.hm(input["start"]) { block.start = start }
            if let end = Self.hm(input["end"]) { block.end = end }
            if input["weekdays"] != nil { block.weekdays = Self.weekdays(input["weekdays"]) }
            if block.kind == .free { block.start = nil; block.end = nil } else if block.start == nil || block.end == nil {
                return Result(output: "This kind needs start and end", isError: true)
            }
            plan.upsert(block)
            let time = block.start.map { NotificationScheduler.clock($0) } ?? "anytime"
            return Result(output: "Updated \(block.id): \(block.label) at \(time)", summary: "Updated “\(block.label)” → \(time)")

        case "delete_block":
            guard let id = input["id"] as? String, let block = plan.block(id: id) else { return Result(output: "No block with that id", isError: true) }
            guard input["confirm"] as? Bool == true else { return Result(output: "Not deleted: ask the user to confirm, then call again with confirm=true", isError: true) }
            guard plan.delete(id: id) else { return Result(output: "The anchor block cannot be deleted", isError: true) }
            return Result(output: "Deleted \(block.label)", summary: "Deleted “\(block.label)”")

        case "mark_done":
            guard let id = input["id"] as? String, let block = plan.block(id: id) else { return Result(output: "No block with that id", isError: true) }
            let done = input["done"] as? Bool ?? true
            let isDone = completions.completed(on: today).contains(id)
            if done != isDone { mutator.setDone(id, done, dayKey: mutator.dayKey(today)) }
            return Result(output: "\(block.label) is now \(done ? "done" : "not done")", summary: "\(done ? "Done" : "Undone"): \(block.label)")

        case "skip_today":
            guard let id = input["id"] as? String, let block = plan.block(id: id) else { return Result(output: "No block with that id", isError: true) }
            if input["undo"] as? Bool == true {
                mutator.unskip(id, on: today)
                return Result(output: "\(block.label) is back on today's plan", summary: "Unskipped \(block.label)")
            }
            mutator.skipToday(id, dayKey: mutator.dayKey(today))
            return Result(output: "Skipped \(block.label) for today", summary: "Skipped \(block.label) today")

        case "set_block_note":
            guard let id = input["id"] as? String, let block = mutator.block(id: id, on: today) else { return Result(output: "No block with that id today", isError: true) }
            let note = input["note"] as? String ?? ""
            mutator.days.setNote(note, blockID: id, dayKey: mutator.dayKey(today))
            return Result(output: note.isEmpty ? "Note removed from \(block.label)" : "Note set on \(block.label)", summary: note.isEmpty ? "Note removed: \(block.label)" : "Note: \(block.label)")

        case "move_today":
            guard let id = input["id"] as? String, plan.block(id: id) != nil else { return Result(output: "No block with that id", isError: true) }
            let outcome: Replanner.Outcome
            if let start = Self.hm(input["start"]) { outcome = mutator.move(id, to: start, on: today) } else { outcome = mutator.replan(id, on: today) }
            switch outcome {
            case .rejected(let reason): return Result(output: reason, isError: true)
            case .noRoom: return Result(output: mutator.lastChange?.summary ?? "No room today", summary: mutator.lastChange?.summary)
            default: return Result(output: mutator.lastChange?.summary ?? "Moved", summary: mutator.lastChange?.summary)
            }

        case "undo_replan":
            let summary = mutator.days.undo?.summary
            guard mutator.undo() else { return Result(output: "Nothing to undo today", isError: true) }
            return Result(output: "Undone: \(summary ?? "")", summary: "Undid: \(summary ?? "last change")")

        case "get_pantry":
            guard !food.pantry.isEmpty else { return Result(output: "Pantry is empty.") }
            let lines = food.pantry.sorted { $0.name < $1.name }.map {
                "\($0.name): \(FoodStore.format($0.quantity)) \($0.unit) (min \(FoodStore.format($0.minQuantity)))" + ($0.isLow ? " LOW" : "")
            }
            return Result(output: lines.joined(separator: "\n"))

        case "add_pantry_item":
            guard let name = input["name"] as? String, let qty = Self.double(input["quantity"]), let unit = input["unit"] as? String else {
                return Result(output: "name, quantity and unit are required", isError: true)
            }
            let minQ = Self.double(input["min_quantity"]) ?? (qty / 2)
            if var existing = food.pantry.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                existing.quantity = qty; existing.unit = unit
                if input["min_quantity"] != nil { existing.minQuantity = minQ }
                food.upsert(existing)
                return Result(output: "Set \(existing.name) to \(FoodStore.format(qty)) \(unit)", summary: "Pantry: \(existing.name) = \(FoodStore.format(qty)) \(unit)")
            }
            food.upsert(PantryItem(name: name, quantity: qty, unit: unit, minQuantity: minQ))
            return Result(output: "Added \(name) \(FoodStore.format(qty)) \(unit) (min \(FoodStore.format(minQ)))", summary: "Added \(name) \(FoodStore.format(qty)) \(unit)")

        case "adjust_pantry":
            guard let name = input["name"] as? String, let delta = Self.double(input["delta"]),
                  let item = food.pantry.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return Result(output: "No pantry item with that name (use add_pantry_item)", isError: true)
            }
            food.adjust(id: item.id, by: delta)
            let after = food.pantry.first { $0.id == item.id }?.quantity ?? 0
            return Result(output: "\(item.name): now \(FoodStore.format(after)) \(item.unit)", summary: "\(item.name) → \(FoodStore.format(after)) \(item.unit)")

        case "log_meal":
            guard let name = input["name"] as? String, let kcal = Self.int(input["kcal"]), let protein = Self.int(input["protein_grams"]) else {
                return Result(output: "name, kcal and protein_grams are required", isError: true)
            }
            food.log(name: name, kcal: kcal, proteinGrams: protein, carbsGrams: Self.int(input["carbs_grams"]) ?? 0, fatGrams: Self.int(input["fat_grams"]) ?? 0, at: today, saveAsPreset: false)
            let m = food.macros(on: today)
            return Result(output: "Logged. Today: \(m.kcal)/\(food.targets.kcal) kcal, \(m.proteinGrams)/\(food.targets.proteinGrams) g protein",
                          summary: "Logged \(name) (\(kcal) kcal, \(protein) g)")

        case "get_recipes":
            guard !food.recipes.isEmpty else { return Result(output: "No recipes saved.") }
            let lines = food.recipes.map { r -> String in
                let missing = food.missing(for: r)
                let ings = r.ingredients.map { "\($0.name) \(FoodStore.format($0.amount)) \($0.unit)" }.joined(separator: ", ")
                return "\(r.name): \(r.kcal) kcal, \(r.proteinGrams) g P | \(ings) | " + (missing.isEmpty ? "can cook now" : "missing: \(missing.map(\.name).joined(separator: ", "))")
            }
            return Result(output: lines.joined(separator: "\n"))

        case "add_recipe":
            guard let name = input["name"] as? String, let kcal = Self.int(input["kcal"]), let protein = Self.int(input["protein_grams"]),
                  let raw = input["ingredients"] as? [[String: Any]] else { return Result(output: "name, kcal, protein_grams and ingredients are required", isError: true) }
            let ingredients = raw.compactMap { d -> Recipe.Ingredient? in
                guard let n = d["name"] as? String, let a = Self.double(d["amount"]) else { return nil }
                return Recipe.Ingredient(name: n, amount: a, unit: d["unit"] as? String ?? "pcs")
            }
            food.upsertRecipe(Recipe(name: name, ingredients: ingredients, kcal: kcal, proteinGrams: protein,
                                     carbsGrams: Self.int(input["carbs_grams"]) ?? 0, fatGrams: Self.int(input["fat_grams"]) ?? 0, note: input["note"] as? String ?? ""))
            return Result(output: "Saved recipe \(name)", summary: "Recipe: \(name)")

        case "cook_recipe":
            guard let name = input["name"] as? String, let recipe = food.recipes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return Result(output: "No recipe with that name", isError: true) }
            let missing = food.missing(for: recipe)
            guard food.cook(recipe, at: today, force: input["force"] as? Bool ?? false) else {
                return Result(output: "Missing: \(missing.map(\.name).joined(separator: ", ")). Pass force=true to cook anyway.", isError: true)
            }
            return Result(output: "Cooked \(recipe.name); pantry updated and meal logged", summary: "Cooked \(recipe.name)")

        case "delete_recipe":
            guard let name = input["name"] as? String, let recipe = food.recipes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return Result(output: "No recipe with that name", isError: true) }
            food.deleteRecipe(id: recipe.id)
            return Result(output: "Deleted recipe \(recipe.name)", summary: "Removed recipe \(recipe.name)")

        case "get_grocery_list":
            let list = food.groceryList
            return Result(output: list.isEmpty ? "Nothing is below minimum." : food.groceryText())

        case "get_closet":
            var lines = ["Weather \(wardrobe.weather.rawValue), style \(wardrobe.formality.rawValue)"]
            if wardrobe.closet.isEmpty { lines.append("Closet is empty.") }
            lines.append(contentsOf: wardrobe.closet.map {
                "\($0.name) | \($0.category.rawValue) | \($0.color) | warmth \($0.warmth) | \($0.formality.rawValue) | worn \($0.wearsSinceWash)/\($0.washAfter)" + ($0.needsWash ? " | needs wash" : "")
            })
            return Result(output: lines.joined(separator: "\n"))

        case "add_garment":
            guard let name = input["name"] as? String, let catRaw = input["category"] as? String, let category = GarmentCategory(rawValue: catRaw),
                  let color = input["color"] as? String else {
                return Result(output: "name, category and color are required", isError: true)
            }
            let warmth = min(3, max(1, Self.int(input["warmth"]) ?? 2))
            let formality = (input["formality"] as? String).flatMap(Formality.init(rawValue:)) ?? .casual
            let g = Garment(name: name, category: category, color: color, warmth: warmth, formality: formality,
                            washAfter: Self.int(input["wash_after"]).map { max(0, $0) } ?? category.defaultWashAfter)
            wardrobe.add(g, imageData: nil)
            return Result(output: "Added \(name) to the closet", summary: "Closet: added \(name)")

        case "wear_outfit":
            let names = (input["names"] as? [String]) ?? []
            let garments = names.compactMap { n in wardrobe.closet.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
            guard !garments.isEmpty else { return Result(output: "No matching garments", isError: true) }
            wardrobe.wear(garments, now: today)
            return Result(output: "Wearing: " + garments.map(\.name).joined(separator: ", "), summary: "Wearing " + garments.map(\.name).joined(separator: ", "))

        case "delete_pantry_item":
            guard let name = input["name"] as? String, let item = food.pantry.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return Result(output: "No pantry item with that name", isError: true)
            }
            food.deleteItem(id: item.id)
            return Result(output: "Removed \(item.name)", summary: "Pantry: removed \(item.name)")

        case "get_meals_today":
            let m = food.macros(on: today)
            var lines = ["Totals: \(m.kcal)/\(food.targets.kcal) kcal, \(m.proteinGrams)/\(food.targets.proteinGrams) g protein"]
            let meals = food.meals(on: today)
            lines.append(meals.isEmpty ? "No meals logged today." : meals.map { "\($0.id) | \($0.date.formatted(date: .omitted, time: .shortened)) | \($0.name) | \($0.kcal) kcal | \($0.proteinGrams) g" }.joined(separator: "\n"))
            if !food.presets.isEmpty {
                lines.append("Presets: " + food.presets.map { "\($0.name) (\($0.kcal) kcal, \($0.proteinGrams) g)" }.joined(separator: "; "))
            }
            return Result(output: lines.joined(separator: "\n"))

        case "delete_meal":
            guard let id = input["id"] as? String, let meal = food.meals.first(where: { $0.id == id }) else { return Result(output: "No meal with that id", isError: true) }
            food.deleteMeal(id: id)
            return Result(output: "Deleted \(meal.name)", summary: "Removed meal \(meal.name)")

        case "set_targets":
            var t = food.targets
            if let c = Self.int(input["carbs_grams"]) { t.carbsGrams = c }
            if let f = Self.int(input["fat_grams"]) { t.fatGrams = f }
            if let k = Self.int(input["kcal"]) { t.kcal = k }
            if let p = Self.int(input["protein_grams"]) { t.proteinGrams = p }
            food.targets = t
            return Result(output: "Targets: \(t.kcal) kcal, \(t.proteinGrams) g protein", summary: "Targets → \(t.kcal) kcal / \(t.proteinGrams) g")

        case "add_preset":
            guard let name = input["name"] as? String, let kcal = Self.int(input["kcal"]), let p = Self.int(input["protein_grams"]) else {
                return Result(output: "name, kcal and protein_grams are required", isError: true)
            }
            food.addPreset(name: name, kcal: kcal, proteinGrams: p)
            return Result(output: "Preset saved: \(name)", summary: "Preset: \(name)")

        case "delete_preset":
            guard let name = input["name"] as? String, let preset = food.presets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return Result(output: "No preset with that name", isError: true)
            }
            food.deletePreset(id: preset.id)
            return Result(output: "Deleted preset \(preset.name)", summary: "Removed preset \(preset.name)")

        case "update_garment":
            guard let name = input["name"] as? String, var g = wardrobe.closet.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return Result(output: "No garment with that name", isError: true)
            }
            if let n = input["new_name"] as? String, !n.isEmpty { g.name = n }
            if let c = (input["category"] as? String).flatMap(GarmentCategory.init(rawValue:)) { g.category = c }
            if let c = input["color"] as? String { g.color = c }
            if let w = Self.int(input["warmth"]) { g.warmth = min(3, max(1, w)) }
            if let f = (input["formality"] as? String).flatMap(Formality.init(rawValue:)) { g.formality = f }
            if let w = Self.int(input["wash_after"]) { g.washAfter = max(0, w) }
            wardrobe.update(g)
            return Result(output: "Updated \(g.name)", summary: "Closet: updated \(g.name)")

        case "delete_garment":
            guard let name = input["name"] as? String, let g = wardrobe.closet.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return Result(output: "No garment with that name", isError: true)
            }
            wardrobe.remove(id: g.id)
            return Result(output: "Removed \(g.name)", summary: "Closet: removed \(g.name)")

        case "mark_washed":
            if input["all"] as? Bool == true {
                let n = wardrobe.laundry.count
                wardrobe.washAll()
                return Result(output: "Laundry pile cleared (\(n) items)", summary: "Washed everything (\(n))")
            }
            let names = (input["names"] as? [String]) ?? []
            let items = names.compactMap { n in wardrobe.closet.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
            guard !items.isEmpty else { return Result(output: "No matching garments", isError: true) }
            for g in items { wardrobe.washed(id: g.id) }
            return Result(output: "Washed: " + items.map(\.name).joined(separator: ", "), summary: "Washed " + items.map(\.name).joined(separator: ", "))

        case "set_closet_context":
            if let w = (input["weather"] as? String).flatMap(Weather.init(rawValue:)) { wardrobe.weather = w }
            if let f = (input["style"] as? String).flatMap(Formality.init(rawValue:)) { wardrobe.formality = f }
            return Result(output: "Weather \(wardrobe.weather.rawValue), style \(wardrobe.formality.rawValue)", summary: "Outfit context: \(wardrobe.weather.rawValue), \(wardrobe.formality.rawValue)")

        case "get_study":
            var lines = ["Today \(track.studyMinutes(on: today)) min; this week \(track.studyMinutes(weekOf: today)) / \(track.weeklyStudyGoalMinutes) min"]
            if let since = track.runningSince { lines.append("Running since \(since.formatted(date: .omitted, time: .shortened)) (\(track.runningTopic))") }
            let recent = track.recentSessions(limit: 10)
            if !recent.isEmpty {
                lines.append(recent.map { "\($0.id) | \($0.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())) | \($0.topic) | \($0.minutes) min" }.joined(separator: "\n"))
            }
            return Result(output: lines.joined(separator: "\n"))

        case "add_study_session":
            guard let minutes = Self.int(input["minutes"]), minutes > 0 else { return Result(output: "minutes is required", isError: true) }
            let topic = input["topic"] as? String ?? ""
            let start: Date
            if let hm = Self.hm(input["start"]), let d = calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: today) {
                start = d
            } else {
                start = today.addingTimeInterval(-Double(minutes) * 60)
            }
            track.addSession(start: start, minutes: minutes, topic: topic)
            return Result(output: "Logged \(minutes) min of study", summary: "Study +\(minutes) min")

        case "delete_study_session":
            guard let id = input["id"] as? String, track.sessions.contains(where: { $0.id == id }) else { return Result(output: "No session with that id", isError: true) }
            track.deleteSession(id: id)
            return Result(output: "Deleted session", summary: "Removed a study session")

        case "set_study_goal":
            guard let m = Self.int(input["minutes"]), m > 0 else { return Result(output: "minutes is required", isError: true) }
            track.weeklyStudyGoalMinutes = m
            return Result(output: "Weekly goal: \(m) min", summary: "Study goal → \(m) min/week")

        case "get_income":
            let entries = track.incomeEntries(monthOf: today)
            var lines = ["Month total \(track.incomeTotal(monthOf: today)); year total \(track.incomeTotal(yearOf: today))"]
            lines.append(contentsOf: track.incomeBySource(monthOf: today).map { "\($0.source): \($0.amount)" })
            if !entries.isEmpty {
                lines.append(entries.map { "\($0.id) | \($0.date.formatted(date: .abbreviated, time: .omitted)) | \($0.source) | \($0.amount)" }.joined(separator: "\n"))
            }
            return Result(output: lines.joined(separator: "\n"))

        case "add_income":
            guard let source = input["source"] as? String, let amount = Self.double(input["amount"]) else { return Result(output: "source and amount are required", isError: true) }
            var date = today
            if let s = input["date"] as? String {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.timeZone = calendar.timeZone
                if let d = f.date(from: s) { date = d }
            }
            track.addIncome(source: source, amount: Decimal(amount), on: date)
            return Result(output: "Logged \(amount) from \(source)", summary: "Income +\(amount) (\(source))")

        case "delete_income":
            guard let id = input["id"] as? String, track.income.contains(where: { $0.id == id }) else { return Result(output: "No income entry with that id", isError: true) }
            track.deleteIncome(id: id)
            return Result(output: "Deleted income entry", summary: "Removed an income entry")

        case "forget":
            guard let text = input["text"] as? String, !text.isEmpty else { return Result(output: "text is required", isError: true) }
            let n = CoachProfile.forget(text)
            return Result(output: n == 0 ? "Nothing in memory matched" : "Forgot \(n) line(s)", summary: n == 0 ? nil : "Forgot: \(text)")

        case "remember":
            guard let note = input["note"] as? String, !note.isEmpty else { return Result(output: "note is required", isError: true) }
            CoachProfile.appendMemory(note)
            return Result(output: "Remembered.", summary: "Remembered: \(note)")

        default:
            return Result(output: "Unknown tool \(name)", isError: true)
        }
    }

    // MARK: - Parsing helpers

    static func hm(_ value: Any?) -> DateComponents? {
        guard let s = value as? String else { return nil }
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return .hm(parts[0], parts[1])
    }

    static func weekdays(_ value: Any?) -> Set<Int>? {
        guard let arr = value as? [Any] else { return nil }
        let days = Set(arr.compactMap { int($0) }.filter { (1...7).contains($0) })
        return days.isEmpty || days.count == 7 ? nil : days
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }
}
