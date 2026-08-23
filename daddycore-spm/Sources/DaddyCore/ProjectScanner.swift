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
        /// Immediate selectable directories. Discovery deliberately stops here.
        public let children: [Found]

        public var path: String { url.path }
    }

    /// Scans `root` for code projects and folders whose immediate children
    /// contain code projects. Every included root carries all of its immediate
    /// selectable directories, not just repositories, so an agent can work
    /// either at a client/project root or inside one focused subdirectory.
    ///
    /// Results are sorted by most recently modified, so what you were last
    /// working on is at the top. Children are alphabetical, like Finder.
    public static func scan(
        root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents"),
        limit: Int = 60
    ) -> [Found] {
        var found: [Found] = []

        for directory in childDirectories(of: root) {
            let children = childDirectories(of: directory)
            let rootIsProject = classify(directory) != nil
            let containsProjects = children.contains { classify($0) != nil }

            guard rootIsProject || containsProjects else { continue }

            found.append(describe(
                directory,
                children: children
                    .map { describe($0) }
                    .sorted(by: alphabetical)
            ))
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
            isRepository: isRepository,
            children: []
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

        return entries.filter {
            $0.hasDirectoryPath && !ignoredNames.contains($0.lastPathComponent)
        }
    }

    private static func describe(_ url: URL, children: [Found] = []) -> Found {
        Found(
            id: url.path,
            name: url.lastPathComponent,
            url: url,
            isRepository: FileManager.default.fileExists(
                atPath: url.appendingPathComponent(".git").path
            ),
            children: children
        )
    }

    private static func alphabetical(_ lhs: Found, _ rhs: Found) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func modifiedAt(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }
}
