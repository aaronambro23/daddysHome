import Foundation

public enum ProviderUsageAvailability: Sendable, Equatable {
    case available
    case stale(String)
    case unavailable(String)
    case failed(String)
}

public struct ProviderUsageWindow: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.label = label
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        100 - usedPercent
    }
}

public struct ProviderUsageSnapshot: Sendable, Equatable {
    public let provider: AgentKind
    public let windows: [ProviderUsageWindow]
    public let fetchedAt: Date
    public let availability: ProviderUsageAvailability

    public init(
        provider: AgentKind,
        windows: [ProviderUsageWindow],
        fetchedAt: Date = Date(),
        availability: ProviderUsageAvailability = .available
    ) {
        self.provider = provider
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.availability = availability
    }

    public func markedStale(_ reason: String) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            windows: windows,
            fetchedAt: fetchedAt,
            availability: .stale(reason)
        )
    }
}

public actor ProviderUsageService {
    private var cache: [AgentKind: ProviderUsageSnapshot] = [:]

    public init() {}

    public func refresh(
        _ providers: [AgentKind] = [.claude, .codex, .cursor, .opencode]
    ) async -> [AgentKind: ProviderUsageSnapshot] {
        let previous = cache

        let fetched = await withTaskGroup(
            of: (AgentKind, Result<ProviderUsageSnapshot, ProviderUsageError>).self
        ) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return (provider, .success(try await ProviderUsageCollector.fetch(provider)))
                    } catch let error as ProviderUsageError {
                        return (provider, .failure(error))
                    } catch {
                        return (provider, .failure(.failed("Unexpected provider response")))
                    }
                }
            }

            var results: [AgentKind: ProviderUsageSnapshot] = [:]
            for await (provider, result) in group {
                switch result {
                case .success(let snapshot):
                    results[provider] = snapshot
                case .failure(let error):
                    if let old = previous[provider], !old.windows.isEmpty {
                        results[provider] = old.markedStale(error.message)
                    } else {
                        results[provider] = ProviderUsageSnapshot(
                            provider: provider,
                            windows: [],
                            availability: error.availability
                        )
                    }
                }
            }
            return results
        }

        cache.merge(fetched) { _, new in new }
        return cache
    }
}

public enum ProviderUsageError: Error, Sendable {
    case unavailable(String)
    case failed(String)

    var message: String {
        switch self {
        case .unavailable(let message), .failed(let message):
            return message
        }
    }

    var availability: ProviderUsageAvailability {
        switch self {
        case .unavailable(let message): return .unavailable(message)
        case .failed(let message): return .failed(message)
        }
    }
}

enum ProviderUsageCollector {
    static func fetch(_ provider: AgentKind) async throws -> ProviderUsageSnapshot {
        switch provider {
        case .claude: return try await fetchClaude()
        case .codex: return try await fetchCodex()
        case .cursor: return try await fetchCursor()
        case .opencode: return try await fetchOpenCode()
        }
    }

    private static func fetchClaude() async throws -> ProviderUsageSnapshot {
        let token = try await claudeToken()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.234", forHTTPHeaderField: "User-Agent")

        let data = try await responseData(for: request, provider: "Claude")
        return try ProviderUsageParser.claude(data)
    }

    private static func fetchOpenCode() async throws -> ProviderUsageSnapshot {
        let token = try openCodeToken()
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await responseData(for: request, provider: "OpenCode")
        return try ProviderUsageParser.openCode(data)
    }

