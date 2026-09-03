import Foundation
import DaddyCore

// MARK: - Naming the conversations nobody named
//
// Claude titles its own conversations and Daddy uses that title, because a name
// written from the whole conversation beats anything derived from its opening
// line. The other CLIs write nothing, and those cards fell back to the first
// thing you typed — which is a sentence, not a name: "about page changes were
// left halfway bc of token limit being hit in another…".
//
// So the local model writes one. It is already running for the orchestrator, a
// title is the smallest possible ask of it, and it never leaves the machine.

extension MockStore {

    /// Ask again after this long when the model was unreachable, so a session
    /// started while Ollama was down is not stuck nameless forever — and a
    /// session is not retried every ten seconds either.
    private static let titleRetryInterval: TimeInterval = 300

    /// How long to wait before giving up on one title. It is a label; it is
    /// not worth a request that hangs.
    ///
    /// Generous because the first request after the machine wakes has to load
    /// the model into memory, which took the better part of a minute in
    /// testing while every request after it came back in seconds.
    private static let titleTimeout: TimeInterval = 90

    /// Name any live session whose CLI does not name its own.
    ///
    /// Called from the same pass that refreshes models and context — one more
    /// dictionary lookup per card when there is nothing to do.
    func titleUntitledSessions() {
        for agent in agents where agent.isRealSession && agent.isLive {
            guard let sessionID = agent.sessionID else { continue }
            guard !sessionManager.titlesOwnConversations(agent.agent) else { continue }

            // A generated title is final. Regenerating it as the conversation
            // moves on would rename cards under you while you are reading them.
            guard !titledSessionIDs.contains(sessionID) else { continue }

            if let last = titleAttemptedAt[sessionID],
               Date().timeIntervalSince(last) < Self.titleRetryInterval { continue }
            titleAttemptedAt[sessionID] = Date()

            generateTitle(for: agent.id, sessionID: sessionID)
        }
    }

    private func generateTitle(for agentID: String, sessionID: String) {
        let manager = sessionManager
        let client = ollamaClient
        let model = orchestratorModel

        Task { [weak self] in
            // Reading the head of a rollout is real disk work, and the request
            // that follows is a network call. Neither belongs on the main actor.
            let excerpt = await Task.detached(priority: .utility) {
                manager.openingExcerpt(for: sessionID)
            }.value

            guard let excerpt, excerpt.count > 20 else { return }

            let title = await Self.askForTitle(client: client, model: model, excerpt: excerpt)
            guard let title, let self else { return }

            self.titledSessionIDs.insert(sessionID)
            self.mutateAgent(agentID) { $0.title = title }
        }
    }

    /// One turn, no tools — just the words back, or nothing if it takes too long.
    ///
    /// The timeout is a race rather than a check inside the loop: a check only
    /// runs when an event arrives, so a model that accepts the request and then
    /// says nothing at all would never trip it. That is exactly the shape a
    /// wedged local model has.
    private static func askForTitle(
        client: OllamaClient,
        model: String,
        excerpt: String
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await request(client: client, model: model, excerpt: excerpt) }
            group.addTask {
                try? await Task.sleep(for: .seconds(titleTimeout))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func request(
        client: OllamaClient,
        model: String,
        excerpt: String
    ) async -> String? {
        let system = """
            You name software work sessions. Given the opening of a \
            conversation between a developer and a coding agent, reply with a \
            title of at most six words naming what the work is about. No \
            quotes, no punctuation at the end, no preamble, no explanation — \
            the title alone. Prefer the concrete subject over the activity: \
            "About page layout" beats "Fixing a page".
            """

        var answer = ""
        do {
            let stream = client.chatStream(
                model: model,
                messages: [
                    OllamaMessage(role: .system, content: system),
                    OllamaMessage(role: .user, content: excerpt),
                ],
                temperature: 0.1
            )

            for try await event in stream {
                guard !Task.isCancelled else { return nil }
                switch event {
                case .text(let chunk):
                    answer += chunk
                case .finished(let response):
                    // Populated on the non-streaming path; empty on the
                    // streaming one, where the chunks were the answer.
                    let content = response.message.content
                    if !content.isEmpty { answer = content }
                }
            }
        } catch {
            // Ollama not running, model not pulled, machine asleep. The card
            // keeps its work-unit id and we try again in five minutes.
            return nil
        }

        return clean(answer)
    }

    /// Small models like to answer a question they were not asked. This throws
    /// away the framing and keeps the name.
    private static func clean(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Thinking models sometimes narrate first. The title is the last
        // non-empty line in that case, and the only line in every other.
        if let last = text.split(separator: "\n").last(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) {
            text = String(last)
        }

        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*#.:- "))

        // A model that ignored "six words" produced a sentence, not a title.
        // Better the first prompt than a paragraph on a card.
        guard !text.isEmpty, text.count <= 60, text.split(separator: " ").count <= 8 else {
            return nil
        }
        return text
    }
}
