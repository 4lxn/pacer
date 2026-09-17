import Foundation
import Observation
import OSLog

/// Persistence errors are never silent: they land here, in the log, and in a banner on Today.
@Observable
@MainActor
final class PersistenceState {
    static let shared = PersistenceState()
    private(set) var lastError: String?
    private(set) var errorCount = 0

    func report(_ message: String) {
        lastError = message
        errorCount += 1
    }

    func clear() { lastError = nil }
}

/// One load/save path for every store: atomic writes, undecodable files renamed to `.bad`
/// instead of being overwritten, every failure reported.
enum JSONFile {
    private static let log = Logger(subsystem: "com.alan.autopiloto", category: "persistence")

    enum Outcome<T> {
        case missing
        case loaded(T)
        case corrupt
    }

    /// `.corrupt` means the file existed, failed to decode, and was moved aside as `<name>.bad`.
    @MainActor
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> Outcome<T> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try JSONDecoder().decode(type, from: data))
        } catch {
            let bad = url.appendingPathExtension("bad")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: url, to: bad)
            let message = "Couldn't read \(url.lastPathComponent); kept a copy as \(bad.lastPathComponent)"
            log.error("\(message): \(error.localizedDescription)")
            PersistenceState.shared.report(message)
            return .corrupt
        }
    }

    @MainActor
    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            let message = "Couldn't save \(url.lastPathComponent)"
            log.error("\(message): \(error.localizedDescription)")
            PersistenceState.shared.report(message)
        }
    }
}
