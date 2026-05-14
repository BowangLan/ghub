import Foundation

enum GitClient {
    static let bin: String = Shell.resolve("git") ?? "/usr/bin/git"

    struct LocalStatus: Sendable {
        let currentBranch: String?
        let isDirty: Bool
        let untrackedCount: Int
        let modifiedCount: Int
    }

    static func isRepo(path: String) async -> Bool {
        let out = try? await Shell.run(bin, ["-C", path, "rev-parse", "--is-inside-work-tree"])
        return out?.status == 0 && (out?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true")
    }

    static func toplevel(path: String) async -> String? {
        let out = try? await Shell.run(bin, ["-C", path, "rev-parse", "--show-toplevel"])
        guard let out, out.status == 0 else { return nil }
        let s = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Absolute path for `git -C`: expands `~`, resolves symlinks, then uses `rev-parse --show-toplevel` when possible.
    static func resolvedWorkTreePath(storedPath: String) async -> String {
        let expanded = (storedPath as NSString).expandingTildeInPath
        let symlinkResolved = URL(fileURLWithPath: expanded, isDirectory: true).resolvingSymlinksInPath().path
        if let root = await toplevel(path: symlinkResolved) { return root }
        return symlinkResolved
    }

    static func remoteURL(path: String) async -> String? {
        let out = try? await Shell.run(bin, ["-C", path, "config", "--get", "remote.origin.url"])
        guard let out, out.status == 0 else { return nil }
        let s = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    static func defaultBranch(path: String) async -> String? {
        let out = try? await Shell.run(bin, ["-C", path, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        guard let out, out.status == 0 else { return nil }
        let s = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = s.firstIndex(of: "/") { return String(s[s.index(after: slash)...]) }
        return s.isEmpty ? nil : s
    }

    /// Parse owner/repo from a git remote URL, if it points at github.com.
    /// Accepts `git@github.com:o/r(.git)`, `https://github.com/o/r(.git)`, `ssh://git@github.com/o/r(.git)`.
    static func parseGitHubSlug(_ url: String) -> (owner: String, repo: String)? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s.removeLast(4) }
        guard let r = s.range(of: "github.com", options: .caseInsensitive) else { return nil }
        var rest = String(s[r.upperBound...])
        if let first = rest.first, first == ":" || first == "/" { rest.removeFirst() }
        let parts = rest.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let owner = String(parts[0])
        var repo = String(parts[1])
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        if owner.isEmpty || repo.isEmpty { return nil }
        return (owner, repo)
    }

    static func localStatus(path: String) async throws -> LocalStatus {
        let head = try await Shell.run(bin, ["-C", path, "symbolic-ref", "--short", "-q", "HEAD"])
        let branch: String? = (head.status == 0)
            ? head.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            : nil
        let st = try await Shell.run(bin, ["-C", path, "status", "--porcelain=v1"])
        if st.status != 0 {
            throw ShellError.nonZeroExit(status: st.status, stderr: st.stderr.isEmpty ? st.stdout : st.stderr)
        }
        var untracked = 0
        var modified = 0
        for raw in st.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            if raw.hasPrefix("??") { untracked += 1 } else { modified += 1 }
        }
        return LocalStatus(
            currentBranch: branch,
            isDirty: untracked + modified > 0,
            untrackedCount: untracked,
            modifiedCount: modified
        )
    }

    static func branches(path: String, repoID: String, currentBranch: String?) async throws -> [Branch] {
        let format = "%(refname:short)%09%(objectname)%09%(upstream:short)%09%(committerdate:iso-strict)%09%(upstream:track)"
        let out = try await Shell.runChecked(bin, ["-C", path, "for-each-ref", "--format=\(format)", "refs/heads"])
        var result: [Branch] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { continue }
            let name = parts[0]
            let sha = parts[1]
            let upstream: String? = parts[2].nilIfEmpty
            let date = ISODate.parse(parts[3])
            let track = parts.count > 4 ? parts[4] : ""
            let (ahead, behind) = parseTrack(track)
            result.append(Branch(
                repoID: repoID,
                name: name,
                headSHA: sha,
                upstream: upstream,
                ahead: ahead,
                behind: behind,
                lastCommitAt: date,
                isCurrent: name == currentBranch
            ))
        }
        return result
    }

    static func checkout(path: String, branch: String) async throws {
        let root = await resolvedWorkTreePath(storedPath: path)
        // `git checkout -- <name>` treats <name> as pathspecs, not a branch. Use `git switch` for branches.
        var args = ["-C", root, "switch"]
        if branch.hasPrefix("-") {
            args.append("--")
        }
        args.append(branch)
        _ = try await Shell.runChecked(bin, args)
    }

    static func commit(path: String, message: String) async throws {
        let root = await resolvedWorkTreePath(storedPath: path)
        _ = try await Shell.runChecked(bin, ["-C", root, "commit", "-m", message])
    }

    static func push(path: String) async throws {
        let root = await resolvedWorkTreePath(storedPath: path)
        _ = try await Shell.runChecked(bin, ["-C", root, "push"])
    }

    static func pull(path: String) async throws {
        let root = await resolvedWorkTreePath(storedPath: path)
        _ = try await Shell.runChecked(bin, ["-C", root, "pull", "--ff-only"])
    }

    /// Parsed `git diff --shortstat` line (staged and unstaged are fetched separately).
    struct DiffShortstat: Sendable, Equatable {
        var filesChanged: Int
        var insertions: Int
        var deletions: Int

        var hasDelta: Bool { filesChanged > 0 || insertions > 0 || deletions > 0 }

        static let empty = DiffShortstat(filesChanged: 0, insertions: 0, deletions: 0)
    }

    struct WorkingTreeDiff: Sendable, Equatable {
        var staged: DiffShortstat
        var unstaged: DiffShortstat

        var hasDelta: Bool { staged.hasDelta || unstaged.hasDelta }

        static let empty = WorkingTreeDiff(staged: .empty, unstaged: .empty)
    }

    enum DiffScope: String, Sendable, Equatable {
        case staged = "Staged"
        case unstaged = "Unstaged"
        case untracked = "Untracked"
    }

    struct FileDiff: Identifiable, Sendable, Equatable {
        var id: String { "\(scope.rawValue):\(path)" }
        let scope: DiffScope
        let status: String
        let path: String
        let oldPath: String?
        let diff: String
        var branch: String?

        var folder: String {
            let folder = (path as NSString).deletingLastPathComponent
            return folder == "." ? "" : folder
        }

        var fileName: String {
            (path as NSString).lastPathComponent
        }
    }

    struct DetailedWorkingTreeDiff: Sendable, Equatable {
        var files: [FileDiff]

        var isEmpty: Bool { files.isEmpty }

        static let empty = DetailedWorkingTreeDiff(files: [])
    }

    struct FileCommitGroup: Identifiable, Sendable, Equatable {
        let id: String
        var name: String
        var files: [FileDiff]
        var branch: String?
        var isDefault: Bool = false

        var title: String { name }
        var paths: [String] { Array(Set(files.map(\.path))).sorted() }
        var fileCount: Int { files.count }
        var diffText: String { files.map(\.diff).filter { !$0.isEmpty }.joined(separator: "\n\n") }
    }

    struct GroupStash: Sendable, Equatable {
        let id: String
        let ref: String
    }

    /// Staged (`--cached`) vs unstaged working tree diffs vs `HEAD` / index.
    static func workingTreeDiff(path: String) async throws -> WorkingTreeDiff {
        async let stagedOut = Shell.run(bin, ["-C", path, "diff", "--cached", "--shortstat"])
        async let unstagedOut = Shell.run(bin, ["-C", path, "diff", "--shortstat"])
        let st = try await stagedOut
        let us = try await unstagedOut
        if st.status != 0 {
            throw ShellError.nonZeroExit(status: st.status, stderr: st.stderr.isEmpty ? st.stdout : st.stderr)
        }
        if us.status != 0 {
            throw ShellError.nonZeroExit(status: us.status, stderr: us.stderr.isEmpty ? us.stdout : us.stderr)
        }
        return WorkingTreeDiff(
            staged: parseDiffShortstat(st.stdout),
            unstaged: parseDiffShortstat(us.stdout)
        )
    }

    static func detailedWorkingTreeDiff(path: String) async throws -> DetailedWorkingTreeDiff {
        let root = await resolvedWorkTreePath(storedPath: path)
        async let staged = fileDiffs(path: root, scope: .staged)
        async let unstaged = fileDiffs(path: root, scope: .unstaged)
        async let untracked = untrackedFileDiffs(path: root)
        return DetailedWorkingTreeDiff(files: try await staged + unstaged + untracked)
    }

    private static func parseDiffShortstat(_ raw: String) -> DiffShortstat {
        var files = 0, ins = 0, del = 0
        for part in raw.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let firstToken = p.split(separator: " ").first, let n = Int(firstToken) else { continue }
            if p.contains("insertion") { ins = n }
            else if p.contains("deletion") { del = n }
            else if p.contains("file"), p.contains("changed") { files = n }
        }
        return DiffShortstat(filesChanged: files, insertions: ins, deletions: del)
    }

