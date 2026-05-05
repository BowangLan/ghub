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

        static let empty = WorkingTreeDiff(staged: .empty, unstaged: .empty)
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
