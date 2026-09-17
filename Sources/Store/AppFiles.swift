import Foundation
import OSLog

/// Where the JSON stores live: the App Group container (shared with the widget), or Application
/// Support when the group isn't available (tests, missing entitlement).
enum AppFiles {
    static let groupID = "group.com.alan.autopiloto"
    private static let log = Logger(subsystem: "com.alan.autopiloto", category: "persistence")

    static let directory: URL = {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return group.appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        return legacyDirectory
    }()

    static var legacyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// One-time move of the pre-App-Group files. Runs at launch, before any store loads; a file
    /// that already exists in the group wins.
    static func migrateLegacyFiles() {
        guard directory != legacyDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: legacyDirectory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names where name.hasSuffix(".json") {
            let to = url(name)
            guard !FileManager.default.fileExists(atPath: to.path) else { continue }
            do {
                try FileManager.default.moveItem(at: legacyDirectory.appendingPathComponent(name), to: to)
                log.info("Moved \(name) into the app group")
            } catch {
                log.error("Could not move \(name): \(error.localizedDescription)")
            }
        }
    }
}
