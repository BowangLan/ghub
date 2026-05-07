import SwiftUI

struct MiniRepoView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeNamespace

    @State private var diff: GitClient.WorkingTreeDiff = .empty
    @State private var currentPR: PullRequest?
    @State private var currentChecks: [CICheck] = []
    @State private var loadToken: UUID = UUID()

    private var selected: Repo? { state.selectedRepo }

    var body: some View {
        Group {
            if let repo = selected, state.miniMinified {
                compactBody(repo: repo)
            } else if let repo = selected {
                expandedBody(repo: repo)
            } else {
                expandedEmpty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: MiniWindowMetrics.shellCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MiniWindowMetrics.shellCornerRadius, style: .continuous)
                .stroke(DT.Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MiniWindowMetrics.shellCornerRadius, style: .continuous))
        .frame(
            minWidth: MiniWindowMetrics.minWidth,
            minHeight: state.miniMinified
                ? MiniWindowMetrics.compactContentHeight
                : MiniWindowMetrics.expandedDefaultSize.height,
            maxHeight: .infinity
        )
        .task(id: reloadKey) { await reload() }
    }

    // MARK: - Layouts

    @ViewBuilder
    private func compactBody(repo: Repo) -> some View {
        MiniRepoCompactView(
            repo: repo,
            pr: currentPR,
            diff: diff,
            checks: currentChecks,
            namespace: modeNamespace,
            onToggleMode: toggleMode
        )
        .padding(.vertical, DT.Spacing.windowPaddingVertical)
        .padding(.horizontal, DT.Spacing.windowPaddingHorizontal)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .transition(.opacity)
    }

    @ViewBuilder
    private func expandedBody(repo: Repo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderSection(selected: repo,
                          currentPR: currentPR,
                          isSyncing: state.isSyncing,
                          namespace: modeNamespace,
                          onToggleMode: toggleMode)
            VStack(alignment: .leading, spacing: DT.Spacing.v) {
                Divider50()

                BranchSection(repo: repo,
                              diff: diff,
                              baseBranch: baseBranch(for: repo),
                              onAfterSwitch: { await reload() })

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var expandedEmpty: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderSection(selected: nil,
                          currentPR: nil,
                          isSyncing: state.isSyncing,
                          namespace: modeNamespace,
                          onToggleMode: toggleMode)
            EmptyStateSection(reposIsEmpty: state.repos.isEmpty)
                .padding(.horizontal, DT.Spacing.h)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Mode toggle

    private func toggleMode() {
        if reduceMotion {
            state.miniMinified.toggle()
        } else {
            withAnimation(.easeInOut(duration: MiniWindowMetrics.modeAnimationDuration)) {
                state.miniMinified.toggle()
            }
        }
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
