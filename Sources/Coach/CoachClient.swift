import Foundation

/// The only network code in the app: one POST to the Claude Messages API per question.
struct CoachClient: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let defaultModel = "claude-opus-5"

    var apiKey: String
    var model = CoachClient.defaultModel
    var session: URLSession = .shared

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
        let request = try Self.makeRequest(apiKey: apiKey, model: model, staticSystem: staticSystem, snapshot: snapshot, question: question)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parse(data, status: status)
    }
}
