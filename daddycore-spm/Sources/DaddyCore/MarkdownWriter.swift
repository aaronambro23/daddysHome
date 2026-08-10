import Foundation

public struct WorkUnitSnapshot {
    public var goal: String = ""
    public var currentState: String = ""
    public var whatWasDone: [String] = []
    public var changes: [String] = []
    public var remaining: [String] = []
    public var decisions: [String] = []
    public var agentsUsed: [String] = []
    public var notes: String = ""

    public init() {}
}

public final class MarkdownWriter {
    private let workflowRootURL: URL
    private let lock = NSLock()

    public init(workflowRoot: URL? = nil) {
        if let workflowRoot = workflowRoot {
            self.workflowRootURL = workflowRoot
        } else {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            self.workflowRootURL = desktop.appendingPathComponent("DaddyWork")
        }

        try? FileManager.default.createDirectory(at: workflowRootURL, withIntermediateDirectories: true)
    }

    public func getWorkUnitDirectory(project: String, workUnit: String) -> URL {
        let projectDir = workflowRootURL.appendingPathComponent(project)
        let workUnitDir = projectDir.appendingPathComponent(workUnit)
        try? FileManager.default.createDirectory(at: workUnitDir, withIntermediateDirectories: true)
        return workUnitDir
    }

    public func writeSnapshot(project: String, workUnit: String, snapshot: WorkUnitSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        let workUnitDir = getWorkUnitDirectory(project: project, workUnit: workUnit)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = dateFormatter.string(from: Date())

        let filename = "\(timestamp).md"
        let filePath = workUnitDir.appendingPathComponent(filename)

        let markdown = formatSnapshot(snapshot)

        try markdown.write(to: filePath, atomically: true, encoding: .utf8)
    }

    public func writeDone(project: String, workUnit: String, snapshot: WorkUnitSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        let workUnitDir = getWorkUnitDirectory(project: project, workUnit: workUnit)
        let doneFilePath = workUnitDir.appendingPathComponent("DONE.md")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())

        var markdown = "# \(workUnit)\n\n"
        markdown += "**Status**: ✅ DONE\n"
        markdown += "**Completed**: \(timestamp)\n\n"

        markdown += "## Goal\n\(snapshot.goal)\n\n"

        if !snapshot.whatWasDone.isEmpty {
            markdown += "## What Was Done\n"
            for item in snapshot.whatWasDone {
                markdown += "- \(item)\n"
            }
            markdown += "\n"
        }

        if !snapshot.changes.isEmpty {
            markdown += "## Changes\n"
            for change in snapshot.changes {
                markdown += "- \(change)\n"
            }
            markdown += "\n"
        }

        if !snapshot.decisions.isEmpty {
            markdown += "## Decisions\n"
            for decision in snapshot.decisions {
                markdown += "- \(decision)\n"
            }
            markdown += "\n"
        }

        if !snapshot.agentsUsed.isEmpty {
            markdown += "## Agents Used\n"
            for agent in snapshot.agentsUsed {
                markdown += "- \(agent)\n"
            }
            markdown += "\n"
        }

        if !snapshot.notes.isEmpty {
            markdown += "## Notes\n\(snapshot.notes)\n\n"
        }

        try markdown.write(to: doneFilePath, atomically: true, encoding: .utf8)
    }

    public func getRecentSnapshots(project: String, workUnit: String, limit: Int = 5) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let workUnitDir = getWorkUnitDirectory(project: project, workUnit: workUnit)

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: workUnitDir, includingPropertiesForKeys: nil)
            let mdFiles = contents
                .filter { $0.pathExtension == "md" && $0.lastPathComponent != "DONE.md" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .prefix(limit)

            return mdFiles.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        } catch {
            return []
        }
    }

    public func isDone(project: String, workUnit: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let workUnitDir = getWorkUnitDirectory(project: project, workUnit: workUnit)
        let donePath = workUnitDir.appendingPathComponent("DONE.md")

        return FileManager.default.fileExists(atPath: donePath.path)
    }

    private func formatSnapshot(_ snapshot: WorkUnitSnapshot) -> String {
        var markdown = ""

        if !snapshot.goal.isEmpty {
            markdown += "## Goal\n\(snapshot.goal)\n\n"
        }

        if !snapshot.currentState.isEmpty {
            markdown += "## Current State\n\(snapshot.currentState)\n\n"
        }

        if !snapshot.whatWasDone.isEmpty {
            markdown += "## What Was Done\n"
            for item in snapshot.whatWasDone {
                markdown += "- \(item)\n"
            }
            markdown += "\n"
        }

        if !snapshot.changes.isEmpty {
            markdown += "## Changes\n"
            for change in snapshot.changes {
                markdown += "- \(change)\n"
            }
            markdown += "\n"
        }

        if !snapshot.remaining.isEmpty {
            markdown += "## Remaining\n"
            for item in snapshot.remaining {
                markdown += "- \(item)\n"
            }
            markdown += "\n"
        }

        if !snapshot.decisions.isEmpty {
            markdown += "## Decisions\n"
            for decision in snapshot.decisions {
                markdown += "- \(decision)\n"
            }
            markdown += "\n"
        }

        if !snapshot.agentsUsed.isEmpty {
            markdown += "## Agents Used\n"
            for agent in snapshot.agentsUsed {
                markdown += "- \(agent)\n"
            }
            markdown += "\n"
        }

        if !snapshot.notes.isEmpty {
            markdown += "## Notes\n\(snapshot.notes)\n\n"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        markdown += "## Updated\n\(dateFormatter.string(from: Date()))\n"

        return markdown
    }
}
