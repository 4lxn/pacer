import Foundation
import XCTest
@testable import Autopiloto

/// Serves canned Messages-API responses in order.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [Data] = []
    nonisolated(unsafe) static var requests: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let body = request.httpBody ?? request.httpBodyStream.map({ stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536); defer { buf.deallocate() }
            while stream.hasBytesAvailable { let n = stream.read(buf, maxLength: 65_536); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        }) {
            Self.requests.append(body)
        }
        let data = Self.responses.isEmpty ? Data("{}".utf8) : Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class CoachAgentTests: XCTestCase {
    private var dir: URL!
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        StubProtocol.responses = []
        StubProtocol.requests = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeTools() throws -> CoachTools {
        let legacy = dir.appendingPathComponent("completions.json")
        try Data("{}".utf8).write(to: legacy)
        return CoachTools(
            plan: PlanStore(fileURL: dir.appendingPathComponent("plan.json"), legacyMarker: legacy),
            completions: CompletionStore(fileURL: legacy, calendar: calendar),
            food: FoodStore(fileURL: dir.appendingPathComponent("food.json"), legacyMarker: legacy, calendar: calendar),
            wardrobe: WardrobeStore(fileURL: dir.appendingPathComponent("wardrobe.json")),
            health: HealthStore(),
            track: TrackStore(fileURL: dir.appendingPathComponent("track.json"), calendar: calendar),
            calendar: calendar,
            now: { self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))! }
        )
    }

    func testTrimmingKeepsToolPairsTogether() {
        var messages: [[String: Any]] = []
        for i in 0..<10 {
            messages.append(["role": "user", "content": "q\(i)"])
            messages.append(["role": "assistant", "content": [["type": "tool_use", "id": "t\(i)", "name": "get_plan", "input": [:]]]])
            messages.append(["role": "user", "content": [["type": "tool_result", "tool_use_id": "t\(i)", "content": "x"]]])
            messages.append(["role": "assistant", "content": [["type": "text", "text": "a\(i)"]]])
        }
        let trimmed = CoachChatStore.trimmed(messages, max: 10)
        XCTAssertLessThanOrEqual(trimmed.count, 10)
        XCTAssertEqual(trimmed.first?["content"] as? String, "q8")
        XCTAssertEqual(trimmed.count, 8)
    }

    func testToolsMutateStores() throws {
        let tools = try makeTools()
        XCTAssertTrue(tools.run(name: "get_plan", input: [:]).output.contains("b11 | 15:45–17:15 | Study"))

        let moved = tools.run(name: "update_block", input: ["id": "b11", "start": "17:00", "end": "18:30"])
        XCTAssertFalse(moved.isError)
        XCTAssertEqual(tools.plan.block(id: "b11")?.start, .hm(17, 0))
        XCTAssertEqual(moved.summary, "Updated “Study” → 17:00")

        XCTAssertTrue(tools.run(name: "delete_block", input: ["id": "b11", "confirm": false]).isError)
        XCTAssertTrue(tools.run(name: "delete_block", input: ["id": "b01", "confirm": true]).isError)   // anchor
        XCTAssertFalse(tools.run(name: "delete_block", input: ["id": "b19", "confirm": true]).isError)
        XCTAssertNil(tools.plan.block(id: "b19"))

        let added = tools.run(name: "add_block", input: ["label": "Read", "kind": "window", "start": "21:00", "end": "21:30", "weekdays": [2, 4]])
        XCTAssertFalse(added.isError)
        XCTAssertEqual(tools.plan.blocks.last?.weekdays, [2, 4])
        XCTAssertTrue(tools.run(name: "add_block", input: ["label": "Bad", "kind": "fixed"]).isError)

        let rice = tools.run(name: "add_pantry_item", input: ["name": "Rice", "quantity": 2500, "unit": "g"])
        XCTAssertEqual(rice.summary, "Pantry: Rice = 2500 g")
        XCTAssertEqual(tools.food.pantry.first { $0.name == "Rice" }?.quantity, 2500)
        _ = tools.run(name: "adjust_pantry", input: ["name": "rice", "delta": -2000])
        XCTAssertEqual(tools.food.pantry.first { $0.name == "Rice" }?.quantity, 500)
        XCTAssertTrue(tools.run(name: "get_grocery_list", input: [:]).output.contains("Rice"))
        XCTAssertFalse(tools.run(name: "add_pantry_item", input: ["name": "Eggs", "quantity": 12, "unit": "pcs"]).isError)
        XCTAssertEqual(tools.food.pantry.first { $0.name == "Eggs" }?.minQuantity, 6)

        _ = tools.run(name: "log_meal", input: ["name": "Shake", "kcal": 450, "protein_grams": 40])
        XCTAssertEqual(tools.food.macros(on: tools.now()).proteinGrams, 40)

        _ = tools.run(name: "mark_done", input: ["id": "b01"])
        XCTAssertTrue(tools.completions.completed(on: tools.now()).contains("b01"))

        XCTAssertEqual(tools.run(name: "add_garment", input: ["name": "navy hoodie", "category": "outer", "color": "navy", "warmth": 3]).summary, "Closet: added navy hoodie")
        XCTAssertEqual(tools.run(name: "wear_outfit", input: ["names": ["Navy Hoodie"]]).summary, "Wearing navy hoodie")
        XCTAssertTrue(tools.run(name: "nope", input: [:]).isError)
    }

    func testCrudToolsCoverEveryStore() throws {
        let tools = try makeTools()
        // Pantry delete
        XCTAssertEqual(tools.run(name: "delete_pantry_item", input: ["name": "prunes"]).summary, "Pantry: removed Prunes")
        XCTAssertNil(tools.food.pantry.first { $0.name == "Prunes" })
        // Meals + presets + targets
        _ = tools.run(name: "log_meal", input: ["name": "Yogurt", "kcal": 200, "protein_grams": 15])
        let mealID = tools.food.meals(on: tools.now()).first!.id
        XCTAssertTrue(tools.run(name: "get_meals_today", input: [:]).output.contains(mealID))
        XCTAssertEqual(tools.run(name: "delete_meal", input: ["id": mealID]).summary, "Removed meal Yogurt")
        XCTAssertEqual(tools.run(name: "set_targets", input: ["kcal": 2100]).summary, "Targets → 2100 kcal / 160 g")
        _ = tools.run(name: "add_preset", input: ["name": "Oats", "kcal": 300, "protein_grams": 10])
        XCTAssertTrue(tools.food.presets.contains { $0.name == "Oats" })
        _ = tools.run(name: "delete_preset", input: ["name": "oats"])
        XCTAssertFalse(tools.food.presets.contains { $0.name == "Oats" })
        // Closet update / wash / context / delete
        _ = tools.run(name: "add_garment", input: ["name": "grey tee", "category": "top", "color": "grey", "wash_after": 2])
        XCTAssertEqual(tools.run(name: "update_garment", input: ["name": "grey tee", "new_name": "grey v-neck", "warmth": 9]).summary, "Closet: updated grey v-neck")
        XCTAssertEqual(tools.wardrobe.closet.first?.warmth, 3)
        _ = tools.run(name: "wear_outfit", input: ["names": ["grey v-neck"]])
        _ = tools.run(name: "wear_outfit", input: ["names": ["grey v-neck"]])   // same day: still 1 wear
        XCTAssertEqual(tools.wardrobe.closet.first?.wearsSinceWash, 1)
        XCTAssertEqual(tools.run(name: "mark_washed", input: ["names": ["grey v-neck"]]).summary, "Washed grey v-neck")
        XCTAssertEqual(tools.run(name: "set_closet_context", input: ["weather": "cold", "style": "smart"]).summary, "Outfit context: cold, smart")
        XCTAssertTrue(tools.run(name: "get_closet", input: [:]).output.hasPrefix("Weather cold, style smart"))
        _ = tools.run(name: "delete_garment", input: ["name": "grey v-neck"])
        XCTAssertTrue(tools.wardrobe.closet.isEmpty)
        // Study + income
        XCTAssertEqual(tools.run(name: "add_study_session", input: ["minutes": 45, "topic": "Swift", "start": "10:00"]).summary, "Study +45 min")
        XCTAssertEqual(tools.track.studyMinutes(on: tools.now()), 45)
        let sessionID = tools.track.sessions[0].id
        XCTAssertTrue(tools.run(name: "get_study", input: [:]).output.contains(sessionID))
        _ = tools.run(name: "delete_study_session", input: ["id": sessionID])
        XCTAssertTrue(tools.track.sessions.isEmpty)
        _ = tools.run(name: "set_study_goal", input: ["minutes": 600])
        XCTAssertEqual(tools.track.weeklyStudyGoalMinutes, 600)
        _ = tools.run(name: "add_income", input: ["source": "Salary", "amount": 1000, "date": "2026-09-01"])
        XCTAssertEqual(tools.track.incomeTotal(monthOf: tools.now()), 1000)
        let incomeID = tools.track.income[0].id
        XCTAssertTrue(tools.run(name: "get_income", input: [:]).output.contains(incomeID))
        _ = tools.run(name: "delete_income", input: ["id": incomeID])
        XCTAssertTrue(tools.track.income.isEmpty)
        // Definitions and executor agree on names
        let names = CoachTools.definitions.compactMap { $0["name"] as? String }
        XCTAssertEqual(names.count, Set(names).count)
        for name in names {
            XCTAssertNotEqual(tools.run(name: name, input: [:]).output, "Unknown tool \(name)", name)
        }
    }

    func testForgetRemovesMemoryLines() {
        let defaults = UserDefaults(suiteName: "mem-\(UUID().uuidString)")!
        CoachProfile.save("## Goals\nlose fat", defaults: defaults)
        CoachProfile.appendMemory("hates broccoli", defaults: defaults)
        CoachProfile.appendMemory("likes prunes", defaults: defaults)
        XCTAssertEqual(CoachProfile.forget("Broccoli", defaults: defaults), 1)
        XCTAssertEqual(CoachProfile.load(defaults: defaults), "## Goals\nlose fat\n\n## Memory\n- likes prunes")
        XCTAssertEqual(CoachProfile.forget("nothing", defaults: defaults), 0)
    }

    func testAgentLoopRunsToolsThenAnswers() async throws {
        let tools = try makeTools()
        let chat = CoachChatStore(fileURL: dir.appendingPathComponent("chat.json"))
        let agent = CoachAgent(chat: chat, tools: tools)

        StubProtocol.responses = [
            Data(#"{"content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"tool_use","id":"t1","name":"add_pantry_item","input":{"name":"Rice","quantity":1000,"unit":"g"}}],"stop_reason":"tool_use"}"#.utf8),
            Data(#"{"content":[{"type":"text","text":"Listo, 1 kg de arroz en la despensa."}],"stop_reason":"end_turn"}"#.utf8),
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        var client = CoachClient(apiKey: "sk-test")
        client.session = URLSession(configuration: config)

        await agent.send("agrega 1 kg de arroz", client: client, systemBlocks: [["type": "text", "text": "sys"]])

        XCTAssertNil(agent.lastError)
        XCTAssertEqual(tools.food.pantry.first { $0.name == "Rice" }?.quantity, 1000)
        XCTAssertEqual(chat.entries.map(\.role), [.user, .tool, .assistant])
        XCTAssertEqual(chat.entries[1].text, "Pantry: Rice = 1000 g")   // seeded pantry already has Rice
        XCTAssertEqual(chat.messages.count, 4)

        // Second request replays the assistant blocks (thinking included) and the tool_result.
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: StubProtocol.requests[1]) as? [String: Any])
        let messages = try XCTUnwrap(second["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        let assistant = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistant.first?["type"] as? String, "thinking")
        XCTAssertEqual(assistant.first?["signature"] as? String, "sig")
        let result = try XCTUnwrap((messages[2]["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(result["tool_use_id"] as? String, "t1")
        XCTAssertNotNil(second["tools"])

        // Persisted: a new store sees the same conversation.
        XCTAssertEqual(CoachChatStore(fileURL: dir.appendingPathComponent("chat.json")).entries.count, 3)
    }

    func testMemoryAppendsToProfile() {
        let defaults = UserDefaults(suiteName: "mem-\(UUID().uuidString)")!
        CoachProfile.save("## Goals\nlose fat", defaults: defaults)
        CoachProfile.appendMemory("hates broccoli", defaults: defaults)
        CoachProfile.appendMemory("gym closed Sundays", defaults: defaults)
        XCTAssertEqual(CoachProfile.load(defaults: defaults), "## Goals\nlose fat\n\n## Memory\n- hates broccoli\n- gym closed Sundays")
    }
}
