import XCTest
@testable import DaddyCore

/// The app used to carry six hardcoded project names because the real discovery
/// called every subdirectory of ~/Documents a project — including screenshots
/// folders and tax paperwork.
final class ProjectScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeDirectory(_ name: String, containing files: [String] = []) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files {
            try "".write(to: url.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        return url
    }

    func testAGitRepositoryIsAProject() throws {
        let repo = try makeDirectory("my-repo")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true
        )

        let found = ProjectScanner.scan(root: root)
        XCTAssertEqual(found.map(\.name), ["my-repo"])
        XCTAssertTrue(found[0].isRepository)
    }

    func testAManifestIsEnoughWithoutGit() throws {
        _ = try makeDirectory("swift-thing", containing: ["Package.swift"])
        _ = try makeDirectory("node-thing", containing: ["package.json"])

        let names = Set(ProjectScanner.scan(root: root).map(\.name))
        XCTAssertEqual(names, ["swift-thing", "node-thing"])
    }

    func testOrdinaryFoldersAreNotProjects() throws {
        _ = try makeDirectory("Screenshots", containing: ["shot.png"])
        _ = try makeDirectory("tax-2026", containing: ["return.pdf"])

        XCTAssertTrue(ProjectScanner.scan(root: root).isEmpty,
                      "every subdirectory used to count as a project")
    }

    func testFindsProjectsNestedOneLevelDeeper() throws {
        // ~/Documents/code/thing — a folder of repos, not a repo itself.
        let container = try makeDirectory("code")
        let nested = container.appendingPathComponent("thing")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "".write(to: nested.appendingPathComponent("Cargo.toml"),
                     atomically: true, encoding: .utf8)

        XCTAssertEqual(ProjectScanner.scan(root: root).map(\.name), ["thing"])
    }

    func testNoiseDirectoriesAreSkipped() throws {
        let modules = try makeDirectory("node_modules", containing: ["package.json"])
        _ = modules

        XCTAssertTrue(ProjectScanner.scan(root: root).isEmpty)
    }

    func testAProjectIsNotListedTwice() throws {
        // Both a repo and a manifest — one entry, not two.
        let repo = try makeDirectory("both", containing: ["Package.swift"])
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true
        )

        XCTAssertEqual(ProjectScanner.scan(root: root).count, 1)
    }
}
