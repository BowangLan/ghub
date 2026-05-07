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
        )

        let callback: FSEventStreamCallback = { (_, info, _, _, _, _) in
            guard let info else { return }
            let me = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            me.scheduleSync()
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
