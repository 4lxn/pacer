import Foundation
import Observation

/// One row of the visible conversation, derived from the raw API messages.
struct ChatEntry: Identifiable, Hashable {
    enum Role: Hashable { case user, assistant, tool }
    let id: String
    let role: Role
    let text: String
}

/// Persists the raw Messages-API `messages` array so assistant blocks (thinking, tool_use) replay
/// unchanged. Trimmed at user-text boundaries so tool_use / tool_result pairs are never split.
@Observable
@MainActor
final class CoachChatStore {
    private(set) var messages: [[String: Any]] = []
    private(set) var entries: [ChatEntry] = []
    /// One-line confirmations returned by write tools, keyed by tool_use id, for the transcript.
    private var toolSummaries: [String: String] = [:]

    static let maxMessages = 40
    private let fileURL: URL

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat.json")
    }

    init(fileURL: URL = CoachChatStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            messages = json["messages"] as? [[String: Any]] ?? []
            toolSummaries = json["toolSummaries"] as? [String: String] ?? [:]
        }
        rebuildEntries()
    }

    func appendUser(text: String) {
        messages.append(["role": "user", "content": text])
        persist()
    }

    func appendAssistant(content: [[String: Any]]) {
        messages.append(["role": "assistant", "content": content])
        persist()
    }

    func appendToolResults(_ results: [(id: String, output: String, summary: String?)]) {
        let blocks: [[String: Any]] = results.map { ["type": "tool_result", "tool_use_id": $0.id, "content": $0.output] }
        for r in results { if let s = r.summary { toolSummaries[r.id] = s } }
        messages.append(["role": "user", "content": blocks])
        persist()
    }

    /// Drops a trailing, unanswered assistant tool_use turn (after a failed loop) so the next
    /// request is well-formed.
    func dropDanglingToolUse() {
        guard let last = messages.last, last["role"] as? String == "assistant",
              let content = last["content"] as? [[String: Any]],
              content.contains(where: { $0["type"] as? String == "tool_use" }) else { return }
        messages.removeLast()
        persist()
    }

    func clear() {
        messages = []
        toolSummaries = [:]
        persist()
    }

    // MARK: - Trimming

    static func trimmed(_ messages: [[String: Any]], max: Int) -> [[String: Any]] {
        guard messages.count > max else { return messages }
        // Cut at the earliest user *text* message that keeps the count ≤ max.
        var start = messages.count - max
        while start < messages.count {
            let m = messages[start]
            if m["role"] as? String == "user", m["content"] is String { break }
            start += 1
        }
        return Array(messages[start...])
    }

    private func persist() {
        messages = Self.trimmed(messages, max: Self.maxMessages)
        rebuildEntries()
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["messages": messages, "toolSummaries": toolSummaries])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            PersistenceState.shared.report("Couldn't save chat.json")
        }
    }

    private func rebuildEntries() {
        var out: [ChatEntry] = []
        for (i, m) in messages.enumerated() {
            let role = m["role"] as? String
            if let text = m["content"] as? String {
                out.append(ChatEntry(id: "\(i)-u", role: .user, text: text))
                continue
            }
            guard let blocks = m["content"] as? [[String: Any]] else { continue }
            for (j, b) in blocks.enumerated() {
                switch b["type"] as? String {
                case "text":
                    if role == "assistant", let t = b["text"] as? String, !t.isEmpty {
                        out.append(ChatEntry(id: "\(i)-\(j)-a", role: .assistant, text: t))
                    }
                case "tool_result":
                    if let id = b["tool_use_id"] as? String, let summary = toolSummaries[id] {
                        out.append(ChatEntry(id: "\(i)-\(j)-t", role: .tool, text: summary))
                    }
                default:
                    break
                }
            }
        }
        entries = out
    }
}
