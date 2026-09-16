import Foundation

/// The only network code in the app. Two modes: direct to the Claude Messages API with the user's
/// own key, or through the Coach proxy (`server/`) with a session token from Sign in with Apple.
struct CoachClient: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let defaultModel = "claude-opus-5"
    /// Set after deploying `server/` (e.g. https://autopiloto-coach.up.railway.app). nil = own-key only.
    static let proxyURL: URL? = nil

    enum Auth: Sendable {
        case apiKey(String)
        case proxy(URL, sessionToken: String)
    }

    var auth: Auth
    var model = CoachClient.defaultModel
    var session: URLSession = .shared

    init(apiKey: String) { auth = .apiKey(apiKey) }
    init(proxy: URL, sessionToken: String) { auth = .proxy(proxy, sessionToken: sessionToken) }

    struct Request: Encodable {
        struct TextBlock: Encodable {
            struct CacheControl: Encodable { let type = "ephemeral" }
            let type = "text"
            let text: String
            var cache_control: CacheControl?
        }
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let max_tokens: Int
        let system: [TextBlock]
        let messages: [Message]
        let fallbacks: String
    }

    struct Response: Decodable {
        struct Content: Decodable {
            let type: String
            let text: String?
        }
        struct APIError: Decodable {
            let type: String
            let message: String
        }
        let content: [Content]?
        let stop_reason: String?
        let error: APIError?
    }

    enum CoachError: LocalizedError {
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case let .http(status, message): "API error \(status): \(message)"
            case .empty: "The coach returned no text."
            }
        }
    }

    /// Builds the request. `staticSystem` is cached server-side (prompt caching); `snapshot` is
    /// the per-request part and goes after the cache breakpoint.
    static func makeRequest(apiKey: String, model: String, staticSystem: String, snapshot: String, question: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body = Request(
            model: model,
            max_tokens: 4096,
            system: [
                .init(text: staticSystem, cache_control: .init()),
                .init(text: snapshot, cache_control: nil),
            ],
            messages: [.init(role: "user", content: question)],
            fallbacks: "default"
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    struct ProxyRequest: Encodable {
        let system: [Request.TextBlock]
        let question: String
        var image: ImagePayload?
    }

    struct ImagePayload: Encodable {
        let media_type: String
        let data: String
    }

    /// Direct-mode request with an image block before the text (Claude vision).
    struct VisionRequest: Encodable {
        struct Content: Encodable {
            struct Source: Encodable { let type = "base64"; let media_type: String; let data: String }
            let type: String
            var source: Source?
            var text: String?
        }
        struct Message: Encodable { let role: String; let content: [Content] }
        let model: String
        let max_tokens: Int
        let messages: [Message]
        let fallbacks: String
    }

    static func makeVisionRequest(apiKey: String, model: String, jpeg: Data, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body = VisionRequest(
            model: model, max_tokens: 512,
            messages: [.init(role: "user", content: [
                .init(type: "image", source: .init(media_type: "image/jpeg", data: jpeg.base64EncodedString()), text: nil),
                .init(type: "text", source: nil, text: prompt),
            ])],
            fallbacks: "default"
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Describe a photo. Returns the model's text (JSON per the prompt).
    func describe(jpeg: Data, prompt: String) async throws -> String {
        switch auth {
        case let .apiKey(key):
            let request = try Self.makeVisionRequest(apiKey: key, model: model, jpeg: jpeg, prompt: prompt)
            let (data, response) = try await session.data(for: request)
            return try Self.parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        case let .proxy(base, token):
            var request = try Self.makeProxyRequest(base: base, sessionToken: token, staticSystem: "You describe clothing photos.", snapshot: "", question: prompt)
            request.httpBody = try JSONEncoder().encode(ProxyRequest(
                system: [.init(text: "You describe clothing photos.", cache_control: nil)],
                question: prompt,
                image: ImagePayload(media_type: "image/jpeg", data: jpeg.base64EncodedString())
            ))
            let (data, response) = try await session.data(for: request)
            return try Self.parseProxy(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    struct ProxyResponse: Decodable {
        let text: String?
        let remaining: Int?
        let error: String?
    }

    static func makeProxyRequest(base: URL, sessionToken: String, staticSystem: String, snapshot: String, question: String) throws -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("v1/coach"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let body = ProxyRequest(
            system: [.init(text: staticSystem, cache_control: .init()), .init(text: snapshot, cache_control: nil)],
            question: question
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func parseProxy(_ data: Data, status: Int) throws -> String {
        let decoded = try JSONDecoder().decode(ProxyResponse.self, from: data)
        if let error = decoded.error { throw CoachError.http(status, error) }
        guard (200..<300).contains(status) else { throw CoachError.http(status, String(decoding: data, as: UTF8.self)) }
        guard let text = decoded.text, !text.isEmpty else { throw CoachError.empty }
        return text
    }

    /// Exchanges an Apple identity token for a proxy session token.
    static func openSession(base: URL, identityToken: String, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("v1/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["identityToken": identityToken])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        struct SessionResponse: Decodable { let token: String?; let error: String? }
        let decoded = try JSONDecoder().decode(SessionResponse.self, from: data)
        if let error = decoded.error { throw CoachError.http(status, error) }
        guard let token = decoded.token else { throw CoachError.empty }
        return token
    }

    // MARK: - Agent (tool use, multi-turn)

    /// Builds a Messages-API request with tools from raw JSON dictionaries so assistant blocks
    /// (thinking, tool_use) replay exactly as received. Works for both auth modes.
    static func makeAgentRequest(auth: Auth, model: String, system: [[String: Any]], messages: [[String: Any]], tools: [[String: Any]]) throws -> URLRequest {
        var request: URLRequest
        var body: [String: Any]
        switch auth {
        case let .apiKey(key):
            request = URLRequest(url: endpoint)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body = ["model": model, "max_tokens": 4096, "system": system, "messages": messages, "tools": tools, "fallbacks": "default"]
        case let .proxy(base, token):
            request = URLRequest(url: base.appendingPathComponent("v1/coach"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            body = ["system": system, "messages": messages, "tools": tools]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    struct AgentResponse {
        var content: [[String: Any]]
        var stopReason: String?
        var stopDetails: [String: Any]?
        var remaining: Int?
    }

    static func parseAgent(_ data: Data, status: Int) throws -> AgentResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoachError.http(status, String(decoding: data, as: UTF8.self))
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw CoachError.http(status, message)
        }
        if let error = json["error"] as? String { throw CoachError.http(status, error) }
        guard (200..<300).contains(status) else { throw CoachError.http(status, String(decoding: data, as: UTF8.self)) }
        return AgentResponse(
            content: json["content"] as? [[String: Any]] ?? [],
            stopReason: json["stop_reason"] as? String,
            stopDetails: json["stop_details"] as? [String: Any],
            remaining: json["remaining"] as? Int
        )
    }

    /// Sends a prepared request; the caller parses on its own actor.
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func parse(_ data: Data, status: Int) throws -> String {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let error = decoded.error {
            throw CoachError.http(status, error.message)
        }
        guard (200..<300).contains(status) else {
            throw CoachError.http(status, String(decoding: data, as: UTF8.self))
        }
        let text = (decoded.content ?? []).compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n")
        guard !text.isEmpty else { throw CoachError.empty }
        return text
    }

    func ask(_ question: String, staticSystem: String, snapshot: String) async throws -> String {
        switch auth {
        case let .apiKey(key):
            let request = try Self.makeRequest(apiKey: key, model: model, staticSystem: staticSystem, snapshot: snapshot, question: question)
            let (data, response) = try await session.data(for: request)
            return try Self.parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        case let .proxy(base, token):
            let request = try Self.makeProxyRequest(base: base, sessionToken: token, staticSystem: staticSystem, snapshot: snapshot, question: question)
            let (data, response) = try await session.data(for: request)
            return try Self.parseProxy(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}
