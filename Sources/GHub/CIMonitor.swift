import Foundation

/// Polls hot repo+PR pairs that have at least one pending CI check, on a
/// 15-second cadence. Idle when nothing is pending — only the regular
/// `SyncManager` sync discovers the first running signal, after which this
/// monitor refreshes those PR checks until they settle.
@MainActor
final class CIMonitor {
    @MainActor static let shared = CIMonitor()
    private static let intervalSeconds = 15

    private var task: Task<Void, Never>?

    @Published private(set) var hotPRs: Set<CIWatchTarget> = []

    private init() {}

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                let nanos = UInt64(Self.intervalSeconds) * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        hotPRs = []
        AppState.shared.ciMonitoringPRs = []
    }

    /// Restart the loop so a changed interval / enable flag takes effect on the
    /// next tick rather than after the in-flight sleep finishes.
    func reschedule() {
        if AppState.shared.ciMonitorEnabled {
            start()
        } else {
            stop()
        }
    }

    private func tick() async {
        guard AppState.shared.ciMonitorEnabled, GHClient.isAvailable else {
            if !hotPRs.isEmpty {
                hotPRs = []
                AppState.shared.ciMonitoringPRs = []
            }
            return
        }

        let discovered = await discoverHotPRs()
        if hotPRs != discovered {
            hotPRs = discovered
            AppState.shared.ciMonitoringPRs = discovered
        }
        guard !discovered.isEmpty else { return }

        var stillHot = Set<CIWatchTarget>()
        var finishedGreen = false
        await withTaskGroup(of: (CIWatchTarget, CIRefreshResult).self) { group in
            for target in discovered {
                group.addTask {
                    let result = await SyncManager.refreshChecksOnly(target: target)
                    return (target, result)
                }
            }
            for await (target, result) in group {
                if result == .pending {
                    stillHot.insert(target)
                } else if result == .finishedGreen {
                    finishedGreen = true
                }
            }
        }
        if finishedGreen {
            AppSoundPlayer.play(.ciGreen)
        }
        if hotPRs != stillHot {
            hotPRs = stillHot
            AppState.shared.ciMonitoringPRs = stillHot
        }
        await SyncManager.shared.reload()
    }

    private func discoverHotPRs() async -> Set<CIWatchTarget> {
        var targets = Set<CIWatchTarget>()
        for repo in AppState.shared.repos where repo.syncEnabled {
            guard let slug = repo.slug else { continue }
            let prs = (try? await Database.shared.pullRequests(repoID: repo.id)) ?? []
            for pr in prs {
                let checks = (try? await Database.shared.checks(repoID: repo.id, prNumber: pr.number)) ?? []
                if checks.contains(where: \.isPending) {
                    targets.insert(CIWatchTarget(repoID: repo.id, slug: slug, prNumber: pr.number))
                }
            }
        }
        return targets
    }
}