    private static func fileDiffs(path: String, scope: DiffScope) async throws -> [FileDiff] {
        let cachedArg = scope == .staged ? ["--cached"] : []
        let names = try await Shell.runChecked(bin, ["-C", path, "diff"] + cachedArg + ["--name-status", "-z"])
        let records = parseNameStatus(names)
        var files: [FileDiff] = []
        for record in records {
            let diffPath = record.diffPath
            let diff = try await Shell.runChecked(bin, ["-C", path, "diff"] + cachedArg + ["--", diffPath])
            files.append(FileDiff(
                scope: scope,
                status: statusLabel(record.status),
                path: record.path,
                oldPath: record.oldPath,
                diff: diff.trimmingCharacters(in: .newlines),
                branch: nil
            ))
        }
        return files
    }

    private static func untrackedFileDiffs(path: String) async throws -> [FileDiff] {
        let names = try await Shell.runChecked(bin, ["-C", path, "ls-files", "--others", "--exclude-standard", "-z"])
        let paths = names.split(separator: "\0", omittingEmptySubsequences: true).map(String.init).sorted()
        var files: [FileDiff] = []
        for relativePath in paths {
            let absolutePath = URL(fileURLWithPath: path).appendingPathComponent(relativePath).path
            let out = try await Shell.run(bin, ["-C", path, "diff", "--no-index", "--", "/dev/null", absolutePath])
            if out.status != 0 && out.status != 1 {
                throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
            }
            files.append(FileDiff(
                scope: .untracked,
                status: "Untracked",
                path: relativePath,
                oldPath: nil,
                diff: out.stdout.trimmingCharacters(in: .newlines),
                branch: nil
            ))
        }
        return files
    }

