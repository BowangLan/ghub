import Foundation
import CoreServices

/// Watches repository directories for filesystem changes and triggers per-repo
/// syncs after a short debounce. Uses FSEvents (recursive).
///
/// Re-target with `watch(repos:)`. Pass an empty list to stop.
final class RepoWatcher: @unchecked Sendable {
    struct WatchedRepo: Hashable, Sendable {
        let repoID: String
        let path: String
    }

    @MainActor static let shared = RepoWatcher()

    private let queue = DispatchQueue(label: "ghub.repowatcher")
    private var stream: FSEventStreamRef?
    private var watchedRepos: [WatchedRepo] = []
    private var pendingSyncs: [String: DispatchWorkItem] = [:]
    private var pendingChangesByRepo: [String: Set<RepoChange>] = [:]

    private init() {}

    func watch(repos: [WatchedRepo]) {
        queue.async { [weak self] in
            self?._watch(repos: repos)
        }
    }

    private func _watch(repos: [WatchedRepo]) {
        let repos = normalized(repos: repos)
        if watchedRepos == repos { return }
        teardown()
        watchedRepos = repos
        guard !repos.isEmpty else { return }

        let info = Unmanaged.passUnretained(self).toOpaque()
        var ctx = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = repos.map(\.path) as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagIgnoreSelf
            | kFSEventStreamCreateFlagUseCFTypes
        )

