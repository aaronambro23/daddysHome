import Foundation
import DaddyCore

// The missing link. `CommandParser` has existed and been unit-tested since
// milestone 5, and nothing ever called it: the voice view appended a log entry
// and stopped. This turns a parsed command into something that actually reaches
// a running agent.
//
// Deliberately not a speech recogniser. Dictation is HEX's job — it is already
// system-wide and already has the hotkey. Daddy reads the text that lands in its
// own composer while it is frontmost, which needs no microphone permission and
// no Full Disk Access. On this branch that costs nothing, because the terminal
// is in Daddy: you are already here.

struct VoiceOutcome {
    let summary: String
    let didSucceed: Bool

    static func ok(_ summary: String) -> VoiceOutcome {
        VoiceOutcome(summary: summary, didSucceed: true)
    }

    static func refused(_ summary: String) -> VoiceOutcome {
        VoiceOutcome(summary: summary, didSucceed: false)
    }
}

@MainActor
struct VoiceRouter {
    let store: MockStore

    private var parser: CommandParser { store.commandParser }

    func route(_ transcript: String) -> VoiceOutcome {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .refused("nothing heard") }

        let command = parser.parse(trimmed)

        guard let target = resolveTarget(command) else {
            return .refused(
                command.agent.map { "no live \($0.rawValue) session" }
                    ?? "no agent selected"
            )
        }

        switch command.intent {
        case .stop:
            store.stop(target.id)
            return .ok("stopped \(target.displayName)")

        case .interrupt:
            store.interrupt(target.id)
            return .ok("interrupted \(target.displayName)")

        case .work, .resume:
            // "Claude, fix the login bug" carries an instruction; "Claude,
            // continue" does not. One is a new prompt, the other is a nudge.
            if let prompt = command.prompt, isInstruction(prompt) {
                store.send(prompt, to: target.id)
                return .ok("sent to \(target.displayName): \(prompt)")
            }
            store.resume(target.id)
            return .ok("told \(target.displayName) to continue")

        case .review:
            store.send(command.prompt ?? "review the recent changes", to: target.id)
            return .ok("\(target.displayName) reviewing")

        case .runTests:
            store.send("run the tests", to: target.id)
            return .ok("\(target.displayName) running tests")

        case .switchModel:
            guard let model = command.model else {
                return .refused("no model named")
            }
            return store.switchModel(model, on: target.id)
                ? .ok("\(target.displayName) → \(model)")
                : .refused("\(target.displayName) has no model \"\(model)\"")

        case .handoff:
            guard let kind = command.targetAgent else {
                return .refused("no agent to hand off to")
            }
            store.handOff(target.id, to: kind)
            return .ok("handed \(target.workUnitID) to \(kind.rawValue)")

        case .status:
            return .ok("\(target.displayName): \(StateColors.name(for: target.state).lowercased())")

        case .unknown:
            // A sentence with no recognised command word is almost always just
            // something to say to the agent. Sending it beats discarding it.
            store.send(trimmed, to: target.id)
            return .ok("sent to \(target.displayName): \(trimmed)")
        }
    }

    /// Which agent the command is about: the one it names, else the selected one.
    private func resolveTarget(_ command: ParsedCommand) -> MockAgent? {
        if let kind = command.agent {
            let live = store.agents.filter { $0.agent == kind && $0.isLive }
            if let selected = live.first(where: { $0.id == store.selectedAgentID }) {
                return selected
            }
            return live.first
        }
        return store.selectedAgent
    }

    /// A prompt that says what to do, rather than just "keep going".
    private func isInstruction(_ prompt: String) -> Bool {
        let filler: Set<String> = [
            "continue", "keep going", "go", "go on", "resume", "restart",
            "dale", "dal", "segui", "seguí", "prosigue",
        ]
        let cleaned = prompt
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?"))
            .lowercased()
        return !filler.contains(cleaned) && cleaned.split(separator: " ").count > 1
    }
}
