import XCTest
@testable import DaddyCore
import Foundation

final class ExecutableResolverTests: XCTestCase {

    func testResolvesBareNameOnPath() {
        // /bin/sh exists on every macOS install.
        let resolved = ExecutableResolver.resolve("sh")
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.hasSuffix("/sh") == true, "Got: \(resolved ?? "nil")")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: resolved!))
    }

    func testAbsolutePathPassesThrough() {
        XCTAssertEqual(ExecutableResolver.resolve("/bin/sh"), "/bin/sh")
    }

    func testAbsolutePathToNonExecutableIsRejected() {
        // A real file that is not executable.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertNil(ExecutableResolver.resolve(file.path))
    }

    func testMissingExecutableReturnsNil() {
        XCTAssertNil(ExecutableResolver.resolve("definitely-not-a-real-binary-\(UUID().uuidString)"))
    }

    func testFindsToolsOutsideTheMinimalGUIPath() throws {
        // The whole reason this type exists: a GUI app's inherited PATH is
        // roughly /usr/bin:/bin:/usr/sbin:/sbin, which does not contain
        // ~/.local/bin where the agent CLIs live. If claude is installed at
        // all, we must find it.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let claudeInLocalBin = "\(home)/.local/bin/claude"
        try XCTSkipIf(
            !FileManager.default.isExecutableFile(atPath: claudeInLocalBin),
            "claude not installed in ~/.local/bin"
        )

        XCTAssertNotNil(ExecutableResolver.resolve("claude"))
    }

    /// Resolution must never block indefinitely: it runs on whatever thread
    /// first launches an agent, and in the app that is the main thread.
    func testResolutionCompletesPromptly() {
        let start = Date()
        _ = ExecutableResolver.resolve("sh")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 10, "Login-shell PATH probe did not respect its deadline")
    }
}

final class UTF8ChunkDecodingTests: XCTestCase {

    func testDecodesPlainASCII() {
        var bytes = Array("hello".utf8)
        XCTAssertEqual(PTYProcess.consumeValidUTF8(&bytes), "hello")
        XCTAssertTrue(bytes.isEmpty)
    }

    func testHoldsBackSplitMultiByteSequence() {
        // "é" is 0xC3 0xA9. Deliver only the first byte.
        var bytes: [UInt8] = Array("caf".utf8) + [0xC3]

        let first = PTYProcess.consumeValidUTF8(&bytes)
        XCTAssertEqual(first, "caf", "Incomplete code point must not be emitted")
        XCTAssertEqual(bytes, [0xC3], "Partial sequence must be retained")

        // Now the continuation byte arrives.
        bytes.append(0xA9)
        let second = PTYProcess.consumeValidUTF8(&bytes)
        XCTAssertEqual(second, "é")
        XCTAssertTrue(bytes.isEmpty)
    }

    func testReassemblesFourByteEmojiAcrossThreeChunks() {
        // "🚀" is F0 9F 9A 80 — the worst case for a naive decoder.
        let emoji = Array("🚀".utf8)
        var bytes: [UInt8] = []
        var assembled = ""

        for chunk in [emoji[0..<1], emoji[1..<3], emoji[3..<4]] {
            bytes.append(contentsOf: chunk)
            assembled += PTYProcess.consumeValidUTF8(&bytes)
        }

        XCTAssertEqual(assembled, "🚀")
        XCTAssertTrue(bytes.isEmpty)
    }

    func testFlushesRatherThanStallingOnInvalidBytes() {
        // Genuinely invalid bytes must not wedge the decoder forever.
        var bytes: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC, 0xFB]
        let decoded = PTYProcess.consumeValidUTF8(&bytes)
        XCTAssertFalse(decoded.isEmpty, "Decoder stalled on invalid input")
        XCTAssertLessThanOrEqual(bytes.count, 3)
    }

    func testEmptyInput() {
        var bytes: [UInt8] = []
        XCTAssertEqual(PTYProcess.consumeValidUTF8(&bytes), "")
    }
}

final class TerminalInputTests: XCTestCase {

    func testControlByteIsSentRaw() {
        XCTAssertEqual(TerminalInput.interrupt.bytes, [0x03])
        XCTAssertEqual(TerminalInput.endOfFile.bytes, [0x04])
    }

    func testInterruptIsNotTheStringForm() {
        // The bug this type prevents: "\u{03}" as text is not Ctrl-C.
        XCTAssertEqual(TerminalInput.interrupt.bytes, [0x03])
        XCTAssertEqual(TerminalInput.text("\u{03}").bytes, [0x03])
        // Same here, but Enter is where the two genuinely diverge:
        XCTAssertEqual(TerminalInput.key(.enter).bytes, Array("\r".utf8))
        XCTAssertNotEqual(TerminalInput.key(.enter).bytes, Array("\n".utf8))
    }

    func testArrowKeysUseXtermSequences() {
        XCTAssertEqual(TerminalInput.key(.up).bytes, Array("\u{1B}[A".utf8))
        XCTAssertEqual(TerminalInput.key(.down).bytes, Array("\u{1B}[B".utf8))
        XCTAssertEqual(TerminalInput.key(.right).bytes, Array("\u{1B}[C".utf8))
        XCTAssertEqual(TerminalInput.key(.left).bytes, Array("\u{1B}[D".utf8))
    }

    func testEveryKeyEncodesToSomething() {
        for key in TerminalInput.Key.allCases {
            XCTAssertFalse(
                TerminalInput.key(key).bytes.isEmpty,
                "\(key) encodes to nothing"
            )
        }
    }

    func testTextIsUTF8() {
        XCTAssertEqual(TerminalInput.text("héllo 🚀").bytes, Array("héllo 🚀".utf8))
    }
}
