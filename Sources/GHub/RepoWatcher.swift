import Foundation
import CoreServices

/// Watches a single repository directory for filesystem changes and triggers a
/// per-repo sync after a short debounce. Uses FSEvents (recursive).
///
/// Re-target with `watch(repoID:path:)`. Pass `nil`s to stop.
final class RepoWatcher: @unchecked Sendable {
    @MainActor static let shared = RepoWatcher()

    private let queue = DispatchQueue(label: "ghub.repowatcher")
    private var stream: FSEventStreamRef?
    private var currentRepoID: String?
    private var currentPath: String?
    private var pendingSync: DispatchWorkItem?

    private init() {}

    func watch(repoID: String?, path: String?) {
        queue.async { [weak self] in
            self?._watch(repoID: repoID, path: path)
        }
    }

    private func _watch(repoID: String?, path: String?) {
        if currentRepoID == repoID, currentPath == path { return }
        teardown()
        currentRepoID = repoID
        currentPath = path
        guard let path, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return }

        let info = Unmanaged.passUnretained(self).toOpaque()
        var ctx = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [path] as CFArray
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

    private func handle(paths: [String]) {
        let changes = paths.map(Self.resolveChange)
        let shouldSync = changes.contains { change in
            switch change {
            case .normalFile:
                return true
            case .git(let kind):
                return kind != .ignoredInternal
            }
        }
        guard shouldSync else { return }

        scheduleSync(soundHint: Self.soundHint(for: changes))
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
        // Treat them as sync triggers only; a push sound needs an app-owned push action.
        if path.contains("/.git/logs/refs/remotes/") { return .git(.remoteRefUpdate) }
        if path.contains("/.git/refs/remotes/") { return .git(.remoteRefUpdate) }
        if path.contains("/.git/logs/refs/heads/") { return .git(.localHistoryUpdate) }
        if path.contains("/.git/refs/heads/") { return .git(.localHistoryUpdate) }
        if path.contains("/.git/refs/") { return .git(.refUpdate) }
        if path.hasSuffix("/.git/logs/HEAD") { return .git(.localHistoryUpdate) }
        if path.contains("/.git/logs/") { return .git(.historyUpdate) }
        return .git(.ignoredInternal)
    }

    private static func soundHint(for changes: [RepoChange]) -> SoundHint {
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

    private func scheduleSync(soundHint: SoundHint) {
        pendingSync?.cancel()
        let id = currentRepoID
        let path = currentPath
        let work = DispatchWorkItem {
            guard let id else { return }
            Task {
                if let sound = await Self.soundKind(for: soundHint, repoPath: path) {
                    await MainActor.run { AppSoundPlayer.play(sound) }
                }
                await SyncManager.shared.syncRepoLocalOnly(id: id)
            }
        }
        pendingSync = work
        queue.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
    }

    private func teardown() {
        pendingSync?.cancel()
        pendingSync = nil
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }

    deinit { teardown() }
}

private enum RepoChange: Equatable {
    case normalFile
    case git(GitChangeKind)
}

private enum GitChangeKind: Equatable {
    case headUpdate
    case historyUpdate
    case localHistoryUpdate
    case mergeUpdate
    case refUpdate
    case remoteRefUpdate
    case ignoredInternal
}

private enum SoundHint {
    case none
    case normalFile
    case localHistoryUpdate
}
