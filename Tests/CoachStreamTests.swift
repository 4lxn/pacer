import XCTest
@testable import Autopiloto

/// Serves `body` as a text/event-stream response to any request.
final class SSEStub: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CoachStreamTests: XCTestCase {
    static let sse = """
    event: remaining
    data: {"remaining": 37}

    event: message_start
    data: {"type":"message_start","message":{"id":"m1"}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: content_block_start
    data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Adding "}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"rice."}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":1}

    event: content_block_start
    data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"t1","name":"add_pantry_item","input":{}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"name\\": \\"Ri"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"ce\\", \\"quantity\\": 1000, \\"unit\\": \\"g\\"}"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":2}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":20}}

    event: message_stop
    data: {"type":"message_stop"}

    """

    private func check(_ r: CoachClient.AgentResponse, streamed: String) {
        XCTAssertEqual(streamed, "Adding rice.")
        XCTAssertEqual(r.remaining, 37)
        XCTAssertEqual(r.stopReason, "tool_use")
        XCTAssertEqual(r.content.count, 3)
        XCTAssertEqual(r.content[0]["thinking"] as? String, "hmm"); XCTAssertEqual(r.content[0]["signature"] as? String, "sig")
        XCTAssertEqual(r.content[1]["text"] as? String, "Adding rice.")
        XCTAssertEqual(r.content[2]["name"] as? String, "add_pantry_item")
        XCTAssertEqual((r.content[2]["input"] as? [String: Any])?["quantity"] as? Int, 1000)
    }

    func testAssemblesTextAndToolUseFromEvents() {
        var parser = CoachStream.Parser()
        var assembler = CoachStream.Assembler()
        var streamed = ""
        for line in Self.sse.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let e = parser.feed(line: line), let t = assembler.apply(e) { streamed += t }
        }
        check(assembler.response, streamed: streamed)
        XCTAssertNil(assembler.error)

        var errored = CoachStream.Assembler()
        _ = errored.apply(.init(name: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        XCTAssertEqual(errored.error, "Overloaded")
    }

    /// Regression: `bytes.lines` drops the blank lines that end SSE events, so every event
    /// merged into one unparseable blob and the coach answered nothing (build 17–19).
    @MainActor
    func testStreamAgentKeepsEventBoundaries() async throws {
        SSEStub.body = Data(Self.sse.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEStub.self]
        var client = CoachClient(proxy: URL(string: "https://coach.test")!, sessionToken: "t")
        client.session = URLSession(configuration: config)
        let request = try CoachClient.makeAgentRequest(auth: client.auth, model: "m", system: [], messages: [["role": "user", "content": "hi"]], tools: [])
        var streamed = ""
        let response = try await client.streamAgent(request) { streamed += $0 }
        check(response, streamed: streamed)
    }

    @MainActor
    func testEmptyAssistantTurnsAreDropped() {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "hi"],
            ["role": "assistant", "content": [] as [[String: Any]]],
            ["role": "user", "content": "still there?"],
            ["role": "assistant", "content": [["type": "text", "text": "yes"]]],
        ]
        let clean = CoachChatStore.sanitized(messages)
        XCTAssertEqual(clean.count, 3)
        XCTAssertEqual(clean.map { $0["role"] as? String }, ["user", "user", "assistant"])
        XCTAssertEqual(CoachChatStore.trimmed(messages, max: 10).count, 3)
    }
}
