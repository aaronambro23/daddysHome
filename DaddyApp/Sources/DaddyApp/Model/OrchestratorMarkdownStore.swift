import Foundation

/// Stores orchestrator state as readable Markdown rather than introducing a
/// second private database. Work items are deliberately easy for a coding agent
/// to inspect during a dispatch.
final class OrchestratorMarkdownStore: @unchecked Sendable {
    private let rootURL: URL
    private let lock = NSLock()

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            self.rootURL = desktop.appendingPathComponent("DaddyWork/Orchestrator", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func loadWorkItems() -> [OrchestratorWorkItem] {
        lock.lock()
        defer { lock.unlock() }

        guard let files = try? allMarkdownFiles() else { return [] }
        return files.compactMap { parseWorkItem(at: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadConversations() -> [String: OrchestratorConversationSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        let directory = conversationsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [:] }

        var snapshots: [String: OrchestratorConversationSnapshot] = [:]
        for file in files where file.pathExtension == "md" {
            guard let snapshot = parseConversation(at: file) else { continue }
            if let expiresAt = snapshot.expiresAt, expiresAt <= Date() {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            snapshots[snapshot.key] = snapshot
        }
        return snapshots
    }

    func save(_ item: OrchestratorWorkItem) {
        lock.lock()
        defer { lock.unlock() }

        let directory = rootURL.appendingPathComponent(item.category.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(item.id.uuidString).md")
        if let copies = try? allMarkdownFiles() {
            for copy in copies where copy.lastPathComponent == url.lastPathComponent && copy != url {
                try? FileManager.default.removeItem(at: copy)
            }
        }
        try? format(item).write(to: url, atomically: true, encoding: .utf8)
    }

    func fileURL(for item: OrchestratorWorkItem) -> URL {
        rootURL
            .appendingPathComponent(item.category.folderName, isDirectory: true)
            .appendingPathComponent("\(item.id.uuidString).md")
    }

    /// Removes a work item's Markdown file. The board can delete cards, and
    /// without this the file would survive and reappear on the next load.
    /// Searches every category folder rather than trusting `item.category`,
    /// because the file may predate a category change.
    func delete(_ item: OrchestratorWorkItem) {
        lock.lock()
        defer { lock.unlock() }

        let fileName = "\(item.id.uuidString).md"
        guard let files = try? allMarkdownFiles() else { return }
        for file in files where file.lastPathComponent == fileName {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func saveConversation(_ snapshot: OrchestratorConversationSnapshot) {
        lock.lock()
        defer { lock.unlock() }

        let directory = conversationsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(conversationFileName(for: snapshot.key)).md")
        if snapshot.hasContent {
            try? formatConversation(snapshot).write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteConversation(key: String) {
        lock.lock()
        defer { lock.unlock() }

        let url = conversationsDirectory()
            .appendingPathComponent("\(conversationFileName(for: key)).md")
        try? FileManager.default.removeItem(at: url)
    }

    private func allMarkdownFiles() throws -> [URL] {
        let contents = try FileManager.default.subpathsOfDirectory(atPath: rootURL.path)
        return contents
            .map { rootURL.appendingPathComponent($0) }
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "conversation.md" }
            .filter { !$0.path.contains("/conversations/") }
    }

    private func format(_ item: OrchestratorWorkItem) -> String {
        var output = "---\n"
        output += "id: \(item.id.uuidString)\n"
        output += "title: \(frontMatter(item.title))\n"
        output += "category: \(item.category.rawValue)\n"
        output += "status: \(item.status.rawValue)\n"
        output += "priority: \(item.priority.rawValue)\n"
        output += "project: \(frontMatter(item.projectID ?? ""))\n"
        output += "attachments: \(item.attachmentIDs.map(\.uuidString).joined(separator: ","))\n"
        output += "sessions: \(item.linkedSessionIDs.joined(separator: ","))\n"
        output += "created: \(Self.formatDate(item.createdAt))\n"
        output += "updated: \(Self.formatDate(item.updatedAt))\n"
        output += "---\n\n"
        output += "# \(item.title)\n\n"
        output += "## Summary\n\(item.summary)\n\n"
        output += "## Original Capture\n\(item.rawCapture)\n"
        return output
    }

    private func parseWorkItem(at url: URL) -> OrchestratorWorkItem? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              content.hasPrefix("---\n") else { return nil }

        let sections = content.components(separatedBy: "\n---\n")
        guard sections.count >= 2 else { return nil }

        var values: [String: String] = [:]
        for line in sections[0].split(separator: "\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }

        guard let id = UUID(uuidString: values["id"] ?? ""),
              let category = OrchestratorWorkCategory(rawValue: values["category"] ?? ""),
              let status = OrchestratorWorkStatus(rawValue: values["status"] ?? "") else { return nil }

        let body = sections[1]
        let title = value(after: "# ", in: body) ?? values["title"] ?? "Untitled"
        let summary = subsection("Summary", in: body) ?? ""
        let capture = subsection("Original Capture", in: body) ?? ""
        let attachments = csv(values["attachments"] ?? "").compactMap(UUID.init(uuidString:))
        let sessions = csv(values["sessions"] ?? "")
        let created = Self.parseDate(values["created"] ?? "") ?? Date()
        let updated = Self.parseDate(values["updated"] ?? "") ?? created
        let priority = OrchestratorPriority(rawValue: values["priority"] ?? "medium") ?? .medium
        let projectValue = values["project"] ?? ""
        let project = projectValue.isEmpty ? nil : projectValue

        return OrchestratorWorkItem(
            id: id,
            title: title,
            summary: summary,
            rawCapture: capture,
            category: category,
            status: status,
            priority: priority,
            projectID: project,
            attachmentIDs: attachments,
            linkedSessionIDs: sessions,
            createdAt: created,
            updatedAt: updated
        )
    }

    private func conversationsDirectory() -> URL {
        rootURL.appendingPathComponent("conversations", isDirectory: true)
    }

    private func formatConversation(_ snapshot: OrchestratorConversationSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(snapshot)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"

        var output = "---\n"
        output += "key: \(snapshot.key)\n"
        output += "category: \(snapshot.category?.rawValue ?? "all")\n"
        output += "created: \(Self.formatDate(snapshot.createdAt))\n"
        output += "updated: \(Self.formatDate(snapshot.updatedAt))\n"
        output += "keep-long-term: \(snapshot.keepLongTerm ? "true" : "false")\n"
        output += "expires: \(snapshot.expiresAt.map(Self.formatDate) ?? "never")\n"
        output += "---\n\n"
        output += "# Orchestrator Chat: \(snapshot.category?.title ?? "ALL")\n\n"
        output += "```json\n\(json)\n```\n"
        return output
    }

    private func parseConversation(at url: URL) -> OrchestratorConversationSnapshot? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              let blockStart = content.range(of: "```json\n") else { return nil }
        let remainder = content[blockStart.upperBound...]
        guard let blockEnd = remainder.range(of: "\n```") else { return nil }
        let json = String(remainder[..<blockEnd.lowerBound])
        guard let data = json.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OrchestratorConversationSnapshot.self, from: data)
    }

    private func conversationFileName(for key: String) -> String {
        key.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private func subsection(_ heading: String, in body: String) -> String? {
        guard let start = body.range(of: "## \(heading)\n") else { return nil }
        let remainder = body[start.upperBound...]
        let end = remainder.range(of: "\n## ")?.lowerBound ?? remainder.endIndex
        return String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func value(after prefix: String, in body: String) -> String? {
        guard let line = body.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private func csv(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func frontMatter(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
