import SwiftUI

struct MiniRepoView: View {
    @EnvironmentObject var state: AppState

    @State private var diff: GitClient.WorkingTreeDiff = .empty
    @State private var currentPR: PullRequest?
    @State private var currentChecks: [CICheck] = []
    @State private var loadToken: UUID = UUID()

    private var selected: Repo? { state.selectedRepo }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderSection(selected: selected,
                          currentPR: currentPR,
                          isSyncing: state.isSyncing)
            if let repo = selected {
                VStack(alignment: .leading, spacing: DT.Spacing.v) {
                    Divider50()
                    BranchRowSection(repo: repo,
                                     baseBranch: baseBranch(for: repo),
                                     onAfterSwitch: { await reload() })
                    StatsGridSection(diff: diff)
                        .padding(.vertical, -DT.Spacing.v / 2)
                    BreakdownChipsSection(stagedCount: diff.staged.filesChanged,
                                          unstagedCount: diff.unstaged.filesChanged,
                                          untrackedCount: repo.untrackedCount)
                    Divider50()
                    PRBlockSection(pr: currentPR,
                                   currentBranch: repo.currentBranch,
                                   checks: currentChecks)
                    Spacer(minLength: 0)
                    Divider50()
                    FooterBarSection(repo: repo,
                                     stagedCount: diff.staged.filesChanged,
                                     onAfterAction: { await reload() })
                }
                .padding(.horizontal, DT.Spacing.h)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                EmptyStateSection(reposIsEmpty: state.repos.isEmpty)
                    .padding(.horizontal, DT.Spacing.h)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 380, minHeight: 480)
        .task(id: reloadKey) { await reload() }
    }

    // MARK: - Derived

    private func baseBranch(for repo: Repo) -> String {
        currentPR?.baseBranch ?? repo.defaultBranch ?? "main"
    }

    /// Single key that drives `reload()` — re-fires whenever the selected repo,
    /// its current branch, or its sync timestamp changes. Without `currentBranch`
    /// here, switching branches inside the same repo would not re-pick the PR.
    private var reloadKey: String {
        let id = state.selectedRepoID ?? "_none_"
        let branch = selected?.currentBranch ?? ""
        let synced = selected?.lastSyncedAt.map { String($0.timeIntervalSince1970) } ?? ""
        return "\(id)|\(branch)|\(synced)"
    }

    // MARK: - Loading

    private func reload() async {
        loadToken = UUID()
        let token = loadToken
        guard let repo = selected else {
            self.diff = .empty
            self.currentPR = nil
            self.currentChecks = []
            return
        }
        let wd = (try? await GitClient.workingTreeDiff(path: repo.path)) ?? .empty
        let allPRs = (try? await Database.shared.pullRequests(repoID: repo.id)) ?? []
        let pr = pickPR(for: repo.currentBranch, from: allPRs)
        let ck: [CICheck]
        if let pr {
            ck = (try? await Database.shared.checks(repoID: repo.id, prNumber: pr.number)) ?? []
        } else {
            ck = []
        }
        if token != loadToken { return }
        self.diff = wd
        self.currentPR = pr
        self.currentChecks = ck
    }

    private func pickPR(for branch: String?, from prs: [PullRequest]) -> PullRequest? {
        guard let branch, !branch.isEmpty else { return nil }
        let matches = prs.filter { $0.headBranch == branch }
        if let open = matches.first(where: { $0.state.uppercased() == "OPEN" }) { return open }
        return matches.max(by: { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) })
    }
}
