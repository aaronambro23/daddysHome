import Foundation

/// One agent card, as it survives a quit.
///
/// Only what is needed to put the card back and reopen its conversation. The
/// live parts — state, last line, the pty — are deliberately absent: a restored
/// card describes an agent that is no longer running, and pretending otherwise
/// would show a READY badge over a process that does not exist.
public struct SessionRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let projectID: String
    public let workUnitID: String
    public let agent: AgentKind
    public let model: String
    public let cwd: String
    /// The CLI's own id for the conversation, when it has one Daddy could
    /// learn. Nil means this card can only ask for the newest conversation in
    /// its directory.
    public let providerSessionID: String?
    public let startedAt: Date
    public let lastOutputAt: Date

    public init(
        id: String,
        projectID: String,
        workUnitID: String,
        agent: AgentKind,
        model: String,
        cwd: String,
        providerSessionID: String?,
        startedAt: Date,
        lastOutputAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.workUnitID = workUnitID
        self.agent = agent
        self.model = model
        self.cwd = cwd
        self.providerSessionID = providerSessionID
        self.startedAt = startedAt
        self.lastOutputAt = lastOutputAt
    }
}

/// Remembers which agents you had, across quits.
///
/// Application Support rather than a `.daddy` folder inside each project: this
/// is Daddy's own state, not the project's, and scattering a file into every
/// repository you ever open an agent in is a rude thing for an app to do. (The
/// app briefly had a reader for `.daddy/agents/*.json` that nothing ever wrote;
/// it is gone.)
public final class SessionStore: @unchecked Sendable {

    /// Cards kept before the oldest start dropping off. Generous — a record is
    /// a few hundred bytes — but not unbounded, because nothing else prunes it.
    public static let capacity = 200

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
            .appendingPathComponent("sessions.json")
    }

    /// Newest first. Returns nothing rather than throwing: a missing or corrupt
    /// file means "no history", which is a normal state on first run and not
    /// worth refusing to start over.
    public func load() -> [SessionRecord] {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let records = try? decoder.decode([SessionRecord].self, from: data) else { return [] }
        return records.sorted { $0.lastOutputAt > $1.lastOutputAt }
    }

    /// Writes atomically, so a crash mid-save cannot leave a half-written file
    /// that would read as "no history" on the next launch.
    public func save(_ records: [SessionRecord]) {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = Array(
            records
                .sorted { $0.lastOutputAt > $1.lastOutputAt }
                .prefix(Self.capacity)
        )

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(trimmed)
            try data.write(to: url, options: .atomic)
        } catch {
            // Losing the card list is a nuisance, not a reason to interrupt
            // whatever the person was doing.
            print("SessionStore: could not save — \(error.localizedDescription)")
        }
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
