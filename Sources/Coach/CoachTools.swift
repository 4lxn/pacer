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
    var calendar: Calendar = .current
    var now: () -> Date = { .now }

    struct Result {
        var output: String
        var summary: String?
        var isError = false
    }

    // MARK: - Definitions

    static let definitions: [[String: Any]] = [
        tool("get_plan", "Today's blocks with times and status (done, current, upcoming, missed).", [:]),
        tool("add_block", "Add a block to the plan. Times are HH:MM 24h. kind: fixed (notifies at start), window (anytime in range), free (no clock).", [
            "label": str("Short label"), "kind": enumOf(["fixed", "window", "free"]),
            "start": str("HH:MM, omit for free"), "end": str("HH:MM, omit for free"),
            "weekdays": ["type": "array", "items": ["type": "integer"], "description": "1=Sunday…7=Saturday; omit for every day"],
        ], required: ["label", "kind"]),
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
        tool("get_pantry", "Pantry items with quantity, unit and minimum; items below minimum are on the grocery list.", [:]),
        tool("add_pantry_item", "Add a pantry item, or set the quantity of an existing one with the same name.", [
            "name": str("Item name"), "quantity": num("Amount on hand"), "unit": str("g, pcs, L, scoops…"),
            "min_quantity": num("Below this it goes on the grocery list; default = half of quantity"),
        ], required: ["name", "quantity", "unit"]),
        tool("adjust_pantry", "Add (positive) or remove (negative) an amount from a pantry item, e.g. after cooking or shopping.", [
            "name": str("Item name"), "delta": num("Amount to add; negative to remove"),
        ], required: ["name", "delta"]),
        tool("log_meal", "Log a meal eaten today with calories and protein.", [
            "name": str("Meal name"), "kcal": ["type": "integer"], "protein_grams": ["type": "integer"],
        ], required: ["name", "kcal", "protein_grams"]),
        tool("get_grocery_list", "Items below their minimum, with how much to buy.", [:]),
        tool("get_closet", "All garments with category, color, warmth, style and laundry status.", [:]),
        tool("add_garment", "Add a garment to the closet from a description (no photo).", [
            "name": str("e.g. navy hoodie"), "category": enumOf(["top", "bottom", "shoes", "outer", "accessory"]),
            "color": str(""), "warmth": ["type": "integer", "description": "1 light, 2 mid, 3 warm"],
            "formality": enumOf(["sport", "casual", "smart"]),
        ], required: ["name", "category", "color"]),
        tool("wear_outfit", "Log that the user is wearing these garments today (bumps wear counts).", [
            "names": ["type": "array", "items": ["type": "string"], "description": "Garment names"],
        ], required: ["names"]),
        tool("remember", "Save a durable fact or preference about the user to the Coach profile's Memory section.", [
            "note": str("One line, e.g. 'hates broccoli' or 'gym closed on Sundays'"),
        ], required: ["note"]),
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
            let blocks = DayLogic.sorted(plan.today(on: today, calendar: calendar))
            let completed = completions.completed(on: today)
            let lines = blocks.map { b -> String in
                let time = b.start.map { NotificationScheduler.clock($0) + "–" + NotificationScheduler.clock(b.end ?? $0) } ?? "anytime"
                let status = b.status(now: today, completed: completed, calendar: calendar)
                return "\(b.id) | \(time) | \(b.label) | \(b.kind.rawValue) | \(status)" + (b.isAnchor ? " | anchor" : "")
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
            }
            block.weekdays = Self.weekdays(input["weekdays"])
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
            if done != isDone { completions.toggle(id, on: today) }
            return Result(output: "\(block.label) is now \(done ? "done" : "not done")", summary: "\(done ? "Done" : "Undone"): \(block.label)")

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
            food.log(name: name, kcal: kcal, proteinGrams: protein, at: today, saveAsPreset: false)
            let m = food.macros(on: today)
            return Result(output: "Logged. Today: \(m.kcal)/\(food.targets.kcal) kcal, \(m.proteinGrams)/\(food.targets.proteinGrams) g protein",
                          summary: "Logged \(name) (\(kcal) kcal, \(protein) g)")

        case "get_grocery_list":
            let list = food.groceryList
            return Result(output: list.isEmpty ? "Nothing is below minimum." : food.groceryText())

        case "get_closet":
            guard !wardrobe.closet.isEmpty else { return Result(output: "Closet is empty.") }
            let lines = wardrobe.closet.map {
                "\($0.name) | \($0.category.rawValue) | \($0.color) | warmth \($0.warmth) | \($0.formality.rawValue)" + ($0.needsWash ? " | needs wash" : "")
            }
            return Result(output: lines.joined(separator: "\n"))

        case "add_garment":
            guard let name = input["name"] as? String, let catRaw = input["category"] as? String, let category = GarmentCategory(rawValue: catRaw),
                  let color = input["color"] as? String else {
                return Result(output: "name, category and color are required", isError: true)
            }
            let warmth = min(3, max(1, Self.int(input["warmth"]) ?? 2))
            let formality = (input["formality"] as? String).flatMap(Formality.init(rawValue:)) ?? .casual
            let g = Garment(name: name, category: category, color: color, warmth: warmth, formality: formality, washAfter: category.defaultWashAfter)
            wardrobe.add(g, imageData: nil)
            return Result(output: "Added \(name) to the closet", summary: "Closet: added \(name)")

        case "wear_outfit":
            let names = (input["names"] as? [String]) ?? []
            let garments = names.compactMap { n in wardrobe.closet.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
            guard !garments.isEmpty else { return Result(output: "No matching garments", isError: true) }
            wardrobe.wear(garments, now: today)
            return Result(output: "Wearing: " + garments.map(\.name).joined(separator: ", "), summary: "Wearing " + garments.map(\.name).joined(separator: ", "))

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