    @discardableResult
    static func stashGroup(path: String, group: FileCommitGroup, id: String = UUID().uuidString) async throws -> GroupStash? {
        let root = await resolvedWorkTreePath(storedPath: path)
        guard !group.paths.isEmpty else { return nil }
        if Set(group.files.map(\.scope)).count > 1 {
            throw ShellError.nonZeroExit(
                status: 1,
                stderr: "Grouped stash currently requires files with the same Git state. Move staged, unstaged, and untracked files into separate groups before stashing."
            )
        }
        let message = stashMessage(id: id, group: group)
        var args = ["-C", root, "stash", "push", "-m", message]
        switch group.files.first?.scope {
        case .staged:
            try await ensureStagedGroupIsIsolatable(path: root, paths: group.paths)
            args.append("--staged")
        case .unstaged:
            args.append("--keep-index")
        case .untracked:
            args.append("--include-untracked")
        case nil:
            return nil
        }
        args.append("--")
        args.append(contentsOf: group.paths)
        let out = try await Shell.run(bin, args)
        if out.status != 0 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        if out.stdout.contains("No local changes to save") || out.stderr.contains("No local changes to save") {
            return nil
        }
        guard let ref = try await stashRef(path: root, id: id) else { return nil }
        return GroupStash(id: id, ref: ref)
    }

    private static func ensureStagedGroupIsIsolatable(path: String, paths: [String]) async throws {
        let unstaged = try await Shell.runChecked(bin, ["-C", path, "diff", "--name-only", "-z", "--"] + paths)
        if !unstaged.isEmpty {
            throw ShellError.nonZeroExit(
                status: 1,
                stderr: "Cannot isolate staged group because at least one selected file also has unstaged changes. Git stash --staged cannot safely remove only the index copy for mixed files; stage or stash the unstaged hunks first."
            )
        }
    }

    static func popStash(path: String, id: String) async throws {
        let root = await resolvedWorkTreePath(storedPath: path)
        guard let ref = try await stashRef(path: root, id: id) else {
            throw ShellError.nonZeroExit(status: 1, stderr: "stash id not found: \(id)")
        }
        _ = try await Shell.runChecked(bin, ["-C", root, "stash", "pop", "--index", ref])
    }

    static func commitGroupToBranch(
        path: String,
        group: FileCommitGroup,
        branch: String?,
        createBranch: Bool,
        message: String
    ) async throws {
        let root = await resolvedWorkTreePath(storedPath: path)
        let originalBranch = try await currentBranch(path: root)
        let targetBranch = branch?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? originalBranch
        let groupID = "ghub-group-\(UUID().uuidString)"
        let restID = "ghub-rest-\(UUID().uuidString)"

        guard try await stashGroup(path: root, group: group, id: groupID) != nil else {
            throw ShellError.nonZeroExit(status: 1, stderr: "No diff available for group \(group.title)")
        }
        let restStash = try await stashAll(path: root, id: restID)

        do {
            if createBranch {
                _ = try await Shell.runChecked(bin, ["-C", root, "switch", "-c", targetBranch])
            } else {
                try await checkout(path: root, branch: targetBranch)
            }
            try await popStash(path: root, id: groupID)
            _ = try await Shell.runChecked(bin, ["-C", root, "add", "--"] + group.paths)
            try await commit(path: root, message: message)
            try await checkout(path: root, branch: originalBranch)
            if restStash != nil {
                try await popStash(path: root, id: restID)
            }
        } catch {
            try? await checkout(path: root, branch: originalBranch)
            if restStash != nil {
                try? await popStash(path: root, id: restID)
            }
            throw error
        }
    }

