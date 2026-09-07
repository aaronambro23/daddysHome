import Foundation

/// One row of the map between a local thing (a project folder, or a
/// project+category bucket file) and the Drive object it became. This is not
/// a cache — under the `drive.file` scope the app can never rediscover its
/// own folder tree by browsing Drive, so if this file is ever lost, the
/// coordinator's only recovery is to recreate everything as new Drive
/// objects.
public struct DriveSyncEntry: Codable, Sendable, Equatable {
    /// `"root"` for the app's Drive root folder, `"folder:<project>"` for a
    /// project folder, or `"category:<project>/<category>"` for a bucket
    /// file.
    public let localID: String
    public let driveFileID: String
    public var lastSyncedAt: Date

    public init(localID: String, driveFileID: String, lastSyncedAt: Date) {
        self.localID = localID
        self.driveFileID = driveFileID
        self.lastSyncedAt = lastSyncedAt
    }
}

private struct DriveSyncState: Codable {
    var entries: [DriveSyncEntry]
    var pendingBuckets: [PendingBucket]
}

/// A `CategoryBucket` shaped for JSON round-tripping without DaddyCore
/// depending on DaddyApp's model — the coordinator maps to/from its own
/// `CategoryBucket` type.
public struct PendingBucket: Codable, Sendable, Hashable {
    public let projectFolderName: String
    public let categoryFolderName: String

    public init(projectFolderName: String, categoryFolderName: String) {
        self.projectFolderName = projectFolderName
        self.categoryFolderName = categoryFolderName
    }
}

/// Persists sync entries + the offline queue as atomic JSON in Application
/// Support, same pattern as `SessionStore`. The queue is just "these buckets
/// need re-pushing" — content is always re-read fresh from the local file at
/// flush time, so there's nothing stale to snapshot here.
public final class DriveSyncIndex: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
    }

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")

        return support
            .appendingPathComponent("Daddy", isDirectory: true)
            .appendingPathComponent("drive-sync-index.json")
    }

    public func loadEntries() -> [DriveSyncEntry] {
        readState().entries
    }

    public func loadPendingBuckets() -> [PendingBucket] {
        readState().pendingBuckets
    }

    public func save(entries: [DriveSyncEntry], pendingBuckets: [PendingBucket]) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(DriveSyncState(entries: entries, pendingBuckets: pendingBuckets))
            try data.write(to: url, options: .atomic)
        } catch {
            print("DriveSyncIndex: could not save — \(error.localizedDescription)")
        }
    }

    private func readState() -> DriveSyncState {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(DriveSyncState.self, from: data) else {
            return DriveSyncState(entries: [], pendingBuckets: [])
        }
        return state
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
