import Foundation

public struct HEXTranscription: Codable {
    public let id: String
    public let text: String
    public let timestamp: Date
    public let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id, text, timestamp, confidence
    }
}

public final class HEXWatcher: @unchecked Sendable {
    private let hexPath: URL
    private var fileHandle: FileHandle?
    private var lastReadPosition: UInt64 = 0
    private var watcher: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.daddy.hex-watcher")
    public var onNewTranscription: ((String) -> Void)?

    public init?() {
        let containerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/transcription_history.json")

        guard FileManager.default.fileExists(atPath: containerPath.path) else {
            print("HEX transcription file not found at \(containerPath.path)")
            return nil
        }

        self.hexPath = containerPath
        setupFileWatcher()
    }

    private func setupFileWatcher() {
        let fd = open(hexPath.path, O_RDONLY)
        guard fd != -1 else {
            print("Failed to open HEX file")
            return
        }

        fileHandle = FileHandle(fileDescriptor: fd)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readNewTranscriptions()
        }

        source.setCancelHandler { [weak self] in
            self?.fileHandle = nil
            close(fd)
        }

        source.resume()
        self.watcher = source
    }

    private func readNewTranscriptions() {
        guard let fileHandle = fileHandle else { return }

        do {
            let data = try Data(contentsOf: hexPath)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }

            for item in json {
                if let text = item["text"] as? String {
                    let position = UInt64(text.utf8.count)
                    if position > lastReadPosition {
                        lastReadPosition = position

                        if let callback = onNewTranscription {
                            DispatchQueue.main.async {
                                callback(text)
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error reading HEX file: \(error)")
        }
    }

    public func stop() {
        watcher?.cancel()
    }

    deinit {
        stop()
    }
}
