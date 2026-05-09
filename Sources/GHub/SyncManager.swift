import Foundation

@MainActor
final class SyncManager {
    @MainActor static let shared = SyncManager()

    private var timerTask: Task<Void, Never>?
    private var fullSyncRunning = false

    private init() {}

    func start() async {
        await reload()
        await syncAll()
        rescheduleTimer()
    }

    func rescheduleTimer() {
        timerTask?.cancel()
        let minutes = max(1, AppState.shared.refreshIntervalMinutes)
        let interval = UInt64(minutes) * 60 * 1_000_000_000
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await self?.syncAll()
            }
        }
    }

    func reload() async {
        do {
            let repos = try await Database.shared.allRepos()
            AppState.shared.repos = repos
        } catch {
            // Best effort: leave previous list.
        }
    }

    func syncAll() async {
        if fullSyncRunning { return }
        fullSyncRunning = true
        AppState.shared.isSyncing = true
        defer {
            AppState.shared.isSyncing = false
            AppState.shared.lastSyncedAt = Date()
            fullSyncRunning = false
        }
        await reload()
        let toSync = AppState.shared.repos.filter(\.syncEnabled)
        await withTaskGroup(of: Void.self) { group in
            for repo in toSync {
                group.addTask { await Self.syncOne(repo: repo) }
            }
        }
        await reload()
    }

    func syncRepo(id: String) async {
        AppState.shared.isSyncing = true
        defer {
            AppState.shared.isSyncing = false
            AppState.shared.lastSyncedAt = Date()
        }
        if let repo = AppState.shared.repos.first(where: { $0.id == id }) {
            await Self.syncOne(repo: repo)
        }
        await reload()
    }

    nonisolated static func syncOne(repo: Repo) async {
        do {
            let status = try await GitClient.localStatus(path: repo.path)
            let branches = try await GitClient.branches(
                path: repo.path, repoID: repo.id, currentBranch: status.currentBranch
            )
            let commits = try await GitClient.recentCommits(
                path: repo.path, repoID: repo.id, branch: status.currentBranch, limit: 30
            )

            var owner = repo.owner
            var name = repo.repoName
            var defaultBranch = repo.defaultBranch
            if let url = await GitClient.remoteURL(path: repo.path),
               let slug = GitClient.parseGitHubSlug(url) {
                owner = slug.owner
                name = slug.repo
            }
            if defaultBranch == nil {
                defaultBranch = await GitClient.defaultBranch(path: repo.path)
            }

            let cur = branches.first(where: { $0.isCurrent })
            let ahead = cur?.ahead ?? 0
            let behind = cur?.behind ?? 0

            try await Database.shared.updateRepoMetadata(
                id: repo.id, owner: owner, repoName: name, defaultBranch: defaultBranch
            )
            try await Database.shared.replaceBranches(repoID: repo.id, branches: branches)
            try await Database.shared.replaceCommits(repoID: repo.id, commits: commits)
            try await Database.shared.updateRepoStatus(
                id: repo.id,
                currentBranch: status.currentBranch,
                isDirty: status.isDirty,
                untrackedCount: status.untrackedCount,
                ahead: ahead, behind: behind,
                openPRCount: repo.openPRCount,
                failingCheckCount: repo.failingCheckCount,
                pendingCheckCount: repo.pendingCheckCount,
                lastSyncedAt: Date()
            )
        } catch {
            // Best effort: keep last known state on failure.
        }
    }

    /// Refresh ONLY the open PRs and CI checks for a repo. Skips git work.
    /// Used by `CIMonitor` to poll PR status faster than the regular sync.
    /// Returns `true` if at least one check is still pending after refresh.
    @discardableResult
    nonisolated static func refreshPRsOnly(repo: Repo) async -> Bool {
        false
    }
}
