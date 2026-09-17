import Foundation
import Observation

/// The tool-use loop: user text → model → run tools → model … → final text. Everything the model
/// says and does is appended to `CoachChatStore` verbatim so the next turn has full context.
@Observable
@MainActor
final class CoachAgent {
    let chat: CoachChatStore
    let tools: CoachTools
    private(set) var isBusy = false
    private(set) var lastError: String?
    private(set) var remaining: Int?
    /// A prompt another section wants asked (e.g. Food → "Plan my meals"). The Coach tab picks it up.
    var queued: String?
    /// Text of the answer being streamed right now, before it lands in the chat.
    private(set) var partial = ""

    static let maxIterations = 8

    init(chat: CoachChatStore, tools: CoachTools) {
        self.chat = chat
        self.tools = tools
    }

    func send(_ text: String, client: CoachClient, systemBlocks: [[String: Any]]) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        chat.dropDanglingToolUse()
        chat.appendUser(text: trimmed)

        for _ in 0..<Self.maxIterations {
            let request: URLRequest
            do {
                request = try CoachClient.makeAgentRequest(auth: client.auth, model: client.model, system: systemBlocks, messages: chat.messages, tools: tools.enabledDefinitions)
            } catch {
                lastError = error.localizedDescription
                return
            }
            let response: CoachClient.AgentResponse
            partial = ""
            do {
                response = try await client.streamAgent(request) { [weak self] text in self?.partial += text }
            } catch {
                partial = ""
                lastError = error.localizedDescription
                return
            }
            partial = ""
            remaining = response.remaining
            chat.appendAssistant(content: response.content)

            switch response.stopReason {
            case "tool_use":
                let calls = response.content.filter { $0["type"] as? String == "tool_use" }
                var results: [(id: String, output: String, summary: String?)] = []
                for call in calls {
                    guard let id = call["id"] as? String, let name = call["name"] as? String else { continue }
                    let input = call["input"] as? [String: Any] ?? [:]
                    let r = tools.run(name: name, input: input)
                    results.append((id, r.isError ? "ERROR: \(r.output)" : r.output, r.summary))
                }
                chat.appendToolResults(results)
            case "max_tokens":
                lastError = "The answer was cut short; ask again for the rest."
                return
            case "refusal":
                lastError = (response.stopDetails?["explanation"] as? String) ?? "The model declined to answer."
                return
            default:
                return
            }
        }
        lastError = "Stopped after \(Self.maxIterations) tool calls."
    }
}
