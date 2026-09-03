import AppKit
import Foundation
import DaddyCore

// MARK: - Context handoffs
//
// An agent running out of context used to be invisible and unrecoverable: the
// CLI compacted, and everything the session had worked out went with it. This
// catches it early instead.
//
// At 65% of the window, *once the agent has gone idle*, Daddy asks the session
// to write a handoff document — the agent writes it, because it is the only
// thing that knows what it was doing; Daddy re-reading a transcript tail would
// drop every decision made before that tail. When the file lands you are
// notified, and you either approve the continuation or send it to a different
// provider.
//
// The two tiers in the document are deliberate: a paragraph to remind you what
// this work is, and a middle ground with enough for another agent to start
// working without re-reading the repository. Not a changelog.

/// Where one session is in the dance. Absent from the store's dictionary means
/// "still watching, nothing has happened".
enum ContextHandoffPhase {
    /// Daddy has asked the agent to write the document and is waiting for it.
    case asked(at: Date, path: String)
    /// The document exists; the panel is up.
    case proposed
    /// Approved, dismissed, or given up on. Never asked again for this session.
    case resolved
}

/// A written handoff waiting on you.
struct PendingContextHandoff: Identifiable {
    let id = UUID()
    let agentID: String
    let projectID: String
    let workUnitID: String
    let provider: AgentKind
    let path: String
    let percent: Double
    /// The document's "Where this is" section, for the panel's preview.
    let summary: String

    var filename: String { (path as NSString).lastPathComponent }
}

enum ContextHandoff {

    /// How full the window has to be before Daddy asks.
    ///
    /// 65% is early on purpose. Waiting for 90% means asking an agent to
    /// summarise itself with no room left to do it in, and the summary is the
    /// one thing that must not be rushed.
    static let threshold: Double = 65

    /// How long the agent gets to write the file before we stop waiting.
    static let writeTimeout: TimeInterval = 180

    /// Main-actor because the directory it sits in is resolved by the file
    /// panel — `docs/handoffs` where the contract put it, the older
    /// `documents/handoffs` where it did not.
    @MainActor
    static func documentPath(project: MockProject, workUnitID: String) -> String {
        FileTreeView.handoffsPath(for: project) + "/\(workUnitID)-handoff.md"
    }

    /// What Daddy types at the agent that is filling up.
    ///
    /// One line, no newlines anywhere in it: this goes into a live TUI composer
    /// as raw text, and a `\n` submits half a prompt.
    static func requestPrompt(
        path: String,
        provider: AgentKind,
        workUnitID: String,
        percent: Double
    ) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let rounded = Int(percent.rounded())

        return "Daddy here: this session is at \(rounded)% of its context window. "
            + "Before it fills, stop and write a handoff document to \(path) "
            + "(create the directory if it is missing) so another agent can take this work over. "
            + "First line of the file, exactly: "
            + "<!-- daddy-handoff provider=\(provider.rawValue) work-unit=\(workUnitID) "
            + "context=\(rounded) at=\(stamp) -->. "
            + "Then exactly two sections. '## Where this is' — one short paragraph: the goal, "
            + "what is done, what is left. '## Picking it up' — the middle ground: which files "
            + "you touched and why, the decisions and constraints we agreed in this session, "
            + "what is in flight right now, the next concrete step, and any trap the next agent "
            + "would walk into. Leave out the changelog — no bug-by-bug list, nothing the repo "
            + "or the git history already says. Enough that another agent can work from the "
            + "document alone. Write the file, say one line when it is done, and do nothing else."
    }

    /// What the continuation session opens with.
    static func continuationPrompt(
        path: String,
        workUnitID: String,
        from provider: AgentKind
    ) -> String {
        "You are continuing work unit \(workUnitID). The \(provider.rawValue) session that had it "
            + "filled its context and handed over. Read \(path) first and pick up from its next "
            + "step. The handoff is your context — do not re-read the whole repository."
    }

    /// The "Where this is" tier, for the approval panel.
    ///
    /// Reads the file rather than trusting what the agent said in the terminal:
    /// the document on disk is the thing being approved.
    static func summary(ofFileAt path: String) -> String {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }

        var lines: [String] = []
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                if inside { break }
                inside = line.lowercased().contains("where this is")
                continue
            }
            guard inside else { continue }
            lines.append(String(line))
        }

        // No section by that name — the agent wrote something else. Show the
        // top of the file rather than an empty panel.
        let body = lines.isEmpty
            ? text.split(separator: "\n").filter { !$0.hasPrefix("<!--") }.prefix(6).joined(separator: "\n")
            : lines.joined(separator: "\n")

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 700 ? String(trimmed.prefix(700)) + "…" : trimmed
    }
}

