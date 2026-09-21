import Foundation
import Observation

/// One row of the visible conversation, derived from the raw API messages.
struct ChatEntry: Identifiable, Hashable {
    enum Role: Hashable { case user, assistant, tool }
    let id: String
    let role: Role
    let text: String
}

/// One conversation in the history list.
struct Conversation: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
}

/// Conversations with the coach. The current one is the raw Messages-API `messages` array so
/// assistant blocks (thinking, tool_use) replay unchanged, trimmed at user-text boundaries so
/// tool_use / tool_result pairs are never split. `chats.json` is the index; each conversation is
/// `chats/<id>.json`. The pre-history `chat.json` becomes the first conversation.
@Observable
@MainActor
final class CoachChatStore {
    private(set) var conversations: [Conversation] = []   // newest first
    private(set) var current: Conversation
    private(set) var messages: [[String: Any]] = []
    private(set) var entries: [ChatEntry] = []
    /// One-line confirmations returned by write tools, keyed by tool_use id, for the transcript.
    private var toolSummaries: [String: String] = [:]

    static let maxMessages = 40
    static let maxConversations = 50
    private let indexURL: URL
    private let directory: URL

    static var defaultURL: URL { AppFiles.url("chat.json") }

    /// `fileURL` is the legacy single-chat file; history lives next to it.
    init(fileURL: URL = CoachChatStore.defaultURL) {
        directory = fileURL.deletingLastPathComponent().appendingPathComponent("chats", isDirectory: true)
        indexURL = fileURL.deletingLastPathComponent().appendingPathComponent("chats.json")
        if case .loaded(let list) = JSONFile.load([Conversation].self, from: indexURL), let first = list.first {
            conversations = list
            current = first
        } else {
            let first = Conversation(id: UUID().uuidString, title: "New chat", createdAt: .now, updatedAt: .now)
            conversations = [first]
            current = first
            // Adopt the legacy chat.json as this first conversation.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? FileManager.default.moveItem(at: fileURL, to: directory.appendingPathComponent("\(first.id).json"))
            }
        }
        load(current)
        if current.title == "New chat", let firstUser = messages.first(where: { $0["content"] is String })?["content"] as? String {
            rename(current.id, to: Self.title(from: firstUser))
        }
    }

    // MARK: - Conversations

    func newConversation() {
        if messages.isEmpty { return }   // already on a blank one
        let c = Conversation(id: UUID().uuidString, title: "New chat", createdAt: .now, updatedAt: .now)
        conversations.insert(c, at: 0)
        current = c
        messages = []; toolSummaries = [:]
        rebuildEntries()
        saveIndex()
    }

    func open(_ id: String) {
        guard let c = conversations.first(where: { $0.id == id }), c.id != current.id else { return }
        current = c
        load(c)
    }

    func delete(_ id: String) {
        conversations.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
        if current.id == id {
            if let next = conversations.first { current = next; load(next) } else {
                let c = Conversation(id: UUID().uuidString, title: "New chat", createdAt: .now, updatedAt: .now)
                conversations = [c]; current = c; messages = []; toolSummaries = [:]; rebuildEntries()
            }
        }
        saveIndex()
    }

    func rename(_ id: String, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[i].title = clean
        if current.id == id { current.title = clean }
        saveIndex()
    }

    /// First line of the first message, trimmed; the auto title.
    static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 40 ? String(line.prefix(40)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    func appendUser(text: String) {
        if messages.isEmpty { rename(current.id, to: Self.title(from: text)) }
        messages.append(["role": "user", "content": text])
        persist()
    }

    func appendAssistant(content: [[String: Any]]) {
        guard !content.isEmpty else { return }   // the API rejects empty content
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

    /// Empties the current conversation (kept in the list).
    func clear() {
        messages = []
        toolSummaries = [:]
        persist()
    }

    // MARK: - Trimming

    /// Drops assistant turns with no content (left behind by an earlier streaming bug); the API
    /// refuses a conversation that contains one.
    static func sanitized(_ messages: [[String: Any]]) -> [[String: Any]] {
        messages.filter { !($0["role"] as? String == "assistant" && ($0["content"] as? [Any])?.isEmpty == true) }
    }

    static func trimmed(_ messages: [[String: Any]], max: Int) -> [[String: Any]] {
        let messages = sanitized(messages)
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
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["messages": messages, "toolSummaries": toolSummaries])
            try data.write(to: directory.appendingPathComponent("\(current.id).json"), options: .atomic)
        } catch {
            PersistenceState.shared.report("Couldn't save the chat")
        }
        // Bump to the top of the list.
        if let i = conversations.firstIndex(where: { $0.id == current.id }) {
            conversations[i].updatedAt = .now
            current = conversations[i]
            conversations.sort { $0.updatedAt > $1.updatedAt }
        }
        saveIndex()
    }

    private func load(_ c: Conversation) {
        messages = []; toolSummaries = [:]
        if let data = try? Data(contentsOf: directory.appendingPathComponent("\(c.id).json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            messages = Self.sanitized(json["messages"] as? [[String: Any]] ?? [])
            toolSummaries = json["toolSummaries"] as? [String: String] ?? [:]
        }
        rebuildEntries()
    }

    private func saveIndex() {
        if conversations.count > Self.maxConversations {
            for old in conversations[Self.maxConversations...] { try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(old.id).json")) }
            conversations = Array(conversations.prefix(Self.maxConversations))
        }
        JSONFile.save(conversations, to: indexURL)
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
