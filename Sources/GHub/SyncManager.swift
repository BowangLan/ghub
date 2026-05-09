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
                group.addTask { await Self.syncOne(repo: repo, includePRs: true) }
            }
        }
        await reload()
    }

    func syncRepo(id: String) async {
        await syncRepo(id: id, includePRs: true)
    }

    func syncRepoLocalOnly(id: String) async {
        await syncRepo(id: id, includePRs: false)
    }

    private func syncRepo(id: String, includePRs: Bool) async {
        AppState.shared.isSyncing = true
        defer {
            AppState.shared.isSyncing = false
            AppState.shared.lastSyncedAt = Date()
        }
        if let repo = AppState.shared.repos.first(where: { $0.id == id }) {
            await Self.syncOne(repo: repo, includePRs: includePRs)
        }
        await reload()
    }

    nonisolated static func syncOne(repo: Repo, includePRs: Bool) async {
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

            var openPRCount = repo.openPRCount
            var failingCheckCount = repo.failingCheckCount
            var pendingCheckCount = repo.pendingCheckCount
            if includePRs, let slug = makeSlug(owner: owner, name: name) {
                do {
                    let fetched = try await GHClient.fetchPRsAndChecks(
                        slug: slug,
                        repoID: repo.id,
                        searchQuery: repo.prFilterQuery
                    )
                    try await Database.shared.replacePRs(repoID: repo.id, prs: fetched.0, checks: fetched.1)
                    let counts = prCounts(prs: fetched.0, checks: fetched.1)
                    openPRCount = counts.open
                    failingCheckCount = counts.failing
                    pendingCheckCount = counts.pending
                } catch {
                    // Best effort: keep previous PR/check counts if GitHub fetch fails.
                }
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
                openPRCount: openPRCount,
                failingCheckCount: failingCheckCount,
                pendingCheckCount: pendingCheckCount,
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
        guard let slug = repo.slug else { return false }
        do {
            let fetched = try await GHClient.fetchPRsAndChecks(
                slug: slug,
                repoID: repo.id,
                searchQuery: repo.prFilterQuery
            )
            try await Database.shared.replacePRs(repoID: repo.id, prs: fetched.0, checks: fetched.1)
            let counts = prCounts(prs: fetched.0, checks: fetched.1)
            try await Database.shared.updateRepoPRCounts(
                id: repo.id,
                openPRCount: counts.open,
                failingCheckCount: counts.failing,
                pendingCheckCount: counts.pending,
                lastSyncedAt: Date()
            )
            return counts.pending > 0
        } catch {
            return repo.pendingCheckCount > 0
        }
    }

    /// Refresh one hot PR via `gh pr checks`, then recompute repo-level CI counts.
    @discardableResult
    nonisolated static func refreshChecksOnly(target: CIWatchTarget) async -> Bool {
        do {
            let checks = try await GHClient.fetchChecks(
                slug: target.slug,
                repoID: target.repoID,
                prNumber: target.prNumber
            )
            try await Database.shared.replaceChecks(
                repoID: target.repoID,
                prNumber: target.prNumber,
                checks: checks
            )
            try await updateRepoPRCountsFromDatabase(repoID: target.repoID)
            return checks.contains(where: \.isPending)
        } catch {
            return true
        }
    }

    private nonisolated static func makeSlug(owner: String?, name: String?) -> String? {
        guard let owner, let name else { return nil }
        return "\(owner)/\(name)"
    }

    private nonisolated static func prCounts(prs: [PullRequest], checks: [CICheck]) -> (
        open: Int,
        failing: Int,
        pending: Int
    ) {
        (
            open: prs.count,
            failing: checks.filter(\.isFailing).count,
            pending: checks.filter(\.isPending).count
        )
    }

    private nonisolated static func updateRepoPRCountsFromDatabase(repoID: String) async throws {
        let prs = try await Database.shared.pullRequests(repoID: repoID)
        var checks: [CICheck] = []
        for pr in prs {
            checks += try await Database.shared.checks(repoID: repoID, prNumber: pr.number)
        }
        let counts = prCounts(prs: prs, checks: checks)
        try await Database.shared.updateRepoPRCounts(
            id: repoID,
            openPRCount: counts.open,
            failingCheckCount: counts.failing,
            pendingCheckCount: counts.pending,
            lastSyncedAt: Date()
        )
    }
}