// MARK: - The store's half

extension MockStore {

    /// One step of the machine, for every live session. Called from the same
    /// pass that refreshes the context percentages.
    ///
    /// Cheap when nothing is happening: a comparison per card, and one `stat`
    /// per session that has actually been asked for a document.
    func stepContextHandoffs() {
        for agent in agents where agent.isRealSession && agent.isLive {
            switch contextHandoffPhases[agent.id] {
            case .none:
                askForHandoffIfDue(agent)
            case .asked(let at, let path):
                collectHandoffIfWritten(agent, askedAt: at, path: path)
            case .proposed, .resolved:
                continue
            }
        }
    }

    /// Full enough, and quiet. Both halves matter: interrupting an agent
    /// mid-turn to ask for a summary is how you lose the turn.
    private func askForHandoffIfDue(_ agent: MockAgent) {
        guard let percent = agent.contextPercent, percent >= ContextHandoff.threshold else {
            return
        }
        guard case .ready = agent.state else { return }
        guard let project = project(agent.projectID) else { return }

        let path = ContextHandoff.documentPath(project: project, workUnitID: agent.workUnitID)
        send(
            ContextHandoff.requestPrompt(
                path: path,
                provider: agent.agent,
                workUnitID: agent.workUnitID,
                percent: percent
            ),
            to: agent.id
        )
        contextHandoffPhases[agent.id] = .asked(at: Date(), path: path)
    }

    /// The document is there and the agent has stopped writing it.
    ///
    /// Both conditions, because a file that exists is not necessarily a file
    /// that is finished — the agent goes back to `.ready` when it is done.
    private func collectHandoffIfWritten(_ agent: MockAgent, askedAt: Date, path: String) {
        if Date().timeIntervalSince(askedAt) > ContextHandoff.writeTimeout {
            contextHandoffPhases[agent.id] = .resolved
            launchError = "\(agent.displayName): no handoff document was written."
            return
        }

        guard case .ready = agent.state else { return }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let written = attributes?[.modificationDate] as? Date,
              written >= askedAt.addingTimeInterval(-1) else { return }

        // One panel at a time. A second session that filled up while this one
        // was waiting keeps its document and gets proposed on a later pass.
        guard pendingContextHandoff == nil else { return }

        contextHandoffPhases[agent.id] = .proposed
        pendingContextHandoff = PendingContextHandoff(
            agentID: agent.id,
            projectID: agent.projectID,
            workUnitID: agent.workUnitID,
            provider: agent.agent,
            path: path,
            percent: agent.contextPercent ?? ContextHandoff.threshold,
            summary: ContextHandoff.summary(ofFileAt: path)
        )
        signalAttention()
    }

    /// Yes — start the continuation, on whichever provider you picked.
    ///
    /// The old session is left running. It has a full context and nothing left
    /// to give, but it is also the only copy of anything the document missed,
    /// so killing it is your call, not Daddy's.
    func approveContextHandoff(continuingOn kind: AgentKind) {
        guard let pending = pendingContextHandoff,
              let project = project(pending.projectID) else { return }

        pendingContextHandoff = nil
        contextHandoffPhases[pending.agentID] = .resolved

        guard let card = launchReal(kind, in: project, workUnitID: pending.workUnitID) else {
            return
        }

        // Pasted, not submitted — the same contract as a board dispatch, and
        // the only safe way to put text into a CLI that is still booting.
        pasteWhenReady(
            ContextHandoff.continuationPrompt(
                path: pending.path,
                workUnitID: pending.workUnitID,
                from: pending.provider
            ),
            to: card.id
        )
        hopToFleetSession(card.id)
    }

    /// No. The document stays on disk — it cost a turn to write, and it is
    /// still the best record of this session — but Daddy does not ask again.
    func dismissContextHandoff() {
        guard let pending = pendingContextHandoff else { return }
        contextHandoffPhases[pending.agentID] = .resolved
        pendingContextHandoff = nil
    }

    /// Reveal the document in Finder, for reading it before deciding.
    func revealContextHandoff() {
        guard let pending = pendingContextHandoff else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: pending.path)])
    }
}
