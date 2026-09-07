import Foundation

/// Stores orchestrator state as readable Markdown rather than introducing a
/// second private database. Work items are deliberately easy for a coding agent
/// to inspect during a dispatch.
///
/// One Markdown file per project+category bucket, not per item — every item
/// in `daddy/uiux`, say, lives in one `uiux.md`, each block separated by
/// `itemDivider`. A dispatched agent (or you, in any editor) finds its item
/// by the `id:` in its front matter, not by filename.
final class OrchestratorMarkdownStore: @unchecked Sendable {
    private let rootURL: URL
    private let lock = NSLock()

    /// An HTML comment: invisible in any Markdown viewer, and distinct from
    /// the `---` front-matter fences so splitting never gets confused by them.
    static let itemDivider = "\n\n<!-- item -->\n\n"

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            self.rootURL = desktop.appendingPathComponent("DaddyWork/Orchestrator", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        migrateLegacyFlatCategoryFoldersIfNeeded()
        migrateItemFilesIntoCategoryFilesIfNeeded()
    }

    func loadWorkItems() -> [OrchestratorWorkItem] {
        lock.lock()
        defer { lock.unlock() }

        guard let files = try? allMarkdownFiles() else { return [] }
        return files.flatMap { readItems(at: $0) }
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

    /// Writes the item into its target bucket file, first removing any copy
    /// of it from wherever it currently lives (it may have been in a
    /// different project/category before this save). Returns every bucket
    /// file touched — the vacated one, if different, plus the target — so a
    /// caller mirroring this to Drive knows exactly what changed.
    @discardableResult
    func save(_ item: OrchestratorWorkItem) -> Set<CategoryBucket> {
        lock.lock()
        defer { lock.unlock() }

        var touched: Set<CategoryBucket> = []

        if let files = try? allMarkdownFiles() {
            for file in files {
                var items = readItems(at: file)
                guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
                items.remove(at: index)
                writeItems(items, to: file)
                touched.insert(bucket(for: file))
            }
        }

        let targetBucket = CategoryBucket(
            projectFolderName: projectFolderName(for: item.projectID),
            categoryFolderName: item.category.folderName
        )
        var targetItems = readItems(at: url(for: targetBucket))
        targetItems.removeAll { $0.id == item.id }
        targetItems.append(item)
        writeItems(targetItems, to: url(for: targetBucket))
        touched.insert(targetBucket)

        return touched
    }

    func fileURL(for item: OrchestratorWorkItem) -> URL {
        url(for: CategoryBucket(
            projectFolderName: projectFolderName(for: item.projectID),
            categoryFolderName: item.category.folderName
        ))
    }

    /// Removes a work item's block from whichever bucket file holds it.
    /// Returns that bucket (nil if the item wasn't found anywhere), so a
    /// caller mirroring this to Drive knows what to re-push.
    @discardableResult
    func delete(_ item: OrchestratorWorkItem) -> CategoryBucket? {
        lock.lock()
        defer { lock.unlock() }

        guard let files = try? allMarkdownFiles() else { return nil }
        for file in files {
            var items = readItems(at: file)
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
            items.remove(at: index)
            writeItems(items, to: file)
            return bucket(for: file)
        }
        return nil
    }

    /// The bucket file's current raw content, for `WorkItemSyncCoordinator`
    /// to push straight to Drive — nil when the bucket is empty/nonexistent,
    /// which the caller treats as "delete the Drive file too."
    func categoryFileContent(for bucket: CategoryBucket) -> String? {
        lock.lock()
        defer { lock.unlock() }

        return try? String(contentsOf: url(for: bucket), encoding: .utf8)
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

    /// Exposed for `WorkItemSyncCoordinator`, which mirrors this exact
    /// folder-naming rule for Drive's project folders.
    func projectFolderName(for projectID: String?) -> String {
        guard let projectID, !projectID.isEmpty else { return "Unassigned" }
        return (projectID as NSString).lastPathComponent
    }

    private func url(for bucket: CategoryBucket) -> URL {
        rootURL
            .appendingPathComponent(bucket.projectFolderName, isDirectory: true)
            .appendingPathComponent("\(bucket.categoryFolderName).md")
    }

    /// A bucket file's identity from its own path — the inverse of `url(for:)`.
    private func bucket(for fileURL: URL) -> CategoryBucket {
        CategoryBucket(
            projectFolderName: fileURL.deletingLastPathComponent().lastPathComponent,
            categoryFolderName: fileURL.deletingPathExtension().lastPathComponent
        )
    }

    private func readItems(at url: URL) -> [OrchestratorWorkItem] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Self.parseItems(content: content)
    }

    /// Deletes the file when `items` is empty, so an emptied bucket doesn't
    /// leave a stray file behind.
    private func writeItems(_ items: [OrchestratorWorkItem], to url: URL) {
        guard !items.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = items.map(format).joined(separator: Self.itemDivider)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// One-time move of items written before Kanban storage was nested by
    /// project: a `.md` file sitting directly under `<rootURL>/<category>/`
    /// predates project folders and gets relocated under
    /// `<rootURL>/<project>/<category>/` based on its own front matter.
    /// Gated by a marker file so this never runs (or costs anything) again.
    private func migrateLegacyFlatCategoryFoldersIfNeeded() {
        let markerURL = rootURL.appendingPathComponent(".project-nesting-migrated")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }

        let categoryFolderNames = Set(OrchestratorWorkCategory.allCases.map(\.folderName))
        let fm = FileManager.default

        for categoryName in categoryFolderNames {
            let legacyDir = rootURL.appendingPathComponent(categoryName, isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil) else { continue }

            for file in files where file.pathExtension == "md" {
                guard fm.fileExists(atPath: file.path), let item = parseWorkItem(at: file) else { continue }
                let destDir = rootURL
                    .appendingPathComponent(projectFolderName(for: item.projectID), isDirectory: true)
                    .appendingPathComponent(categoryName, isDirectory: true)
                try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                let destURL = destDir.appendingPathComponent(file.lastPathComponent)
                guard !fm.fileExists(atPath: destURL.path) else { continue }
                try? fm.moveItem(at: file, to: destURL)
            }
        }
        try? "".write(to: markerURL, atomically: true, encoding: .utf8)
    }

    /// One-time consolidation of the old one-file-per-item layout
    /// (`<project>/<category>/<uuid>.md`) into one file per bucket
    /// (`<project>/<category>.md`). Runs after the migration above, so items
    /// are already project-nested by the time this looks for them. Gated by
    /// its own marker so it only ever runs once.
    private func migrateItemFilesIntoCategoryFilesIfNeeded() {
        let markerURL = rootURL.appendingPathComponent(".category-files-merged")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }

        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            try? "".write(to: markerURL, atomically: true, encoding: .utf8)
            return
        }

