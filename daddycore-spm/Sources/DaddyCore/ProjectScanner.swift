import Foundation

/// Finds real projects on disk.
///
/// `WorkflowStateManager.discoverProjects()` calls every subdirectory of
/// `~/Documents` a project — screenshots folders, tax paperwork, anything. That
/// list is not something you would ever launch an agent into, which is part of
/// why the app kept its own hardcoded list instead.
///
/// A project here is a directory that looks like code: it has a `.git`, or a
/// build manifest a toolchain would recognise.
public enum ProjectScanner {

    /// Files that mean "someone builds something here".
    public static let manifests: Set<String> = [
        "Package.swift", "package.json", "Cargo.toml", "pyproject.toml",
        "requirements.txt", "go.mod", "Gemfile", "pom.xml", "build.gradle",
        "build.gradle.kts", "CMakeLists.txt", "Makefile", "composer.json",
        "pubspec.yaml", "mix.exs", "deno.json", "*.xcodeproj",
    ]

    public struct Found: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let url: URL
        /// True when the directory is a git repository.
        public let isRepository: Bool

        public var path: String { url.path }
    }

    /// Scans `root` for project directories, one level down, then one level
    /// further for anything that looks like a container of repos (`~/Documents/
    /// code/…`). Results are sorted by most recently modified, so what you were
    /// last working on is at the top.
    public static func scan(
        root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents"),
        limit: Int = 60
    ) -> [Found] {
        var found: [Found] = []
        var seen = Set<String>()

        for directory in childDirectories(of: root) {
            if let project = classify(directory) {
                if seen.insert(project.url.path).inserted { found.append(project) }
                continue
            }

            // Not a project itself — it may be a folder of them.
            for nested in childDirectories(of: directory) {
                if let project = classify(nested),
                   seen.insert(project.url.path).inserted {
                    found.append(project)
                }
            }
        }

        return Array(
            found
                .sorted { lhs, rhs in
                    let l = modifiedAt(lhs.url) ?? .distantPast
                    let r = modifiedAt(rhs.url) ?? .distantPast
                    if l != r { return l > r }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                .prefix(limit)
        )
    }

    /// A project, or nil if the directory does not look like one.
    public static func classify(_ url: URL) -> Found? {
        let fileManager = FileManager.default
        let name = url.lastPathComponent

        // Skip dotfolders and the usual noise.
        guard !name.hasPrefix("."), !ignoredNames.contains(name) else { return nil }

        let isRepository = fileManager.fileExists(
            atPath: url.appendingPathComponent(".git").path
        )

        guard isRepository || hasManifest(url) else { return nil }

        return Found(
            id: url.path,
            name: name,
            url: url,
            isRepository: isRepository
        )
    }

    private static let ignoredNames: Set<String> = [
        "node_modules", "Library", "Applications", ".build", "DerivedData",
        "Pods", "vendor", "target", "dist", "build",
    ]

    private static func hasManifest(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }

        for entry in entries {
            if manifests.contains(entry) { return true }
            if entry.hasSuffix(".xcodeproj") { return true }
        }
        return false
    }

    private static func childDirectories(of url: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return entries.filter { $0.hasDirectoryPath }
    }

    private static func modifiedAt(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }
}
