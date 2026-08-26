import Foundation

/// Finds the projects on disk.
///
/// This used to insist on evidence: a `.git`, or a build manifest a toolchain
/// would recognise. The reasoning was that `~/Documents` is full of screenshots
/// folders and tax paperwork, and none of that is something you would launch an
/// agent into.
///
/// That reasoning does not survive contact with this particular Documents
/// folder, which contains nothing but code. Plenty of it is local-only work
/// that was never a repo and has no manifest, and the rule quietly deleted
/// those from the app — permanently, since no amount of restarting makes a
/// filter let something through.
///
/// It got worse once the rail became a file browser you can create folders in:
/// a browser that cannot show you the folder you just made is not a browser.
/// So every directory counts now, and the only things dropped are the ones
/// nobody means — `ignoredNames` and dotfolders.
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

    /// Every directory in `root`, each carrying its own immediate
    /// subdirectories — so an agent can work either at a project root or inside
    /// one focused subdirectory, and the file tree has something to open.
    ///
    /// `daddy` is pinned first so the app always lands there. Everything else
    /// is most recently modified. Children are alphabetical, like Finder.
    /// `WorkspaceRail` folds the list to its first few; the ordering here is
    /// what decides which few those are.
    public static func scan(
        root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents"),
        limit: Int = 60
    ) -> [Found] {
        let found = childDirectories(of: root).map { directory in
            describe(
                directory,
                children: childDirectories(of: directory)
                    .map { describe($0) }
                    .sorted(by: alphabetical)
            )
        }

        return Array(
            found
                .sorted(by: roots)
                .prefix(limit)
        )
    }

    /// A project, or nil if the directory does not look like one.
    ///
    /// No longer what `scan` filters on — it takes everything now — but still
    /// the answer to "is there actually code in here", which is a different
    /// question and one worth being able to ask.
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

    /// Home project first, then recency. The name match is case-insensitive
    /// because the folder on disk is `daddy` and the app is Daddy.
    private static func roots(_ lhs: Found, _ rhs: Found) -> Bool {
        let lHome = isHomeProject(lhs.name)
        let rHome = isHomeProject(rhs.name)
        if lHome != rHome { return lHome }
        let l = modifiedAt(lhs.url) ?? .distantPast
        let r = modifiedAt(rhs.url) ?? .distantPast
        if l != r { return l > r }
        return alphabetical(lhs, rhs)
    }

    private static func isHomeProject(_ name: String) -> Bool {
        name.caseInsensitiveCompare("daddy") == .orderedSame
    }

    private static func modifiedAt(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }
}
