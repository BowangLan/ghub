import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @MainActor static let shared = AppState()

    private static let selectedRepoIDKey = "selectedRepoID"

    @Published var repos: [Repo] = [] {
        didSet { applyWatcher() }
    }
    @Published var isSyncing: Bool = false
    @Published var lastSyncedAt: Date?
    @Published var ghAvailable: Bool = GHClient.isAvailable
    @Published var ghAuthenticated: Bool = false

    @Published var selectedRepoID: String? = UserDefaults.standard.string(forKey: AppState.selectedRepoIDKey) {
        didSet {
            UserDefaults.standard.set(selectedRepoID, forKey: Self.selectedRepoIDKey)
            applyWatcher()
        }
    }

    @Published var refreshIntervalMinutes: Int = AppState.loadInterval() {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
            SyncManager.shared.rescheduleTimer()
        }
    }

    private init() {}

    var selectedRepo: Repo? {
        guard let id = selectedRepoID else { return nil }
        return repos.first { $0.id == id }
    }

    /// Pick a default selection (first repo) if none is set or the previous one was removed.
    func ensureValidSelection() {
        if let id = selectedRepoID, repos.contains(where: { $0.id == id }) { return }
        selectedRepoID = repos.first?.id
    }

    func applyWatcher() {
        let path = selectedRepo?.path
        RepoWatcher.shared.watch(repoID: selectedRepoID, path: path)
    }

    private static func loadInterval() -> Int {
        let v = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        return v == 0 ? 5 : v
    }

    var totalDirty: Int { repos.filter(\.isDirty).count }
    var totalAhead: Int { repos.reduce(0) { $0 + $1.ahead } }
    var totalBehind: Int { repos.reduce(0) { $0 + $1.behind } }
    var totalOpenPRs: Int { repos.reduce(0) { $0 + $1.openPRCount } }
    var totalFailing: Int { repos.reduce(0) { $0 + $1.failingCheckCount } }

    var menuBarSymbol: String {
        if isSyncing { return "arrow.triangle.2.circlepath" }
        if totalFailing > 0 { return "exclamationmark.triangle.fill" }
        if totalDirty > 0 || totalAhead > 0 || totalBehind > 0 { return "circle.dashed" }
        if repos.isEmpty { return "tray" }
        return "checkmark.circle"
    }

    func addRepoFolder(_ url: URL) async throws {
        let pickedPath = url.path
        guard await GitClient.isRepo(path: pickedPath) else {
            throw NSError(domain: "GHub", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not a Git repository:\n\(pickedPath)"
            ])
        }
        let canonical = (await GitClient.toplevel(path: pickedPath)) ?? pickedPath
        if repos.contains(where: { $0.path == canonical }) {
            throw NSError(domain: "GHub", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Already tracked:\n\(canonical)"
            ])
        }
        let name = (canonical as NSString).lastPathComponent
        _ = try await Database.shared.insertRepo(path: canonical, name: name)
        await SyncManager.shared.reload()
        if let repo = repos.first(where: { $0.path == canonical }) {
            await SyncManager.shared.syncRepo(id: repo.id)
        }
    }

    func removeRepo(id: String) async {
        try? await Database.shared.deleteRepo(id: id)
        await SyncManager.shared.reload()
    }

    func setSyncEnabled(repoID: String, enabled: Bool) async {
        try? await Database.shared.setSyncEnabled(id: repoID, enabled: enabled)
        await SyncManager.shared.reload()
    }

    func setPRFilterQuery(repoID: String, query: String) async {
        try? await Database.shared.setPRFilterQuery(id: repoID, query: query)
        await SyncManager.shared.reload()
    }
}
