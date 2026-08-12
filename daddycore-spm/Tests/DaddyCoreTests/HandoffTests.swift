import XCTest
@testable import DaddyCore
import Foundation

final class HandoffParserTests: XCTestCase {

    private func doc(_ markdown: String, filename: String = "003-auth-refactor.md") -> HandoffDoc {
        let (number, slug) = HandoffParser.parseFilename(filename)!
        return HandoffParser.parse(
            text: markdown,
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            projectID: "p",
            number: number,
            slug: slug,
            modifiedAt: Date()
        )
    }

    // MARK: Filenames

    func testParsesNumberAndSlug() {
        let parsed = HandoffParser.parseFilename("003-auth-refactor.md")
        XCTAssertEqual(parsed?.number, 3)
        XCTAssertEqual(parsed?.slug, "auth-refactor")
    }

    func testOrderingIsNumericNotLexicographic() {
        // The reason for zero-padding: "10" must sort after "9".
        let names = ["010-tenth.md", "002-second.md", "009-ninth.md"]
        let numbers = names.compactMap { HandoffParser.parseFilename($0)?.number }.sorted()
        XCTAssertEqual(numbers, [2, 9, 10])
    }

    func testRejectsUnnumberedFiles() {
        XCTAssertNil(HandoffParser.parseFilename("README.md"))
        XCTAssertNil(HandoffParser.parseFilename("notes.md"))
    }

    // MARK: Checkboxes

    func testCountsCheckboxes() {
        let d = doc("""
        # 003 — Auth refactor

        - **Status:** in-progress
        - **Agent:** claude

        ## Tasks

        - [x] Move token exchange
        - [x] Drop keychain shim
        - [ ] Update tests
        """)

        XCTAssertEqual(d.totalCount, 3)
        XCTAssertEqual(d.completedCount, 2)
        XCTAssertEqual(d.status, .inProgress)
        XCTAssertEqual(d.outstandingTasks.map(\.title), ["Update tests"])
        XCTAssertEqual(d.agent, .claude)
        XCTAssertEqual(d.title, "Auth refactor")
    }

    func testUppercaseXCounts() {
        let d = doc("""
        # 003 — T
        ## Tasks
        - [X] Done with capital X
        """)
        XCTAssertEqual(d.completedCount, 1)
    }

    /// A doc where nothing is ticked yet is a plan, not work in progress.
    func testUntickedIsPlanned() {
        let d = doc("""
        # 003 — T
        ## Tasks
        - [ ] One
        - [ ] Two
        """)
        XCTAssertEqual(d.status, .planned)
        XCTAssertEqual(d.progress, 0)
    }

    /// The case that matters most: everything ticked but never marked done.
    /// Daddy should flag this rather than quietly call it complete.
    func testAllTickedButNotMarkedDoneIsStalled() {
        let d = doc("""
        # 003 — T
        - **Status:** in-progress
        ## Tasks
        - [x] One
        - [x] Two
        """)
        XCTAssertEqual(d.status, .stalled)
    }

    func testExplicitDoneWins() {
        let d = doc("""
        # 003 — T
        - **Status:** done
        ## Tasks
        - [x] One
        - [ ] Two
        """)
        XCTAssertEqual(d.status, .done)
    }

    // MARK: Sections

    func testExtractsSummaryAndNextSteps() {
        let d = doc("""
        # 003 — Auth refactor

        ## Goal

        Move token exchange into DaddyCore.

        ## Tasks

        - [x] Done

        ## Summary

        Replaced the keychain shim with a direct exchange.

        ## Changes

        Deleted KeychainShim.swift.

        ## Next possible steps

        Add refresh-token rotation next; the exchange is stateless today.
        """)

        XCTAssertEqual(d.goal, "Move token exchange into DaddyCore.")
        XCTAssertEqual(d.summary, "Replaced the keychain shim with a direct exchange.")
        XCTAssertEqual(d.changes, "Deleted KeychainShim.swift.")
        XCTAssertTrue(d.nextSteps?.contains("refresh-token rotation") == true)
    }

    /// The template ships italic placeholders. They must not be mistaken for
    /// real content, or every fresh doc would look already filled in.
    func testPlaceholdersAreNotTreatedAsContent() {
        let d = doc("""
        # 003 — T

        ## Summary

        _Filled in when the batch is complete._

        ## Next possible steps

        _Filled in when the batch is complete._
        """)

        XCTAssertNil(d.summary)
        XCTAssertNil(d.nextSteps)
    }

    func testAcceptsNextStepsHeadingVariant() {
        let d = doc("""
        # 003 — T
        ## Next steps
        Do the thing.
        """)
        XCTAssertEqual(d.nextSteps, "Do the thing.")
    }

    func testTitleFallsBackToSlug() {
        let d = doc("no heading here", filename: "007-rate-limit-backoff.md")
        XCTAssertEqual(d.title, "rate limit backoff")
    }
}

