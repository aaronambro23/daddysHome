import Foundation

extension MockStore {
    /// Watch `.git/refs/remotes` for every project that currently has a
    /// dispatched (or in-progress) card. A push is "ahead count went from
    /// something to zero"; a clean repo at watch-start must not dump the column.
    func syncGitPushWatchers() {
        let wanted = Dictionary(
            uniqueKeysWithValues: dispatchedProjectIDs.compactMap { id -> (String, String)? in
                guard let path = gitWatchPath(for: id) else { return nil }
                return (id, path)
            }
        )

        for id in gitPushWatchers.keys where wanted[id] == nil {
            gitPushWatchers[id] = nil
            gitPushWatchPaths[id] = nil
            gitAheadByProject[id] = nil
        }

        for (id, path) in wanted {
            if gitPushWatchPaths[id] == path, gitPushWatchers[id] != nil {
                continue
            }
            startGitPushWatch(projectID: id, path: path)
        }
    }

    private var dispatchedProjectIDs: Set<String> {
        Set(
            orchestratorWorkItems.compactMap { item in
                guard item.status == .dispatched || item.status == .inProgress else { return nil }
                return item.projectID
            }
        )
    }

    private func gitWatchPath(for projectID: String) -> String? {
        guard let project = project(projectID) else { return nil }
        let root = (project.path as NSString).expandingTildeInPath
        let git = (root as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: git, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let remotes = (git as NSString).appendingPathComponent("refs/remotes")
        if FileManager.default.fileExists(atPath: remotes, isDirectory: &isDir), isDir.boolValue {
            return remotes
        }
        let refs = (git as NSString).appendingPathComponent("refs")
        if FileManager.default.fileExists(atPath: refs, isDirectory: &isDir), isDir.boolValue {
            return refs
        }
        return git
    }

    private func startGitPushWatch(projectID: String, path: String) {
        gitPushWatchers[projectID] = DirectoryWatcher(path: path) { [weak self] in
            Task { @MainActor in
                self?.handleGitRefsChanged(projectID: projectID)
            }
        }
        gitPushWatchPaths[projectID] = path
        // Snapshot without firing, so a repo that is already in sync does not
        // mark every dispatched card done the moment we start watching.
        Task { await self.refreshAheadCount(projectID: projectID, applyTransition: false) }
    }

    private func handleGitRefsChanged(projectID: String) {
        // The remotes dir may have appeared since we started watching `.git/refs`.
        if let path = gitWatchPath(for: projectID), path != gitPushWatchPaths[projectID] {
            startGitPushWatch(projectID: projectID, path: path)
        }
        Task { await refreshAheadCount(projectID: projectID, applyTransition: true) }
    }

    private func refreshAheadCount(projectID: String, applyTransition: Bool) async {
        guard let project = project(projectID) else { return }
        let root = (project.path as NSString).expandingTildeInPath
        let ahead = await Self.gitAheadCount(at: root)
        applyAheadCount(ahead, for: projectID, applyTransition: applyTransition)
    }

    private func applyAheadCount(_ ahead: Int?, for projectID: String, applyTransition: Bool) {
        let previous = gitAheadByProject[projectID]
        if let ahead {
            gitAheadByProject[projectID] = ahead
        } else {
            gitAheadByProject[projectID] = nil
        }
        guard applyTransition,
              let previous, previous > 0,
              let ahead, ahead == 0 else { return }
        markDispatchedItemsDone(in: projectID)
    }

    private func markDispatchedItemsDone(in projectID: String) {
        let ids = orchestratorWorkItems.compactMap { item -> UUID? in
            guard item.projectID == projectID,
                  item.status == .dispatched || item.status == .inProgress else { return nil }
            return item.id
        }
        for id in ids {
            _ = moveWorkItem(id, to: .done)
        }
    }

    /// `git status -sb` ahead count, or nil when there is no upstream to compare.
    private static func gitAheadCount(at path: String) async -> Int? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["-C", path, "status", "-sb"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: parseAheadCount(from: text))
            }
        }
    }

    /// First line of `git status -sb` looks like `## main...origin/main [ahead 2]`.
    nonisolated static func parseAheadCount(from status: String) -> Int? {
        let line = status.split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? status
        guard line.contains("...") else { return nil }
        if let range = line.range(of: #"ahead (\d+)"#, options: .regularExpression),
           let count = Int(line[range].split(separator: " ").last ?? "") {
            return count
        }
        return 0
    }
}