    private static func fetchCursor() async throws -> ProviderUsageSnapshot {
        let token = try await cursorToken()
        var request = URLRequest(
            url: URL(
                string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
            )!
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        let data = try await responseData(for: request, provider: "Cursor")
        return try ProviderUsageParser.cursor(data)
    }

    private static func fetchCodex() async throws -> ProviderUsageSnapshot {
        let data = try await Task.detached(priority: .utility) {
            guard let executable = ExecutableResolver.resolve("codex"),
                  FileManager.default.isExecutableFile(atPath: executable) else {
                throw ProviderUsageError.unavailable("Codex CLI is not installed")
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["app-server"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            do {
                try process.run()
                let initialize = """
                {"method":"initialize","id":0,"params":{"clientInfo":{"name":"daddy","title":"Daddy","version":"1"}}}
                """
                try input.fileHandleForWriting.write(contentsOf: Data((initialize + "\n").utf8))
                try await Task.sleep(for: .milliseconds(650))
                let request = #"{"method":"account/rateLimits/read","id":1,"params":{}}"#
                try input.fileHandleForWriting.write(contentsOf: Data((request + "\n").utf8))
                try await Task.sleep(for: .milliseconds(650))
                try input.fileHandleForWriting.close()

                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw ProviderUsageError.failed("Codex usage service failed")
                }
                return data
            } catch let error as ProviderUsageError {
                throw error
            } catch {
                if process.isRunning { process.terminate() }
                throw ProviderUsageError.failed("Could not query Codex usage")
            }
        }.value

        return try ProviderUsageParser.codex(data)
    }

    private static func responseData(
        for request: URLRequest,
        provider: String
    ) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderUsageError.failed("\(provider) returned an invalid response")
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw ProviderUsageError.unavailable("\(provider) sign-in needs attention")
            case 429:
                throw ProviderUsageError.failed("\(provider) usage endpoint is rate-limited")
            default:
                throw ProviderUsageError.failed("\(provider) usage returned HTTP \(http.statusCode)")
            }
        } catch let error as ProviderUsageError {
            throw error
        } catch {
            throw ProviderUsageError.failed("\(provider) usage is unreachable")
        }
    }

    private static func claudeToken() async throws -> String {
        if let token = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !token.isEmpty {
            return token
        }

        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: path),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = object["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           !token.isEmpty {
            return token
        }

        #if os(macOS)
        if let data = try? await runProcess(
            "/usr/bin/security",
            ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        ),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = object["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           !token.isEmpty {
            return token
        }
        #endif

        throw ProviderUsageError.unavailable("Sign in to Claude Code")
    }

    private static func openCodeToken() throws -> String {
        if let token = ProcessInfo.processInfo.environment["OPENCODE_API_KEY"],
           !token.isEmpty {
            return token
        }

        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
        guard let data = try? Data(contentsOf: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = object["opencode-go"] as? [String: Any],
              let token = auth["key"] as? String,
              !token.isEmpty else {
            throw ProviderUsageError.unavailable("Connect an OpenCode Go account")
        }
        return token
    }

    private static func cursorToken() async throws -> String {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw ProviderUsageError.unavailable("Cursor is not signed in")
        }

        let query = "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;"
        guard let data = try? await runProcess(
            "/usr/bin/sqlite3",
            [database.path, query]
        ),
              let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw ProviderUsageError.unavailable("Cursor is not signed in")
        }
        return token
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors

            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ProviderUsageError.failed("Credential lookup failed")
            }
            return data
        }.value
    }
}

enum ProviderUsageParser {
    static func claude(_ data: Data) throws -> ProviderUsageSnapshot {
        let root = try dictionary(data, provider: "Claude")
        var windows: [ProviderUsageWindow] = []

        if let limits = root["limits"] as? [[String: Any]] {
            if let session = limits.first(where: { $0["kind"] as? String == "session" }) {
                windows.append(window(session, id: "session", label: "Current session"))
            }
            if let weekly = limits.first(where: { $0["kind"] as? String == "weekly_all" }) {
                windows.append(window(weekly, id: "all-models", label: "All models"))
            }
        }

        if windows.isEmpty {
            if let session = root["five_hour"] as? [String: Any] {
                windows.append(legacyWindow(session, id: "session", label: "Current session"))
            }
            if let weekly = root["seven_day"] as? [String: Any] {
                windows.append(legacyWindow(weekly, id: "all-models", label: "All models"))
            }
        }

        guard !windows.isEmpty else {
            throw ProviderUsageError.failed("Claude usage format changed")
        }
        return ProviderUsageSnapshot(provider: .claude, windows: windows)
    }

