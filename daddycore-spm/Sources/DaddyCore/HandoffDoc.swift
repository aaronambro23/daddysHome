import Foundation

/// One batch document from a project's `docs/handoffs/` directory.
///
/// These are written by whichever agent did the work, following the contract in
/// `WorkflowContract`. Daddy only ever reads them — it never edits an agent's
/// document — and derives the project overview from the set.
public struct HandoffDoc: Identifiable, Sendable {
    public enum Status: String, Sendable {
        case planned        // no tasks ticked yet
        case inProgress     // some ticked
        case done           // explicitly marked done
        case stalled        // all tasks ticked but never marked done
    }

    public struct Task: Sendable {
        public let title: String
        public let isComplete: Bool
    }

    public var id: URL { url }

    public let url: URL
    public let projectID: String

    /// Leading number in the filename — the ordering key.
    public let number: Int
    public let slug: String

    public let title: String
    public let declaredStatus: String?
    public let agent: AgentKind?
    public let tasks: [Task]
    public let goal: String?
    public let summary: String?
    public let nextSteps: String?
    public let changes: String?
    public let modifiedAt: Date

    // MARK: Derived

    public var completedCount: Int { tasks.filter(\.isComplete).count }
    public var totalCount: Int { tasks.count }

    public var progress: Double {
        guard totalCount > 0 else { return declaredStatus == "done" ? 1 : 0 }
        return Double(completedCount) / Double(totalCount)
    }

    public var status: Status {
        if declaredStatus?.lowercased() == "done" { return .done }
        if totalCount > 0 && completedCount == totalCount { return .stalled }
        if completedCount > 0 { return .inProgress }
        return .planned
    }

    /// The tasks a following agent still has to do.
    public var outstandingTasks: [Task] { tasks.filter { !$0.isComplete } }

    /// Filename as written on disk, e.g. `003-auth-refactor.md`.
    public var filename: String { url.lastPathComponent }
}

// MARK: - Parsing

public enum HandoffParser {

    /// `003-auth-refactor.md` → (3, "auth-refactor")
    static func parseFilename(_ filename: String) -> (number: Int, slug: String)? {
        let base = filename.hasSuffix(".md")
            ? String(filename.dropLast(3))
            : filename

        guard let dash = base.firstIndex(of: "-") else { return nil }
        let numberPart = String(base[base.startIndex..<dash])
        guard let number = Int(numberPart), !numberPart.isEmpty else { return nil }

        let slug = String(base[base.index(after: dash)...])
        return (number, slug)
    }

    public static func parse(contentsOf url: URL, projectID: String) -> HandoffDoc? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let (number, slug) = parseFilename(url.lastPathComponent)
        else { return nil }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date.distantPast

        return parse(
            text: text, url: url, projectID: projectID,
            number: number, slug: slug, modifiedAt: modified
        )
    }

    static func parse(
        text: String, url: URL, projectID: String,
        number: Int, slug: String, modifiedAt: Date
    ) -> HandoffDoc {
        let lines = text.components(separatedBy: .newlines)

        var title = slug.replacingOccurrences(of: "-", with: " ")
        var declaredStatus: String?
        var agent: AgentKind?
        var tasks: [HandoffDoc.Task] = []
        var sections: [String: [String]] = [:]
        var currentSection: String?

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Title: the first H1.
            if line.hasPrefix("# ") && currentSection == nil {
                let heading = String(line.dropFirst(2))
                // Strip a leading "NNN — " / "NNN - " prefix if present.
                title = stripLeadingNumber(from: heading)
                continue
            }

            if line.hasPrefix("## ") {
                currentSection = String(line.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                continue
            }

            // Metadata bullets: "- **Status:** done"
            if let (key, value) = parseMetadata(line) {
                switch key {
                case "status": declaredStatus = value.lowercased()
                case "agent": agent = AgentKind(rawValue: value.lowercased())
                default: break
                }
                continue
            }

            // Checkboxes. Only inside a section, so a stray example in prose
            // does not get counted.
            if let task = parseCheckbox(line), currentSection != nil {
                tasks.append(task)
                continue
            }

            if let section = currentSection, !line.isEmpty {
                sections[section, default: []].append(line)
            }
        }

        func section(_ name: String) -> String? {
            guard let body = sections[name]?.joined(separator: "\n"),
                  !body.isEmpty
            else { return nil }
            // Placeholder italics from the template are not real content.
            if body.hasPrefix("_") && body.hasSuffix("_") { return nil }
            return body
        }

        return HandoffDoc(
            url: url,
            projectID: projectID,
            number: number,
            slug: slug,
            title: title,
            declaredStatus: declaredStatus,
            agent: agent,
            tasks: tasks,
            goal: section("goal"),
            summary: section("summary"),
            nextSteps: section("next possible steps") ?? section("next steps"),
            changes: section("changes"),
            modifiedAt: modifiedAt
        )
    }

    // MARK: Line helpers

    /// `- [x] Ship it` → complete; `- [ ] Ship it` → incomplete.
    static func parseCheckbox(_ line: String) -> HandoffDoc.Task? {
        let bullets = ["- ", "* ", "+ "]
        guard let bullet = bullets.first(where: { line.hasPrefix($0) }) else { return nil }

        let rest = line.dropFirst(bullet.count)
        guard rest.count >= 3, rest.first == "[" else { return nil }

        let markIndex = rest.index(after: rest.startIndex)
        let closeIndex = rest.index(markIndex, offsetBy: 1)
        guard closeIndex < rest.endIndex, rest[closeIndex] == "]" else { return nil }

        let mark = rest[markIndex]
        let isComplete: Bool
        switch mark {
        case "x", "X": isComplete = true
        case " ": isComplete = false
        default: return nil
        }

        let title = rest[rest.index(after: closeIndex)...]
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return HandoffDoc.Task(title: title, isComplete: isComplete)
    }

    /// `- **Status:** done` → ("status", "done")
    static func parseMetadata(_ line: String) -> (String, String)? {
        guard line.hasPrefix("- **") || line.hasPrefix("* **") else { return nil }
        let body = line.dropFirst(4)
        guard let close = body.range(of: ":**") else { return nil }

        let key = body[body.startIndex..<close.lowerBound]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        let value = body[close.upperBound...]
            .trimmingCharacters(in: .whitespaces)

        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    /// "003 — Auth refactor" → "Auth refactor"
    static func stripLeadingNumber(from heading: String) -> String {
        let separators = [" — ", " - ", " – ", ": "]
        for separator in separators {
            if let range = heading.range(of: separator) {
                let prefix = heading[heading.startIndex..<range.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                if Int(prefix) != nil {
                    return String(heading[range.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return heading.trimmingCharacters(in: .whitespaces)
    }
}
