import XCTest
@testable import DaddyCore

/// Regressions for the parser bugs that made voice unusable — and made the test
/// suite report a different number of failures on each run.
final class VoiceCommandTests: XCTestCase {

    let parser = CommandParser()

    // MARK: - Determinism

    func testTheSameSentenceAlwaysParsesTheSameWay() {
        // `extractIntent` used to iterate a Dictionary, whose order is not
        // stable between runs. "what's going on" matched both "what's" (status)
        // and "go" inside "going" (work), and the winner changed run to run.
        // Fresh parsers each time, because the ordering is built in `init`.
        let intents = (0..<200).map { _ in CommandParser().parse("what's going on").intent }

        XCTAssertEqual(Set(intents.map(String.init(describing:))).count, 1,
                       "parse result is not stable across instances")
        XCTAssertEqual(intents.first, .status)
    }

    func testMostSpecificPhraseWins() {
        // "hand off" must beat "hand"; "keep going" must beat "go".
        XCTAssertEqual(parser.parse("hand off to cursor").intent, .handoff)
        XCTAssertEqual(parser.parse("keep going").intent, .work)
        XCTAssertEqual(parser.parse("change model to opus").intent, .switchModel)
    }

    // MARK: - Word boundaries

    func testKeywordsDoNotMatchInsideOtherWords() {
        // "go" inside "going", "para" inside "parameter", "test" inside "latest".
        XCTAssertEqual(parser.parse("what's going on").intent, .status)

        if case .unknown = parser.parse("rename the parameter").intent {} else {
            XCTFail("\"para\" matched inside \"parameter\"")
        }
        if case .unknown = parser.parse("show me the latest").intent {} else {
            XCTFail("\"test\" matched inside \"latest\"")
        }
    }

    // MARK: - Agent naming

    func testAgentIsFoundAnywhereNotJustAtTheStart() {
        // `extractAgent` used to be `hasPrefix`, so this found nothing.
        XCTAssertEqual(parser.parse("continue codex").agent, .codex)
        XCTAssertEqual(parser.parse("ask cursor to review this").agent, .cursor)
        XCTAssertEqual(parser.parse("claude, stop").agent, .claude)
    }

    func testAgentNameIsNotMatchedInsideAWord() {
        XCTAssertNil(parser.parse("check the codexample file").agent)
    }

    func testHandoffPicksTheAgentBeingHandedTo() {
        let result = parser.parse("hand this to codex")
        XCTAssertEqual(result.intent, .handoff)
        XCTAssertEqual(result.targetAgent, .codex)
    }

    func testFirstAgentNamedIsTheSubject() {
        XCTAssertEqual(parser.parse("claude, hand off to cursor").agent, .claude)
    }

    // MARK: - Models

    func testFullModelNameIsNotReportedAsTheBareOne() {
        XCTAssertEqual(parser.parse("switch to claude-opus").model, "claude-opus")
        XCTAssertEqual(parser.parse("switch to opus").model, "opus")
    }

    func testModelIsRemovedFromThePrompt() {
        let result = parser.parse("claude sonnet, keep going")
        XCTAssertEqual(result.agent, .claude)
        XCTAssertEqual(result.model, "sonnet")
        XCTAssertFalse(result.prompt?.contains("sonnet") ?? false)
    }

    // MARK: - Prompts

    func testInstructionSurvivesAsThePrompt() {
        // The intent keyword stays in: "fix the login bug" is both the command
        // and the thing to say to the agent.
        let result = parser.parse("claude, fix the login bug")
        XCTAssertEqual(result.intent, .work)
        XCTAssertEqual(result.prompt, "fix the login bug")
    }

    func testAgentNameIsStrippedFromThePrompt() {
        XCTAssertEqual(parser.parse("claude, stop").prompt, "stop")
        XCTAssertNil(parser.parse("claude").prompt)
    }

    // MARK: - Spanish

    func testSpanishCommandsStillResolve() {
        XCTAssertEqual(parser.parse("dale").intent, .work)
        XCTAssertEqual(parser.parse("codex, frena").intent, .stop)
        XCTAssertEqual(parser.parse("cursor, revisá esto").intent, .review)
        XCTAssertEqual(parser.parse("qué onda").intent, .status)
    }

    func testMixedLanguageKeepsThePrompt() {
        let result = parser.parse("claude, fijate qué onda con este error")
        XCTAssertEqual(result.agent, .claude)
        XCTAssertFalse(result.prompt?.isEmpty ?? true)
    }
}
