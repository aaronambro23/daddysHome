import Foundation
import DaddyCore

/// Turns a spoken phrase into something this app can actually do.
///
/// `CommandParser` (DaddyCore) already recognises intent and agent, in English
/// and Spanish, so that is reused. What it has no concept of is *projects* and
/// *batches* — the nouns that matter on this branch — so the remaining words
/// are resolved against real project names and batch slugs here.
struct VoiceRouter {

    enum Action: Equatable {
        case newBatch(agent: AgentKind, projectID: String)
        case continueBatch(agent: AgentKind, projectID: String, docNumber: Int)
        case copyBrief(projectID: String)
        case openProject(projectID: String)
        /// Understood, but something is missing to act on it.
        case needsTarget(String)
        case unrecognised(String)
    }

    struct Resolution {
        let action: Action
        /// One line shown under the field so the user sees the interpretation
        /// before pressing Enter. Nothing executes without confirmation.
        let preview: String
    }

    private let parser = CommandParser()

    /// - Parameters:
    ///   - projects: everything Daddy knows about.
    ///   - documents: batches for `currentProjectID`, used to match by slug.
    func resolve(
        _ transcript: String,
        projects: [Project],
        documents: [HandoffDoc],
        currentProjectID: String?,
        installed: Set<AgentKind>
    ) -> Resolution {
        let cleaned = Self.stripWakeWord(transcript)
        guard !cleaned.isEmpty else {
            return Resolution(action: .unrecognised(transcript), preview: "")
        }

        let parsed = parser.parse(cleaned)
        let project = matchProject(in: cleaned, projects: projects, fallback: currentProjectID)
        let doc = matchDocument(in: cleaned, documents: documents)
        let spokenAgent = matchAgent(in: cleaned)

        // "copy the brief for korean makeup"
        if cleaned.localizedCaseInsensitiveContains("brief") {
            guard let project else {
                return Resolution(action: .needsTarget("brief"), preview: "Which project's brief?")
            }
            return Resolution(
                action: .copyBrief(projectID: project.id),
                preview: "Copy handoff brief · \(project.name)"
            )
        }

        // "open wagerwise"
        if cleaned.hasPrefix("open"), let project {
            return Resolution(
                action: .openProject(projectID: project.id),
                preview: "Open \(project.name)"
            )
        }

        // Our own verb detection comes first. CommandParser's dictionary was
        // built for the live-session model and has no "start", "launch" or
        // "run" — the most natural words for this — so relying on it alone
        // makes the most obvious phrase fail.
        let wantsLaunch = isLaunchPhrase(cleaned)
            || [.work, .resume, .handoff].contains(parsed.intent)

        if wantsLaunch {
            guard let project else {
                return Resolution(
                    action: .needsTarget("project"),
                    preview: "Which project?"
                )
            }

            let agent = spokenAgent ?? parsed.targetAgent ?? parsed.agent ?? doc?.agent ?? .claude
            guard installed.contains(agent) else {
                return Resolution(
                    action: .unrecognised(cleaned),
                    preview: "\(agent.displayName) is not installed"
                )
            }

            if let doc {
                return Resolution(
                    action: .continueBatch(
                        agent: agent, projectID: project.id, docNumber: doc.number
                    ),
                    preview: "\(agent.displayName) → continue \(doc.filename) · \(project.name)"
                )
            }

            return Resolution(
                action: .newBatch(agent: agent, projectID: project.id),
                preview: "\(agent.displayName) → new batch · \(project.name)"
            )
        }

        switch parsed.intent {
        case .work, .resume, .handoff:
            // Handled above.
            return Resolution(action: .unrecognised(cleaned), preview: "Not understood")

        case .status:
            guard let project else {
                return Resolution(action: .needsTarget("project"), preview: "Status of what?")
            }
            return Resolution(
                action: .openProject(projectID: project.id),
                preview: "Show \(project.name)"
            )

        case .stop, .interrupt, .review, .runTests, .switchModel:
            // These belong to the live-session model this branch dropped.
            // Saying so is better than silently doing nothing.
            return Resolution(
                action: .unrecognised(cleaned),
                preview: "Daddy doesn't control running agents — that happens in your terminal"
            )

        case .unknown:
            return Resolution(action: .unrecognised(cleaned), preview: "Not understood")
        }
    }

    // MARK: - Matching

    /// Verbs that mean "put an agent on this", in English and Spanish.
    static let launchVerbs: Set<String> = [
        "start", "launch", "run", "continue", "resume", "spawn", "kick",
        "empezar", "empieza", "empeza", "arranca", "arrancar",
        "sigue", "segui", "seguir", "continua", "continuar", "dale",
    ]

    func isLaunchPhrase(_ text: String) -> Bool {
        !Self.tokens(text).isDisjoint(with: Self.launchVerbs)
    }

    /// The agent named in the phrase, if any. "agent" is Cursor's CLI name and
    /// is deliberately not matched — it is too generic in speech.
    func matchAgent(in text: String) -> AgentKind? {
        let spoken = Self.tokens(text)
        if spoken.contains("claude") { return .claude }
        if spoken.contains("codex") { return .codex }
        if spoken.contains("cursor") { return .cursor }
        if spoken.contains("opencode") || spoken.contains("open code") { return .opencode }
        return nil
    }

    /// HEX transcribes the wake word too when it is spoken; drop it.
    static func stripWakeWord(_ transcript: String) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["daddy,", "daddy", "papi,", "papi"] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.")).lowercased()
    }

    /// Matches on words rather than raw substrings, so "ocho" does not match
    /// inside another word. Falls back to the selected project.
    func matchProject(
        in text: String, projects: [Project], fallback: String?
    ) -> Project? {
        let spoken = Self.tokens(text)

        var best: (project: Project, score: Int)?
        for project in projects {
            let nameTokens = Self.tokens(project.name)
            guard !nameTokens.isEmpty else { continue }

            let hits = nameTokens.filter { spoken.contains($0) }.count
            // Every word of the project name must appear, so "notes" does not
            // claim "notes-sync" when "sync" was never said.
            guard hits == nameTokens.count else { continue }

            if best == nil || hits > best!.score {
                best = (project, hits)
            }
        }

        if let best { return best.project }
        return projects.first { $0.id == fallback }
    }

    /// Matches a batch by number ("zero zero two", "002") or by slug words.
    func matchDocument(in text: String, documents: [HandoffDoc]) -> HandoffDoc? {
        let spoken = Self.tokens(text)

        for doc in documents {
            let slugTokens = Self.tokens(doc.slug)
            guard !slugTokens.isEmpty else { continue }
            if slugTokens.allSatisfy({ spoken.contains($0) }) { return doc }
        }

        // Digits: "continue 2" / "continue 002"
        for token in spoken {
            if let number = Int(token), let doc = documents.first(where: { $0.number == number }) {
                return doc
            }
        }
        return nil
    }

    /// Lowercased alphanumeric words, hyphens and underscores split apart.
    static func tokens(_ text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(
            text.lowercased()
                .components(separatedBy: separators)
                .filter { $0.count > 1 }
        )
    }
}
