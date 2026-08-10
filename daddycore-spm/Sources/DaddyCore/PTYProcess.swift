import Foundation

public final class PTYProcess {
    public enum PTYError: LocalizedError {
        case processFailed(String)
        case alreadyTerminated
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .processFailed(let msg):
                return "Process failed: \(msg)"
            case .alreadyTerminated:
                return "Process already terminated"
            case .writeFailed(let msg):
                return "Write failed: \(msg)"
            }
        }
    }

    private let process: Process
    private let inputPipe: Pipe
    private let outputPipe: Pipe
    private var outputBuffer: String = ""
    private var isRunning = false
    private var outputCallbacks: [(String) -> Void] = []
    private let lock = NSLock()

    public init(executablePath: String, arguments: [String], cwd: URL) {
        self.process = Process()
        self.inputPipe = Pipe()
        self.outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
    }

    public func launch() throws {
        do {
            try process.run()
            isRunning = true

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureOutput()
            }
        } catch {
            throw PTYError.processFailed(error.localizedDescription)
        }
    }

    public func write(_ data: String) throws {
        guard isRunning else { throw PTYError.alreadyTerminated }

        guard let data = data.data(using: .utf8) else {
            throw PTYError.writeFailed("Could not encode string as UTF-8")
        }

        inputPipe.fileHandleForWriting.write(data)
    }

    public func registerOutputCallback(_ callback: @escaping (String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        outputCallbacks.append(callback)
    }

    public func terminate() {
        if isRunning {
            process.terminate()
            isRunning = false
        }
    }

    public func waitUntilExit() -> Int32 {
        process.waitUntilExit()
        isRunning = false
        return process.terminationStatus
    }

    public var isProcessRunning: Bool {
        isRunning && process.isRunning
    }

    public var recentOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return outputBuffer
    }

    private func captureOutput() {
        let fileHandle = outputPipe.fileHandleForReading

        while isRunning && process.isRunning {
            let data = fileHandle.availableData
            if data.isEmpty {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }

            if let string = String(data: data, encoding: .utf8) {
                lock.lock()
                outputBuffer.append(string)

                let lines = outputBuffer.split(separator: "\n", omittingEmptySubsequences: false)
                if lines.count > 100 {
                    let keptLines = lines.suffix(100)
                    outputBuffer = keptLines.joined(separator: "\n")
                }

                let callbacks = outputCallbacks
                lock.unlock()

                for callback in callbacks {
                    callback(outputBuffer)
                }
            }
        }
    }
}