        for projectDir in projectDirs {
            guard projectDir.lastPathComponent != "conversations",
                  (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            for category in OrchestratorWorkCategory.allCases {
                let categoryDir = projectDir.appendingPathComponent(category.folderName, isDirectory: true)
                guard let files = try? fm.contentsOfDirectory(at: categoryDir, includingPropertiesForKeys: nil) else { continue }

                let items = files
                    .filter { $0.pathExtension == "md" }
                    .compactMap { parseWorkItem(at: $0) }
                guard !items.isEmpty else { continue }

                let mergedURL = projectDir.appendingPathComponent("\(category.folderName).md")
                var merged = readItems(at: mergedURL)
                for item in items where !merged.contains(where: { $0.id == item.id }) {
                    merged.append(item)
                }
                writeItems(merged, to: mergedURL)
                try? fm.removeItem(at: categoryDir)
            }
        }
        try? "".write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private func allMarkdownFiles() throws -> [URL] {
        let contents = try FileManager.default.subpathsOfDirectory(atPath: rootURL.path)
        return contents
            .map { rootURL.appendingPathComponent($0) }
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "conversation.md" }
            .filter { !$0.path.contains("/conversations/") }
    }

    /// Exposed for `WorkItemSyncCoordinator`, which uploads/downloads the
    /// same Markdown representation to/from Drive rather than inventing a
    /// second format.
    func format(_ item: OrchestratorWorkItem) -> String {
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
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Self.parseWorkItem(content: content)
    }

    /// Exposed for `WorkItemSyncCoordinator`, which parses a whole bucket
    /// file's content downloaded from Drive rather than read from disk.
    static func parseItems(content: String) -> [OrchestratorWorkItem] {
        content.components(separatedBy: itemDivider).compactMap(parseWorkItem(content:))
    }

    /// Exposed for `WorkItemSyncCoordinator`. Parses one item's block —
    /// `parseItems(content:)` is `readItems`'s (and Drive's) actual entry
    /// point; this is the single-block primitive both build on.
    static func parseWorkItem(content: String) -> OrchestratorWorkItem? {
        guard content.hasPrefix("---\n") else { return nil }

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

    private static func subsection(_ heading: String, in body: String) -> String? {
        guard let start = body.range(of: "## \(heading)\n") else { return nil }
        let remainder = body[start.upperBound...]
        let end = remainder.range(of: "\n## ")?.lowerBound ?? remainder.endIndex
        return String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func value(after prefix: String, in body: String) -> String? {
        guard let line = body.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func csv(_ value: String) -> [String] {
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
