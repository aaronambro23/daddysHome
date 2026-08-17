import Foundation

public struct HEXTranscription: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let timestamp: Date
    public let sourceAppName: String?
    public let sourceAppBundleID: String?

    enum CodingKeys: String, CodingKey {
        case id, text, timestamp, sourceAppName, sourceAppBundleID
    }
}

private struct HEXHistoryDocument: Decodable {
    let history: [HEXTranscription]
}

public final class HEXWatcher: @unchecked Sendable {
    private let hexPath: URL
    private var seenIDs: Set<String> = []
    private var hasBaseline = false
    private var watcher: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.daddy.hex-watcher")
    private var onNewTranscription: (@MainActor @Sendable (String) -> Void)?

    public convenience init?() {
        let containerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/transcription_history.json")

        self.init(historyURL: containerPath)
    }

    init?(historyURL: URL) {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return nil }
        self.hexPath = historyURL
    }

    /// Starts at the current end of history. Existing recordings are deliberately
    /// treated as seen so launching Daddy never replays old commands.
    public func start(
        onNewTranscription: @escaping @MainActor @Sendable (String) -> Void
    ) {
        queue.sync {
            guard watcher == nil else { return }
            self.onNewTranscription = onNewTranscription
            self.hasBaseline = false
            self.seenIDs.removeAll(keepingCapacity: true)
            self.setupDirectoryWatcher()
            self.readNewTranscriptions()
        }
    }

    /// HEX rewrites its JSON document and may replace the file. Watching the
    /// containing directory survives that replacement; watching the old file
    /// descriptor does not.
    private func setupDirectoryWatcher() {
        let directory = hexPath.deletingLastPathComponent()
        let fd = open(directory.path, O_EVTONLY)
        guard fd != -1 else {
            print("Failed to watch HEX history directory")
            return
        }
        directoryDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.readNewTranscriptions()
        }
        source.setCancelHandler { [weak self] in
            close(fd)
            self?.directoryDescriptor = -1
        }
        self.watcher = source
        source.resume()
    }

    private func readNewTranscriptions() {
        do {
            let history = try readHistory()
            guard hasBaseline else {
                seenIDs = Set(history.map(\.id))
                hasBaseline = true
                return
            }
            let unseen = history
                .filter { !seenIDs.contains($0.id) }
                .sorted { $0.timestamp < $1.timestamp }
            seenIDs.formUnion(history.map(\.id))

            for transcription in unseen where Self.targetsDaddy(transcription) {
                guard let callback = onNewTranscription else { continue }
                let text = transcription.text
                Task { @MainActor in callback(text) }
            }
        } catch {
            // HEX can notify while its replacement file is only partially
            // written. Retry after the atomic save has had time to finish.
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard self?.watcher != nil else { return }
                self?.readNewTranscriptions()
            }
        }
    }

    private func readHistory() throws -> [HEXTranscription] {
        let data = try Data(contentsOf: hexPath, options: .mappedIfSafe)
        return try JSONDecoder().decode(HEXHistoryDocument.self, from: data).history
    }

    private static func targetsDaddy(_ transcription: HEXTranscription) -> Bool {
        if transcription.sourceAppBundleID == "com.aaronambrosi.daddy" {
            return true
        }
        return transcription.sourceAppName == "Daddy"
            || transcription.sourceAppName == "DaddyApp"
    }

    public func stop() {
        queue.sync {
            watcher?.cancel()
            watcher = nil
            onNewTranscription = nil
        }
    }

    deinit {
        stop()
    }
}
