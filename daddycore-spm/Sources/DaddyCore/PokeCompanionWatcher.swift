import Foundation

public final class PokeCompanionWatcher: @unchecked Sendable {
    private let companionStatePath: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.daddy.poke-watcher")
    private var onStateChange: (@MainActor @Sendable (PokeCompanionState) -> Void)?

    public convenience init?() {
        let containerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PokeTokenBar/companion-state.json")

        self.init(statePath: containerPath)
    }

    init?(statePath: URL) {
        guard FileManager.default.fileExists(atPath: statePath.path) else { return nil }
        self.companionStatePath = statePath
    }

    public func start(
        onStateChange: @escaping @MainActor @Sendable (PokeCompanionState) -> Void
    ) {
        queue.sync {
            guard watcher == nil else { return }
            self.onStateChange = onStateChange
            setupDirectoryWatcher()
            readState()
        }
    }

    private func setupDirectoryWatcher() {
        let directory = companionStatePath.deletingLastPathComponent()
        let fd = open(directory.path, O_EVTONLY)
        guard fd != -1 else {
            print("Failed to watch PokeTokenBar directory")
            return
        }
        directoryDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.readState()
        }
        source.setCancelHandler { [weak self] in
            close(fd)
            self?.directoryDescriptor = -1
        }
        self.watcher = source
        source.resume()
    }

    private func readState() {
        do {
            let state = try readCompanionState()
            guard let callback = onStateChange else { return }
            Task { @MainActor in callback(state) }
        } catch {
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard self?.watcher != nil else { return }
                self?.readState()
            }
        }
    }

    private func readCompanionState() throws -> PokeCompanionState {
        let data = try Data(contentsOf: companionStatePath, options: .mappedIfSafe)
        return try JSONDecoder().decode(PokeCompanionState.self, from: data)
    }

    public func stop() {
        queue.sync {
            watcher?.cancel()
            watcher = nil
            onStateChange = nil
        }
    }

    deinit {
        stop()
    }
}