    static func openCode(_ data: Data) throws -> ProviderUsageSnapshot {
        let root = try dictionary(data, provider: "OpenCode")
        guard let usage = root["usage"] as? [String: Any] else {
            throw ProviderUsageError.failed("OpenCode usage format changed")
        }

        let definitions = [
            ("rolling", "Rolling usage"),
            ("weekly", "Weekly usage"),
            ("monthly", "Monthly usage"),
        ]
        let windows = definitions.compactMap { id, label -> ProviderUsageWindow? in
            guard let value = usage[id] as? [String: Any] else { return nil }
            return window(value, id: id, label: label)
        }
        guard windows.count == definitions.count else {
            throw ProviderUsageError.failed("OpenCode usage format changed")
        }
        return ProviderUsageSnapshot(provider: .opencode, windows: windows)
    }

    static func cursor(_ data: Data) throws -> ProviderUsageSnapshot {
        let root = try dictionary(data, provider: "Cursor")
        guard let plan = root["planUsage"] as? [String: Any] else {
            throw ProviderUsageError.failed("Cursor usage format changed")
        }
        let reset = date(root["billingCycleEnd"])
        guard let cursorModels = number(plan["autoPercentUsed"]),
              let otherModels = number(plan["apiPercentUsed"]) else {
            throw ProviderUsageError.failed("Cursor usage format changed")
        }

        return ProviderUsageSnapshot(
            provider: .cursor,
            windows: [
                ProviderUsageWindow(
                    id: "cursor-models",
                    label: "Cursor models",
                    usedPercent: cursorModels,
                    resetsAt: reset
                ),
                ProviderUsageWindow(
                    id: "other-models",
                    label: "Other models",
                    usedPercent: otherModels,
                    resetsAt: reset
                ),
            ]
        )
    }

    static func codex(_ data: Data) throws -> ProviderUsageSnapshot {
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        let payload = lines.lazy.compactMap { line -> [String: Any]? in
            guard let bytes = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  number(root["id"]) == 1 else { return nil }
            return root
        }.first

        guard let result = payload?["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            throw ProviderUsageError.failed("Codex usage format changed")
        }

        var windows: [ProviderUsageWindow] = []
        if let primary = limits["primary"] as? [String: Any] {
            windows.append(codexWindow(primary, id: "primary"))
        }
        if let secondary = limits["secondary"] as? [String: Any] {
            windows.append(codexWindow(secondary, id: "secondary"))
        }
        guard !windows.isEmpty else {
            throw ProviderUsageError.unavailable("Codex did not report quota windows")
        }
        return ProviderUsageSnapshot(provider: .codex, windows: windows)
    }

    private static func codexWindow(_ value: [String: Any], id: String) -> ProviderUsageWindow {
        let minutes = Int(number(value["windowDurationMins"]) ?? 0)
        let label: String
        switch minutes {
        case 1...360: label = "5-hour"
        case 361...10_080: label = "Weekly"
        case 10_081...50_000: label = "Monthly"
        default: label = id == "primary" ? "Short-term" : "Long-term"
        }
        return ProviderUsageWindow(
            id: id,
            label: label,
            usedPercent: number(value["usedPercent"]) ?? 0,
            resetsAt: date(value["resetsAt"])
        )
    }

    private static func window(
        _ value: [String: Any],
        id: String,
        label: String
    ) -> ProviderUsageWindow {
        ProviderUsageWindow(
            id: id,
            label: label,
            usedPercent: number(value["percent"]) ?? 0,
            resetsAt: date(value["resetsAt"] ?? value["resets_at"])
        )
    }

    private static func legacyWindow(
        _ value: [String: Any],
        id: String,
        label: String
    ) -> ProviderUsageWindow {
        ProviderUsageWindow(
            id: id,
            label: label,
            usedPercent: number(value["utilization"]) ?? 0,
            resetsAt: date(value["resets_at"])
        )
    }

    private static func dictionary(_ data: Data, provider: String) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderUsageError.failed("\(provider) returned invalid JSON")
        }
        return root
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
        }
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
