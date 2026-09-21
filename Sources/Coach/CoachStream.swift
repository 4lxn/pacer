import Foundation

/// Messages-API streaming (SSE) for the agent loop. Rebuilds the same `content` array the
/// non-streaming response would carry — text, tool_use (with its input JSON), thinking — while
/// handing text deltas to the UI as they arrive.
enum CoachStream {
    struct Event { var name: String; var data: String }

    /// Splits raw SSE bytes into events. Pure; feed it line by line.
    struct Parser {
        private var name = ""
        private var data: [String] = []

        mutating func feed(line: String) -> Event? {
            if line.isEmpty {
                defer { name = ""; data = [] }
                return data.isEmpty ? nil : Event(name: name, data: data.joined(separator: "\n"))
            }
            if line.hasPrefix("event:") { name = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("data:") { data.append(String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))) }
            return nil
        }
    }

    /// Accumulates content blocks from events.
    struct Assembler {
        private(set) var blocks: [[String: Any]] = []
        private var partialJSON: [Int: String] = [:]
        private(set) var stopReason: String?
        private(set) var stopDetails: [String: Any]?
        private(set) var remaining: Int?
        private(set) var error: String?

        /// Returns text added by this event (for the live bubble).
        mutating func apply(_ event: Event) -> String? {
            guard let json = try? JSONSerialization.jsonObject(with: Data(event.data.utf8)) as? [String: Any] else { return nil }
            switch event.name.isEmpty ? (json["type"] as? String ?? "") : event.name {
            case "remaining":
                remaining = json["remaining"] as? Int
            case "content_block_start":
                guard let index = json["index"] as? Int, var block = json["content_block"] as? [String: Any] else { return nil }
                if block["type"] as? String == "tool_use" { block["input"] = [:]; partialJSON[index] = "" }
                while blocks.count <= index { blocks.append([:]) }
                blocks[index] = block
            case "content_block_delta":
                guard let index = json["index"] as? Int, index < blocks.count, let delta = json["delta"] as? [String: Any] else { return nil }
                switch delta["type"] as? String {
                case "text_delta":
                    let t = delta["text"] as? String ?? ""
                    blocks[index]["text"] = (blocks[index]["text"] as? String ?? "") + t
                    return t
                case "input_json_delta":
                    partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
                case "thinking_delta":
                    blocks[index]["thinking"] = (blocks[index]["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    blocks[index]["signature"] = (blocks[index]["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
                default: break
                }
            case "content_block_stop":
                guard let index = json["index"] as? Int, index < blocks.count else { return nil }
                if let raw = partialJSON[index] {
                    blocks[index]["input"] = (try? JSONSerialization.jsonObject(with: Data((raw.isEmpty ? "{}" : raw).utf8))) as? [String: Any] ?? [:]
                    partialJSON.removeValue(forKey: index)
                }
            case "message_delta":
                if let delta = json["delta"] as? [String: Any] {
                    stopReason = delta["stop_reason"] as? String ?? stopReason
                    stopDetails = delta["stop_details"] as? [String: Any] ?? stopDetails
                }
            case "error":
                error = (json["error"] as? [String: Any])?["message"] as? String ?? "stream error"
            default: break
            }
            return nil
        }

        var response: CoachClient.AgentResponse {
            CoachClient.AgentResponse(content: blocks.filter { !$0.isEmpty }, stopReason: stopReason, stopDetails: stopDetails, remaining: remaining)
        }
    }
}

extension CoachClient {
    /// Streams one agent turn. `onText` runs on the main actor with each text delta.
    func streamAgent(_ request: URLRequest, onText: @MainActor @escaping (String) -> Void) async throws -> AgentResponse {
        var request = request
        if var body = request.httpBody, var json = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            json["stream"] = true
            body = try JSONSerialization.data(withJSONObject: json)
            request.httpBody = body
        }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard (200..<300).contains(status), contentType.contains("text/event-stream") else {
            // Error bodies (and the legacy proxy) come back as JSON.
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            return try Self.parseAgent(data, status: status)
        }
        var parser = CoachStream.Parser()
        var assembler = CoachStream.Assembler()
        // A blank line ends an SSE event and `bytes.lines` drops blank lines, so split by hand.
        var buffer: [UInt8] = []
        for try await byte in bytes {
            guard byte == UInt8(ascii: "\n") else { buffer.append(byte); continue }
            if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: true)
            guard let event = parser.feed(line: line) else { continue }
            if let text = assembler.apply(event) { await onText(text) }
            if let error = assembler.error { throw CoachError.http(status, error) }
        }
        for line in [String(decoding: buffer, as: UTF8.self), ""] {
            if let event = parser.feed(line: line), let text = assembler.apply(event) { await onText(text) }
        }
        if let error = assembler.error { throw CoachError.http(status, error) }
        return assembler.response
    }
}