        let callback: FSEventStreamCallback = { (_, info, numEvents, eventPaths, _, _) in
            guard let info else { return }
            let me = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = unsafeBitCast(eventPaths, to: NSArray.self)
            var changedPaths: [String] = []
            changedPaths.reserveCapacity(numEvents)
            for case let p as String in arr { changedPaths.append(p) }
            me.handle(paths: changedPaths)
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    private func normalized(repos: [WatchedRepo]) -> [WatchedRepo] {
        let existing = repos.compactMap { repo -> WatchedRepo? in
            let path = repo.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let absolutePath = repo.path.hasPrefix("/") ? "/" + path : path
            guard !repo.repoID.isEmpty, !absolutePath.isEmpty,
                  FileManager.default.fileExists(atPath: absolutePath) else { return nil }
            return WatchedRepo(repoID: repo.repoID, path: absolutePath)
        }
        return Array(Set(existing)).sorted {
            if $0.path == $1.path { return $0.repoID < $1.repoID }
            return $0.path < $1.path
        }
    }

    private func handle(paths: [String]) {
        var changesByRepo: [WatchedRepo: Set<RepoChange>] = [:]
        for path in paths {
            guard let repo = repo(for: path) else { continue }
            changesByRepo[repo, default: []].insert(Self.resolveChange(path))
        }

        for (repo, changes) in changesByRepo {
            handle(changes: changes, repo: repo)
        }
    }

    private func handle(changes: Set<RepoChange>, repo: WatchedRepo) {
        let shouldSync = changes.contains { change in
            switch change {
            case .normalFile:
                return true
            case .git(let kind):
                return kind != .ignoredInternal
            }
        }
        guard shouldSync else { return }

        pendingChangesByRepo[repo.repoID, default: []].formUnion(changes)
        scheduleSync(repo: repo)
    }

    private func repo(for changedPath: String) -> WatchedRepo? {
        watchedRepos
            .filter { changedPath == $0.path || changedPath.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }

    private static func resolveChange(_ path: String) -> RepoChange {
        guard path.contains("/.git/") || path.hasSuffix("/.git") else {
            return .normalFile
        }

        // Ignore noisy files touched by `git status` and our own sync work.
        // Ref-like paths still trigger sync, but do not play the normal file sound.
        if path.hasSuffix("/.git/HEAD") { return .git(.headUpdate) }
        if path.hasSuffix("/.git/ORIG_HEAD") { return .git(.historyUpdate) }
        if path.hasSuffix("/.git/MERGE_HEAD") { return .git(.mergeUpdate) }
        if path.hasSuffix("/.git/packed-refs") { return .git(.refUpdate) }
        // Remote-tracking refs can move after fetch, pull, prune, or push.
        // The remote reflog subject distinguishes terminal `git push` from fetch-like updates.
        if path.contains("/.git/logs/refs/remotes/") { return .git(.remoteRefUpdate(remoteRefName(from: path))) }
        if path.contains("/.git/refs/remotes/") { return .git(.remoteRefUpdate(remoteRefName(from: path))) }
        if path.contains("/.git/logs/refs/heads/") { return .git(.localHistoryUpdate) }
        if path.contains("/.git/refs/heads/") { return .git(.localHistoryUpdate) }
        if path.contains("/.git/refs/") { return .git(.refUpdate) }
        if path.hasSuffix("/.git/logs/HEAD") { return .git(.localHistoryUpdate) }
        if path.contains("/.git/logs/") { return .git(.historyUpdate) }
        return .git(.ignoredInternal)
    }

    private static func remoteRefName(from path: String) -> String? {
        if let range = path.range(of: "/.git/logs/") {
            return String(path[range.upperBound...])
        }
        if let range = path.range(of: "/.git/") {
            return String(path[range.upperBound...])
        }
        return nil
    }

    private static func soundHint(for changes: Set<RepoChange>) -> SoundHint {
        let remoteRefs = changes.compactMap { change -> String? in
            guard case .git(.remoteRefUpdate(let refName)) = change else { return nil }
            return refName
        }
        if !remoteRefs.isEmpty { return .remoteRefUpdate(Array(Set(remoteRefs))) }
        if changes.contains(.git(.localHistoryUpdate)) { return .localHistoryUpdate }
        if changes.contains(.normalFile) { return .normalFile }
        return .none
    }

    private static func soundKind(for hint: SoundHint, repoPath: String?) async -> AppSoundKind? {
        switch hint {
        case .none:
            return nil
        case .normalFile:
            return .normalFile
        case .remoteRefUpdate(let refNames):
            guard let repoPath, await latestRemoteReflogLooksLikePush(path: repoPath, refNames: refNames) else { return nil }
            return .gitPush
        case .localHistoryUpdate:
            guard let repoPath, await latestHeadReflogLooksLikeCommit(path: repoPath) else { return nil }
            return .gitCommit
        }
    }

    private static func latestHeadReflogLooksLikeCommit(path: String) async -> Bool {
        let out = try? await Shell.run(GitClient.bin, ["-C", path, "reflog", "-1", "--format=%gs", "HEAD"])
        guard out?.status == 0 else { return false }
        let subject = out?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return subject.hasPrefix("commit")
            || subject.hasPrefix("cherry-pick:")
            || subject.hasPrefix("revert:")
    }

    private static func latestRemoteReflogLooksLikePush(path: String, refNames: [String]) async -> Bool {
        for refName in refNames {
            let out = try? await Shell.run(GitClient.bin, ["-C", path, "reflog", "-1", "--format=%gs", refName])
            guard out?.status == 0 else { continue }
            let subject = out?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if subject == "update by push" { return true }
        }
        return false
    }

    private func scheduleSync(repo: WatchedRepo) {
        pendingSyncs[repo.repoID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changes = self.pendingChangesByRepo[repo.repoID] ?? []
            self.pendingChangesByRepo[repo.repoID] = nil
            self.pendingSyncs[repo.repoID] = nil
            let soundHint = Self.soundHint(for: changes)
            Task {
                if let sound = await Self.soundKind(for: soundHint, repoPath: repo.path) {
                    await MainActor.run { AppSoundPlayer.play(sound) }
                }
                await SyncManager.shared.syncRepoLocalOnly(id: repo.repoID)
            }
        }
        pendingSyncs[repo.repoID] = work
        queue.asyncAfter(deadline: .now() + .milliseconds(700), execute: work)
    }

    private func teardown() {
        for pendingSync in pendingSyncs.values {
            pendingSync.cancel()
        }
        pendingSyncs = [:]
        pendingChangesByRepo = [:]
        watchedRepos = []
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }

    deinit { teardown() }
}

private enum RepoChange: Hashable {
    case normalFile
    case git(GitChangeKind)
}

private enum GitChangeKind: Hashable {
    case headUpdate
    case historyUpdate
    case localHistoryUpdate
    case mergeUpdate
    case refUpdate
    case remoteRefUpdate(String?)
    case ignoredInternal
}

private enum SoundHint {
    case none
    case normalFile
    case localHistoryUpdate
    case remoteRefUpdate([String])
}
