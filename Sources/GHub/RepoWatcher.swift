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
        // Drop events that are entirely git-internal. `git status` and our own
        // sync touch `.git/index`, refs, etc., which would otherwise loop:
        //   FSEvents → syncRepo → git ops touch .git → FSEvents → …
        let userFacing = paths.contains { !Self.isGitInternal($0) }
        guard userFacing else { return }
        scheduleSync()
    }

    private static func isGitInternal(_ path: String) -> Bool {
        guard path.contains("/.git/") || path.hasSuffix("/.git") else { return false }
        // Allow ref-mutation paths through so commits, checkouts, merges,
        // and rebases trigger a resync. These files are not rewritten by
        // `git status` / `git log` / `git branch`, so the FSEvents → sync
        // loop documented above does not apply to them.
        if path.hasSuffix("/.git/HEAD") { return false }
        if path.hasSuffix("/.git/ORIG_HEAD") { return false }
        if path.hasSuffix("/.git/MERGE_HEAD") { return false }
        if path.hasSuffix("/.git/packed-refs") { return false }
        if path.contains("/.git/refs/") { return false }
        if path.contains("/.git/logs/") { return false }
        return true
    }

    private func scheduleSync() {
        pendingSync?.cancel()
        let id = currentRepoID
        let work = DispatchWorkItem {
            guard let id else { return }
            Task { await SyncManager.shared.syncRepo(id: id) }
        }
        pendingSync = work
        queue.asyncAfter(deadline: .now() + .milliseconds(500), execute: work)
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
