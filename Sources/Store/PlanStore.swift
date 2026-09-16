import Foundation
import Observation

/// The user's blocks, persisted as JSON in Application Support. Installs that predate the editor
/// (they already have a completions file) are seeded with the original hard-coded day; fresh
/// installs get onboarding.
@Observable
@MainActor
final class PlanStore {
    private(set) var blocks: [Block] = []
    private(set) var needsOnboarding = false
    private let fileURL: URL

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plan.json")
    }

    init(fileURL: URL = PlanStore.defaultURL, legacyMarker: URL = CompletionStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Block].self, from: data) {
            blocks = decoded
        } else if FileManager.default.fileExists(atPath: legacyMarker.path) {
            blocks = Plan.blocks
            save()
        } else {
            needsOnboarding = true
        }
    }

    func today(on date: Date, calendar: Calendar = .current) -> [Block] {
        blocks.filter { $0.occurs(on: date, calendar: calendar) }
    }

    func block(id: String) -> Block? {
        blocks.first { $0.id == id }
    }

    /// Replaces the whole plan (onboarding). Exactly one anchor is enforced.
    func replace(with newBlocks: [Block]) {
        blocks = Self.withSingleAnchor(newBlocks)
        needsOnboarding = false
        save()
    }

    /// Insert or update. Setting `isAnchor` on a block clears it on the others.
    func upsert(_ block: Block) {
        var next = blocks
        if let i = next.firstIndex(where: { $0.id == block.id }) {
            next[i] = block
        } else {
            next.append(block)
        }
        if block.isAnchor {
            for i in next.indices where next[i].id != block.id { next[i].isAnchor = false }
        }
        blocks = Self.withSingleAnchor(next)
        save()
    }

    /// The anchor block cannot be deleted.
    @discardableResult
    func delete(id: String) -> Bool {
        guard let block = block(id: id), !block.isAnchor else { return false }
        blocks.removeAll { $0.id == id }
        save()
        return true
    }

    /// Guarantees exactly one anchor: keeps the first flagged one, or flags the earliest block.
    static func withSingleAnchor(_ blocks: [Block]) -> [Block] {
        var result = blocks
        let anchors = result.indices.filter { result[$0].isAnchor }
        if anchors.isEmpty, let first = DayLogic.sorted(result).first,
           let i = result.firstIndex(where: { $0.id == first.id }) {
            result[i].isAnchor = true
        } else {
            for i in anchors.dropFirst() { result[i].isAnchor = false }
        }
        return result
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(blocks).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("PlanStore save failed: \(error)")
        }
    }
}