final class HandoffStoreTests: XCTestCase {

    private func makeProject(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let handoffs = root.appendingPathComponent(WorkflowContract.handoffDirectory)
        try FileManager.default.createDirectory(at: handoffs, withIntermediateDirectories: true)

        for (name, body) in files {
            try body.write(
                to: handoffs.appendingPathComponent(name),
                atomically: true, encoding: .utf8
            )
        }
        return root
    }

    func testReadsDocumentsInNumericOrder() throws {
        let root = try makeProject([
            "010-tenth.md": "# 010 — Tenth\n## Tasks\n- [ ] a",
            "002-second.md": "# 002 — Second\n## Tasks\n- [x] a",
            "009-ninth.md": "# 009 — Ninth\n## Tasks\n- [ ] a",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let docs = HandoffStore().documents(in: root, projectID: "p")
        XCTAssertEqual(docs.map(\.number), [2, 9, 10])
    }

    func testNextNumberSkipsPastHighest() throws {
        let root = try makeProject([
            "001-a.md": "# 001 — A",
            "004-b.md": "# 004 — B",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(HandoffStore().nextNumber(in: root, projectID: "p"), 5)
    }

    func testNextNumberIsOneForEmptyProject() throws {
        let root = try makeProject([:])
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(HandoffStore().nextNumber(in: root, projectID: "p"), 1)
    }

    func testNonMarkdownFilesIgnored() throws {
        let root = try makeProject([
            "001-a.md": "# 001 — A",
            "notes.txt": "ignore me",
            "README.md": "unnumbered, ignore me",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(HandoffStore().documents(in: root, projectID: "p").count, 1)
    }

    /// The core PM question: where does a new agent pick up?
    func testOverviewResumesAtFirstUnfinishedDoc() throws {
        let root = try makeProject([
            "001-a.md": "# 001 — A\n- **Status:** done\n## Tasks\n- [x] a",
            "002-b.md": "# 002 — B\n## Tasks\n- [x] a\n- [ ] b",
            "003-c.md": "# 003 — C\n## Tasks\n- [ ] a",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let store = HandoffStore()
        let docs = store.documents(in: root, projectID: "p")
        let overview = store.overview(of: docs)

        XCTAssertEqual(overview.total, 3)
        XCTAssertEqual(overview.done, 1)
        XCTAssertEqual(overview.resumeAt?.number, 2)
        XCTAssertEqual(overview.outstandingTasks, 2)
    }

    func testMissingHandoffDirectoryIsEmptyNotACrash() {
        let nowhere = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID().uuidString)")
        XCTAssertTrue(HandoffStore().documents(in: nowhere, projectID: "p").isEmpty)
        XCTAssertEqual(HandoffStore().nextNumber(in: nowhere, projectID: "p"), 1)
    }
}

final class ContractInstallerTests: XCTestCase {

    func testInstallsBothFilesAndHandoffDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = ContractInstaller()
        let result = try installer.install(into: root, projectName: "korean-makeup")

        let agents = try String(contentsOf: result.agentsPath, encoding: .utf8)
        XCTAssertTrue(agents.contains("korean-makeup"))
        XCTAssertTrue(agents.contains(WorkflowContract.handoffDirectory))

        // Claude picks the contract up through the import, so there is one
        // source of truth rather than two files to keep in sync.
        let claude = try String(contentsOf: result.claudePath, encoding: .utf8)
        XCTAssertEqual(claude.trimmingCharacters(in: .whitespacesAndNewlines), "@AGENTS.md")

        XCTAssertTrue(result.createdHandoffDirectory)
        XCTAssertTrue(installer.isInstalled(in: root))
    }

    /// Overwriting is intended, but existing files can hold real project
    /// knowledge, so nothing is destroyed.
    func testExistingFilesAreBackedUpBeforeOverwrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = "# This is NOT the Next.js you know\nreal project knowledge"
        try original.write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true, encoding: .utf8
        )

        let result = try ContractInstaller().install(into: root)

        XCTAssertEqual(result.backedUp.count, 1)
        let backup = try String(contentsOf: result.backedUp[0], encoding: .utf8)
        XCTAssertEqual(backup, original)

        let installed = try String(contentsOf: result.agentsPath, encoding: .utf8)
        XCTAssertTrue(installed.contains("Working agreement"))
    }

    func testRepeatedInstallDoesNotClobberEarlierBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "original".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true, encoding: .utf8
        )

        _ = try ContractInstaller().install(into: root)
        let second = try ContractInstaller().install(into: root)

        // First backup holds the user's file; the second must land elsewhere.
        let first = try String(
            contentsOf: root.appendingPathComponent("AGENTS.md.bak"), encoding: .utf8
        )
        XCTAssertEqual(first, "original")
        XCTAssertFalse(second.backedUp.isEmpty)
    }

    func testRejectsNonDirectory() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertThrowsError(try ContractInstaller().install(into: file))
    }
}