    private static func currentBranch(path: String) async throws -> String {
        let out = try await Shell.runChecked(bin, ["-C", path, "symbolic-ref", "--short", "-q", "HEAD"])
        guard let branch = out.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            throw ShellError.nonZeroExit(status: 1, stderr: "detached HEAD is not supported for grouped commits")
        }
        return branch
    }

    private static func stashAll(path: String, id: String) async throws -> GroupStash? {
        let message = "ghub:\(id):remaining"
        let out = try await Shell.run(bin, ["-C", path, "stash", "push", "--include-untracked", "-m", message])
        if out.status != 0 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        if out.stdout.contains("No local changes to save") || out.stderr.contains("No local changes to save") {
            return nil
        }
        guard let ref = try await stashRef(path: path, id: id) else { return nil }
        return GroupStash(id: id, ref: ref)
    }

    private static func stashMessage(id: String, group: FileCommitGroup) -> String {
        "ghub:\(id):\(group.title):\(group.fileCount)"
    }

    private static func stashRef(path: String, id: String) async throws -> String? {
        let out = try await Shell.runChecked(bin, ["-C", path, "stash", "list", "--format=%gd%x00%s"])
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[1].contains("ghub:\(id):") {
                return parts[0]
            }
        }
        return nil
    }

    private struct NameStatusRecord {
        let status: String
        let path: String
        let oldPath: String?

        var diffPath: String { path }
    }

    private static func parseNameStatus(_ raw: String) -> [NameStatusRecord] {
        let parts = raw.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var records: [NameStatusRecord] = []
        var index = 0
        while index < parts.count {
            let status = parts[index]
            index += 1
            guard index < parts.count else { break }
            if status.hasPrefix("R") || status.hasPrefix("C") {
                let oldPath = parts[index]
                index += 1
                guard index < parts.count else { break }
                let newPath = parts[index]
                index += 1
                records.append(NameStatusRecord(status: status, path: newPath, oldPath: oldPath))
            } else {
                let filePath = parts[index]
                index += 1
                records.append(NameStatusRecord(status: status, path: filePath, oldPath: nil))
            }
        }
        return records.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private static func statusLabel(_ status: String) -> String {
        if status.hasPrefix("R") { return "Renamed" }
        if status.hasPrefix("C") { return "Copied" }
        switch status.first {
        case "A": return "Added"
        case "D": return "Deleted"
        case "M": return "Modified"
        case "T": return "Type changed"
        case "U": return "Unmerged"
        default: return status
        }
    }

    static func recentCommits(path: String, repoID: String, branch: String?, limit: Int = 30) async throws -> [Commit] {
        var args = ["-C", path, "log", "-n", String(limit), "--pretty=format:%H%x09%an%x09%ae%x09%aI%x09%s"]
        if let branch { args.append(branch) }
        let out = try await Shell.runChecked(bin, args)
        var commits: [Commit] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5 else { continue }
            commits.append(Commit(
                repoID: repoID,
                sha: parts[0],
                author: parts[1],
                email: parts[2],
                date: ISODate.parse(parts[3]),
                message: parts[4]
            ))
        }
        return commits
    }

    private static func parseTrack(_ s: String) -> (ahead: Int, behind: Int) {
        // Examples from git: "[ahead 2]", "[behind 3]", "[ahead 2, behind 1]", "[gone]", ""
        var ahead = 0
        var behind = 0
        let inner = s.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        for raw in inner.split(separator: ",") {
            let p = raw.trimmingCharacters(in: .whitespaces)
            if p.hasPrefix("ahead ") { ahead = Int(p.dropFirst("ahead ".count)) ?? 0 }
            else if p.hasPrefix("behind ") { behind = Int(p.dropFirst("behind ".count)) ?? 0 }
        }
        return (ahead, behind)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Array where Element == GitClient.FileDiff {
    func sortedByPath() -> [GitClient.FileDiff] {
        sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }
}

enum ISODate {
    nonisolated(unsafe) static let withFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parse(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        if let d = withFrac.date(from: s) { return d }
        return plain.date(from: s)
    }
}
