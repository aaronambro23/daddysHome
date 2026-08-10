import XCTest
@testable import DaddyCore

final class CommandParserTests: XCTestCase {

    let parser = CommandParser()

    func testBasicWorkCommand() {
        let result = parser.parse("Claude, continue")
        XCTAssertEqual(result.agent, .claude)
        XCTAssertEqual(result.intent, .work)
    }

    func testWorkCommandWithModel() {
        let result = parser.parse("Claude Opus, keep going")
        XCTAssertEqual(result.agent, .claude)
        XCTAssertEqual(result.model, "opus")
        XCTAssertEqual(result.intent, .work)
    }

    func testStopCommand() {
        let result = parser.parse("Codex, stop")
        XCTAssertEqual(result.agent, .codex)
        XCTAssertEqual(result.intent, .stop)
    }

    func testReviewCommand() {
        let result = parser.parse("Cursor, review this")
        XCTAssertEqual(result.agent, .cursor)
        XCTAssertEqual(result.intent, .review)
    }

    func testHandoffCommand() {
        let result = parser.parse("Hand this to Codex")
        XCTAssertEqual(result.intent, .handoff)
        XCTAssertEqual(result.targetAgent, .codex)
    }

    func testStatusCommand() {
        let result = parser.parse("What's going on")
        XCTAssertEqual(result.intent, .status)
    }

    func testRunTestsCommand() {
        let result = parser.parse("OpenCode, run tests")
        XCTAssertEqual(result.agent, .opencode)
        XCTAssertEqual(result.intent, .runTests)
    }

    func testSpanishCommands() {
        let dalCommand = parser.parse("Claude, dale")
        XCTAssertEqual(dalCommand.intent, .work)

        let frenaCommand = parser.parse("Codex, frena")
        XCTAssertEqual(frenaCommand.intent, .stop)

        let revisaCommand = parser.parse("Cursor, revisá esto")
        XCTAssertEqual(revisaCommand.intent, .review)
    }

    func testMixedLanguageCommand() {
        let result = parser.parse("Claude, fijate qué onda con este error")
        XCTAssertEqual(result.agent, .claude)
        // "qué onda" is in dictionary for status, but this test verifies mixed lang parsing
        XCTAssert(!result.prompt!.isEmpty)
    }

    func testPromptExtraction() {
        let result = parser.parse("Claude, fix the login bug")
        XCTAssertEqual(result.agent, .claude)
        XCTAssertEqual(result.intent, .work)
        XCTAssert(result.prompt?.contains("fix") ?? false)
    }

    func testAgentOnlyCommand() {
        let result = parser.parse("Continue Codex")
        XCTAssertEqual(result.agent, .codex)
    }

    func testNoAgentCommand() {
        let result = parser.parse("What's left?")
        XCTAssertNil(result.agent)
        XCTAssertEqual(result.intent, .status)
    }

    func testMultipleModels() {
        let result = parser.parse("Claude sonnet, continue")
        XCTAssertEqual(result.agent, .claude)
        XCTAssertEqual(result.model, "sonnet")
    }

    func testUnknownIntent() {
        let result = parser.parse("Claude, do something weird")
        XCTAssertEqual(result.agent, .claude)
        if case .unknown = result.intent {
            XCTAssert(true)
        } else {
            XCTFail("Expected unknown intent")
        }
    }
}
