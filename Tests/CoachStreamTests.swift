import XCTest
@testable import Autopiloto

final class CoachStreamTests: XCTestCase {
    func testAssemblesTextAndToolUseFromEvents() {
        let sse = """
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
        var parser = CoachStream.Parser()
        var assembler = CoachStream.Assembler()
        var streamed = ""
        for line in sse.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let e = parser.feed(line: line), let t = assembler.apply(e) { streamed += t }
        }
        let r = assembler.response
        XCTAssertEqual(streamed, "Adding rice.")
        XCTAssertEqual(r.remaining, 37)
        XCTAssertEqual(r.stopReason, "tool_use")
        XCTAssertEqual(r.content.count, 3)
        XCTAssertEqual(r.content[0]["thinking"] as? String, "hmm"); XCTAssertEqual(r.content[0]["signature"] as? String, "sig")
        XCTAssertEqual(r.content[1]["text"] as? String, "Adding rice.")
        XCTAssertEqual(r.content[2]["name"] as? String, "add_pantry_item")
        XCTAssertEqual((r.content[2]["input"] as? [String: Any])?["quantity"] as? Int, 1000)
        XCTAssertNil(assembler.error)

        var errored = CoachStream.Assembler()
        _ = errored.apply(.init(name: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        XCTAssertEqual(errored.error, "Overloaded")
    }
}
