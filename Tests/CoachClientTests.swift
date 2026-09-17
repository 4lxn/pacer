import XCTest
@testable import Autopiloto

final class CoachClientTests: XCTestCase {
    func testRequestShape() throws {
        let request = try CoachClient.makeRequest(
            apiKey: "sk-test", model: "claude-opus-5", staticSystem: "STATIC", snapshot: "SNAP", question: "hola"
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-opus-5")
        XCTAssertEqual(json["max_tokens"] as? Int, 4096)
        XCTAssertEqual(json["fallbacks"] as? String, "default")
        let system = try XCTUnwrap(json["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 2)
        XCTAssertEqual(system[0]["text"] as? String, "STATIC")
        XCTAssertEqual((system[0]["cache_control"] as? [String: String])?["type"], "ephemeral")
        XCTAssertEqual(system[1]["text"] as? String, "SNAP")
        XCTAssertNil(system[1]["cache_control"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "hola")
    }

    func testProxyRequestShapeAndParse() throws {
        let request = try CoachClient.makeProxyRequest(
            base: URL(string: "https://coach.example.com")!, sessionToken: "sess", staticSystem: "STATIC", snapshot: "SNAP", question: "hola"
        )
        XCTAssertEqual(request.url?.absoluteString, "https://coach.example.com/v1/coach")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sess")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["question"] as? String, "hola")
        XCTAssertEqual((json["system"] as? [[String: Any]])?.count, 2)

        XCTAssertEqual(try CoachClient.parseProxy(Data(#"{"text":"Come arroz.","remaining":39}"#.utf8), status: 200), "Come arroz.")
        XCTAssertThrowsError(try CoachClient.parseProxy(Data(#"{"error":"daily limit reached"}"#.utf8), status: 429)) { error in
            XCTAssertEqual(error.localizedDescription, "API error 429: daily limit reached")
        }
    }

    @MainActor
    func testCoachProfileStartsFromTheTemplate() throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        XCTAssertEqual(CoachProfile.load(defaults: defaults), CoachProfile.template)
        CoachProfile.save("mine", defaults: defaults)
        XCTAssertEqual(CoachProfile.load(defaults: defaults), "mine")
    }

    func testParseJoinsTextBlocks() throws {
        let data = Data("""
        {"id":"msg_1","type":"message","role":"assistant","content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hola."},{"type":"text","text":"Come arroz."}],"stop_reason":"end_turn"}
        """.utf8)
        XCTAssertEqual(try CoachClient.parse(data, status: 200), "Hola.\nCome arroz.")
    }

    func testParseSurfacesAPIError() {
        let data = Data("""
        {"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}
        """.utf8)
        XCTAssertThrowsError(try CoachClient.parse(data, status: 401)) { error in
            XCTAssertEqual(error.localizedDescription, "API error 401: invalid x-api-key")
        }
    }

    func testSnapshotListsBlocksWithStatus() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 11, minute: 0))!
        let snapshot = CoachContext.snapshot(blocks: Plan.blocks.filter { $0.occurs(on: now, calendar: calendar) }, now: now, completed: ["b01"], calendar: calendar)
        XCTAssertTrue(snapshot.contains("Wednesday 2026-09-16 11:00"))
        XCTAssertTrue(snapshot.contains("Gym today: Upper."))
        XCTAssertTrue(snapshot.contains("07:30 Wake up — done"))
        XCTAssertTrue(snapshot.contains("10:00 Work block — current"))
        XCTAssertTrue(snapshot.contains("anytime One thing for the future — not done yet"))
    }
}
