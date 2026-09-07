import Foundation

/// A small client for the Drive v3 REST API, scoped to what this app needs:
/// mirroring `<project>/<category>/<uuid>.md` as real Drive folders/files.
///
/// Every call here only ever touches files/folders this app itself created —
/// the `drive.file` scope grants nothing else, and `files.list` cannot
/// "discover" arbitrary Drive content. That means the caller (the sync
/// coordinator) must remember Drive file/folder IDs itself; this client never
/// re-derives them by browsing.
public final class GoogleDriveClient: @unchecked Sendable {
    public enum ClientError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case notFound

        public var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Drive returned an invalid response"
            case .httpError(let status, let body):
                return "Drive request failed (HTTP \(status)): \(body)"
            case .notFound:
                return "That Drive file no longer exists"
            }
        }
    }

    public struct DriveFile: Codable, Sendable {
        public let id: String
        public let name: String
        public let mimeType: String
    }

    public static let folderMimeType = "application/vnd.google-apps.folder"

    private let baseURL = URL(string: "https://www.googleapis.com/drive/v3")!
    private let uploadBaseURL = URL(string: "https://www.googleapis.com/upload/drive/v3")!
    private let session = URLSession(configuration: .default)
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let accessTokenProvider: @Sendable () async throws -> String

    public init(accessTokenProvider: @escaping @Sendable () async throws -> String) {
        self.accessTokenProvider = accessTokenProvider
    }

    public func createFolder(name: String, parentID: String?) async throws -> DriveFile {
        var metadata: [String: Any] = ["name": name, "mimeType": Self.folderMimeType]
        if let parentID { metadata["parents"] = [parentID] }

        var request = try await authorizedRequest(url: baseURL.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(DriveFile.self, from: data)
    }

    /// `mimeType` narrows the search when both a folder and a file could
    /// share a name in the same parent; pass nil to match either.
    public func findFile(name: String, parentID: String, mimeType: String? = nil) async throws -> DriveFile? {
        var query = "name = '\(Self.escape(name))' and '\(parentID)' in parents and trashed = false"
        if let mimeType { query += " and mimeType = '\(Self.escape(mimeType))'" }

        var components = URLComponents(url: baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType)"),
            URLQueryItem(name: "spaces", value: "drive")
        ]

        var request = try await authorizedRequest(url: components.url!)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(FileListResponse.self, from: data).files.first
    }

    public func createFile(name: String, parentID: String, markdown: String) async throws -> DriveFile {
        let metadata: [String: Any] = ["name": name, "parents": [parentID], "mimeType": "text/markdown"]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let boundary = "daddy-\(UUID().uuidString)"

        var body = Data()
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8Data)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".utf8Data)
        body.append("Content-Type: text/markdown\r\n\r\n".utf8Data)
        body.append(markdown.utf8Data)
        body.append("\r\n--\(boundary)--".utf8Data)

        var components = URLComponents(url: uploadBaseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "multipart")]

        var request = try await authorizedRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(DriveFile.self, from: data)
    }

    public func updateFileContent(fileID: String, markdown: String) async throws -> DriveFile {
        var components = URLComponents(
            url: uploadBaseURL.appendingPathComponent("files/\(fileID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "media")]

        var request = try await authorizedRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("text/markdown", forHTTPHeaderField: "Content-Type")
        request.httpBody = markdown.utf8Data

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(DriveFile.self, from: data)
    }

    public func deleteFile(fileID: String) async throws {
        var request = try await authorizedRequest(url: baseURL.appendingPathComponent("files/\(fileID)"))
        request.httpMethod = "DELETE"

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if http.statusCode == 404 { return } // already gone — nothing left to do
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    public func downloadContent(fileID: String) async throws -> String {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("files/\(fileID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]

        var request = try await authorizedRequest(url: components.url!)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func listFiles(inParent parentID: String) async throws -> [DriveFile] {
        var files: [DriveFile] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "q", value: "'\(parentID)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType)"),
                URLQueryItem(name: "spaces", value: "drive"),
                URLQueryItem(name: "pageSize", value: "100")
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = queryItems

            var request = try await authorizedRequest(url: components.url!)
            request.httpMethod = "GET"

            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            let page = try decoder.decode(FileListResponse.self, from: data)
            files.append(contentsOf: page.files)
            pageToken = page.nextPageToken
        } while pageToken != nil

        return files
    }

    private func authorizedRequest(url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        let token = try await accessTokenProvider()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if http.statusCode == 404 { throw ClientError.notFound }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpError(http.statusCode, body)
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
}

private struct FileListResponse: Codable {
    let files: [GoogleDriveClient.DriveFile]
    let nextPageToken: String?
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
