import Foundation
import CoreServices
import AppKit

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

        scheduleSync(sound: Self.soundKind(for: changes))
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
        if path.contains("/.git/logs/refs/remotes/") { return .git(.push) }
        if path.contains("/.git/refs/remotes/") { return .git(.push) }
        if path.contains("/.git/logs/refs/heads/") { return .git(.commit) }
        if path.contains("/.git/refs/heads/") { return .git(.commit) }
        if path.contains("/.git/refs/") { return .git(.refUpdate) }
        if path.hasSuffix("/.git/logs/HEAD") { return .git(.commit) }
        if path.contains("/.git/logs/") { return .git(.historyUpdate) }
        return .git(.ignoredInternal)
    }

    private static func soundKind(for changes: [RepoChange]) -> ChangeSoundKind? {
        if changes.contains(.git(.push)) { return .push }
        if changes.contains(.git(.commit)) { return .commit }
        if changes.contains(.normalFile) { return .normalFile }
        return nil
    }

    private func scheduleSync(sound: ChangeSoundKind?) {
        pendingSync?.cancel()
        let id = currentRepoID
        let work = DispatchWorkItem {
            guard let id else { return }
            if let sound {
                Task { @MainActor in ChangeSoundPlayer.play(sound) }
            }
            Task { await SyncManager.shared.syncRepoLocalOnly(id: id) }
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
    case mergeUpdate
    case refUpdate
    case commit
    case push
    case ignoredInternal
}

private enum ChangeSoundKind {
    case normalFile
    case commit
    case push

    var resourceName: String {
        switch self {
        case .normalFile:
            return "pen-click"
        case .commit:
            return "git-commit"
        case .push:
            return "git-push"
        }
    }
}

@MainActor
private enum ChangeSoundPlayer {
    private static var sounds: [ChangeSoundKind: NSSound] = [:]

    static func play(_ kind: ChangeSoundKind) {
        if sounds[kind] == nil,
           let url = Bundle.module.url(forResource: kind.resourceName, withExtension: "mp3") {
            sounds[kind] = NSSound(contentsOf: url, byReference: false)
        }

        let sound = sounds[kind]
        sound?.stop()
        sound?.currentTime = 0
        sound?.play()
    }
}
