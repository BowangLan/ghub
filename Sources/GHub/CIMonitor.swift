import Foundation

/// Polls open PRs across all tracked repos that have at least one pending CI
/// check, on a faster cadence than the regular `SyncManager` timer. Idle when
/// nothing is pending — only the `SyncManager` is left to discover the first
/// run-on signal, after which `CIMonitor` takes over until checks settle.
@MainActor
final class CIMonitor {
    @MainActor static let shared = CIMonitor()

    private var task: Task<Void, Never>?

    @Published private(set) var monitoringRepoIDs: Set<String> = []

    private init() {}

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                let secs = AppState.shared.ciMonitorIntervalSeconds
                let nanos = UInt64(max(10, secs)) * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        monitoringRepoIDs = []
        AppState.shared.ciMonitoringRepoIDs = []
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
            if !monitoringRepoIDs.isEmpty {
                monitoringRepoIDs = []
                AppState.shared.ciMonitoringRepoIDs = []
            }
            return
        }

        let candidates = AppState.shared.repos.filter {
            $0.syncEnabled && $0.pendingCheckCount > 0 && $0.slug != nil
        }
        let candidateIDs = Set(candidates.map(\.id))
        if monitoringRepoIDs != candidateIDs {
            monitoringRepoIDs = candidateIDs
            AppState.shared.ciMonitoringRepoIDs = candidateIDs
        }
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for repo in candidates {
                group.addTask {
                    _ = await SyncManager.refreshPRsOnly(repo: repo)
                }
            }
        }
        await SyncManager.shared.reload()
    }
}
