import Foundation

private final class StreamTaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

/// A small client for Ollama's native HTTP API.
///
/// This intentionally does not use the PTY/AgentAdapter path. Ollama is the
/// orchestrator's inference service; Claude, Codex, Cursor and OpenCode remain
/// the interactive coding agents owned by SessionManager.
public final class OllamaClient: @unchecked Sendable {
    public enum ClientError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Ollama returned an invalid response"
            case .httpError(let status, let body):
                return "Ollama request failed (HTTP \(status)): \(body)"
            }
        }
    }

    public enum Event: Sendable {
        case text(String)
        case finished(OllamaResponse)
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    public init(baseURL: URL = URL(string: "http://localhost:11434/api")!) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Starts a streaming chat request. The returned stream finishes with one
    /// response containing the assistant message and any tool calls.
    public func chatStream(
        model: String,
        messages: [OllamaMessage],
        tools: [OllamaTool] = [],
        temperature: Double = 0.2
    ) -> AsyncThrowingStream<Event, Error> {
        let taskBox = StreamTaskBox()
        return AsyncThrowingStream { continuation in
            taskBox.task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("chat"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    // Ollama's native API requires non-streaming requests when
                    // tools are present. Plain conversation still streams, so
                    // the client keeps the responsive path without sending an
                    // invalid tools + stream combination.
                    let streams = tools.isEmpty
                    request.httpBody = try encoder.encode(
                        OllamaRequest(
                            model: model,
                            messages: messages,
                            tools: tools.isEmpty ? nil : tools,
                            stream: streams,
                            think: false,
                            keepAlive: "30m",
                            options: ["temperature": .number(temperature)]
                        )
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ClientError.invalidResponse
                    }

                    if !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                        }
                        throw ClientError.httpError(http.statusCode, body)
                    }

                    var assistant = OllamaMessage(role: .assistant, content: "")
                    var doneReason: String?

                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8) else { continue }

                        let chunk = try decoder.decode(OllamaChunk.self, from: data)
                        if let message = chunk.message {
                            if !message.content.isEmpty {
                                assistant.content += message.content
                                continuation.yield(Event.text(message.content))
                            }
                            if let calls = message.toolCalls, !calls.isEmpty {
                                assistant.toolCalls = calls
                            }
                        }
                        if chunk.doneReason != nil {
                            doneReason = chunk.doneReason
                        }
                    }

                    continuation.yield(
                        Event.finished(OllamaResponse(message: assistant, doneReason: doneReason))
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                taskBox.task?.cancel()
            }
        }
    }

    public func models() async throws -> [OllamaModel] {
        let request = URLRequest(url: baseURL.appendingPathComponent("tags"))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(OllamaModelsResponse.self, from: data).models
    }

    public func modelInfo(_ model: String) async throws -> OllamaModelInfo {
        var request = URLRequest(url: baseURL.appendingPathComponent("show"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["model": model])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(OllamaModelInfo.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpError(http.statusCode, body)
        }
    }
}

public enum OllamaRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct OllamaMessage: Codable, Sendable {
    public var role: OllamaRole
    public var content: String
    public var images: [String]?
    public var toolCalls: [OllamaToolCall]?
    public var toolName: String?

    public init(
        role: OllamaRole,
        content: String,
        images: [String]? = nil,
        toolCalls: [OllamaToolCall]? = nil,
        toolName: String? = nil
    ) {
        self.role = role
        self.content = content
        self.images = images
        self.toolCalls = toolCalls
        self.toolName = toolName
    }

    enum CodingKeys: String, CodingKey {
        case role, content, images
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }
}

public struct OllamaToolCall: Codable, Sendable {
    public var function: OllamaFunctionCall

    public init(function: OllamaFunctionCall) {
        self.function = function
    }
}

public struct OllamaFunctionCall: Codable, Sendable {
    public var name: String
    public var arguments: [String: JSONValue]

    public init(name: String, arguments: [String: JSONValue]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct OllamaTool: Codable, Sendable {
    public struct Function: Codable, Sendable {
        public var name: String
        public var description: String
        public var parameters: JSONValue

        public init(name: String, description: String, parameters: JSONValue) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public var type: String = "function"
    public var function: Function

    public init(function: Function) {
        self.function = function
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

public struct OllamaResponse: Sendable {
    public let message: OllamaMessage
    public let doneReason: String?
}

public struct OllamaModel: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let size: Int64?
    public let modifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case name, size
        case modifiedAt = "modified_at"
    }
}

public struct OllamaModelInfo: Codable, Sendable {
    public let capabilities: [String]?
}

private struct OllamaRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let tools: [OllamaTool]?
    let stream: Bool
    let think: Bool
    let keepAlive: String
    let options: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, think, options
        case keepAlive = "keep_alive"
    }
}

private struct OllamaChunk: Codable {
    let message: OllamaMessage?
    let done: Bool?
    let doneReason: String?

    enum CodingKeys: String, CodingKey {
        case message, done
        case doneReason = "done_reason"
    }
}

private struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}
