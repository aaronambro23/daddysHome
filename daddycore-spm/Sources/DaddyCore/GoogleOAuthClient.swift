import Foundation
import Network
import Security
import CryptoKit

/// Google's PKCE + loopback-redirect flow for a "Desktop app" OAuth client.
///
/// Deliberately not `ASWebAuthenticationSession` — that needs a custom URL
/// scheme or universal link registered in the app's bundle, and this app has
/// neither today. A loopback listener needs no new Info.plist/entitlement
/// surface at all: open the system browser, catch the one redirect on
/// `127.0.0.1` ourselves, done.
public final class GoogleOAuthClient: @unchecked Sendable {
    public struct Tokens: Sendable {
        public let accessToken: String
        public let refreshToken: String?
        public let idToken: String?
        public let expiresAt: Date
    }

    public enum ClientError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case listenerFailed(String)
        case userCancelled
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Google returned an invalid response"
            case .httpError(let status, let body):
                return "Google OAuth request failed (HTTP \(status)): \(body)"
            case .listenerFailed(let reason):
                return "Could not start the local sign-in listener: \(reason)"
            case .userCancelled:
                return "Sign-in was cancelled"
            case .timedOut:
                return "Sign-in timed out waiting for the browser"
            }
        }
    }

    private let clientID: String
    private let clientSecret: String
    private let scope: String
    private let session = URLSession(configuration: .default)
    private let decoder = JSONDecoder()

    public init(clientID: String, clientSecret: String, scope: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scope = scope
    }

    // MARK: - PKCE

    public static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    // MARK: - Authorization URL

    public func makeAuthorizationURL(codeVerifier: String, redirectURI: URL) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url!
    }

    // MARK: - Loopback listener

    /// Starts a one-shot HTTP listener on `127.0.0.1` to catch Google's
    /// redirect. Returns the redirect URI to embed in the authorization URL
    /// and an awaiter that resolves with the `code` once the browser lands on
    /// it, or throws if the user denied consent or nothing arrived in time.
    public func startLoopbackListener() async throws -> (redirectURI: URL, code: (TimeInterval) async throws -> String) {
        let listener = try NWListener(using: .tcp, on: .any)
        let box = LoopbackResultBox()

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Self.receiveRequestLine(on: connection) { query in
                connection.cancel()
                listener.cancel()
                box.resolve(query: query)
            }
        }

        let didResume = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                guard didResume.markIfFirst() else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        continuation.resume(throwing: ClientError.listenerFailed("no port bound"))
                        return
                    }
                    let redirectURI = URL(string: "http://127.0.0.1:\(port.rawValue)/callback")!
                    continuation.resume(returning: (redirectURI, { timeout in try await box.wait(timeout: timeout) }))
                case .failed(let error):
                    continuation.resume(throwing: ClientError.listenerFailed(error.localizedDescription))
                default:
                    didResume.reset()
                }
            }
            listener.start(queue: .main)
        }
    }

    private static func receiveRequestLine(on connection: NWConnection, completion: @escaping @Sendable (String?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            let requestLine = text.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = requestLine.split(separator: " ")
            let query: String? = {
                guard parts.count >= 2, let qIndex = parts[1].firstIndex(of: "?") else { return nil }
                return String(parts[1][parts[1].index(after: qIndex)...])
            }()

            let body = "<html><body style=\"font: -apple-system-body; padding: 40px;\">" +
                "Signed in. You can close this tab and return to Daddy.</body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" +
                "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                completion(query)
            })
        }
    }

    fileprivate static func extractCode(from query: String) -> String? {
        var components = URLComponents()
        components.query = query
        return components.queryItems?.first(where: { $0.name == "code" })?.value
    }

    // MARK: - Token exchange

    public func exchangeCode(_ code: String, codeVerifier: String, redirectURI: URL) async throws -> Tokens {
        try await requestTokens(params: [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ], fallbackRefreshToken: nil)
    }

    public func refreshAccessToken(_ refreshToken: String) async throws -> Tokens {
        try await requestTokens(params: [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ], fallbackRefreshToken: refreshToken)
    }

    private func requestTokens(params: [String: String], fallbackRefreshToken: String?) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let payload = try decoder.decode(TokenResponse.self, from: data)
        return Tokens(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken ?? fallbackRefreshToken,
            idToken: payload.idToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpError(http.statusCode, body)
        }
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        let pairs = params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    /// The account email, read off the ID token's JWT payload for display
    /// only — no signature verification, since it never gates access.
    public static func decodeEmail(fromIDToken idToken: String) -> String? {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return payload["email"] as? String
    }
}

/// Guards a one-shot continuation against `NWListener`'s state handler firing
/// from a background queue: `.ready`/`.failed` should resume exactly once,
/// while earlier transient states (`.setup`/`.waiting`) must not consume the
/// one shot.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func markIfFirst() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }

    func reset() {
        lock.lock()
        resumed = false
        lock.unlock()
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

/// Bridges the loopback listener's callback-based redirect capture to a
/// single `async` wait, resolving whichever arrives first: the redirect, or
/// a timeout.
private final class LoopbackResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?

    func resolve(query: String?) {
        let result: Result<String, Error>
        if let query, let code = GoogleOAuthClient.extractCode(from: query) {
            result = .success(code)
        } else {
            result = .failure(GoogleOAuthClient.ClientError.userCancelled)
        }
        deliver(result)
    }

    private func deliver(_ result: Result<String, Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            pendingResult = result
            lock.unlock()
        }
    }

    func wait(timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    self.lock.lock()
                    if let pendingResult = self.pendingResult {
                        self.pendingResult = nil
                        self.lock.unlock()
                        continuation.resume(with: pendingResult)
                    } else {
                        self.continuation = continuation
                        self.lock.unlock()
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw GoogleOAuthClient.ClientError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
