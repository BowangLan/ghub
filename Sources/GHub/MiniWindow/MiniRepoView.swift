import SwiftUI

struct MiniRepoView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var dock: MiniWindowDockState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeNamespace

    @State private var diff: GitClient.WorkingTreeDiff = .empty
    @State private var currentPR: PullRequest?
    @State private var currentChecks: [CICheck] = []
    @State private var loadToken: UUID = UUID()
    @State private var hoverTask: Task<Void, Never>?

    private var selected: Repo? { state.selectedRepo }

    /// `true` when the panel is in dock-badge mode (minified + snapped to a
    /// screen edge). Drives shell asymmetry, border suppression, and the
    /// resting <-> peeked layout branch.
    private var isBadge: Bool { state.miniMinified && dock.isDocked }

    /// `true` when the badge is dwelt-on long enough that the controller has
    /// peeked the window outward.
    private var isPeeked: Bool { isBadge && dock.hovered }

    var body: some View {
        Group {
            if let repo = selected, state.miniMinified {
                if isBadge, !isPeeked {
                    restingBadge(repo: repo)
                } else {
                    compactBody(repo: repo)
                }
            } else if let repo = selected {
                expandedBody(repo: repo)
            } else {
                expandedEmpty
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: state.miniMinified ? nil : .infinity,
            alignment: .topLeading
        )
        .modifier(
            MiniWindowShell(
                dockEdge: isBadge ? dock.edge : .none,
                cornerRadius: MiniWindowMetrics.shellCornerRadius
            )
        )
        .frame(
            minWidth: isBadge ? MiniWindowMetrics.dockedRestingWidth : MiniWindowMetrics.minWidth,
            minHeight: state.miniMinified ? nil : MiniWindowMetrics.expandedDefaultSize.height,
            maxHeight: state.miniMinified ? nil : .infinity
        )
        .contentShape(Rectangle())
        .onHover { isOver in handleHover(isOver) }
        .onDisappear {
            hoverTask?.cancel()
            hoverTask = nil
        }
        .task(id: reloadKey) { await reload() }
    }

    // MARK: - Layouts

    @ViewBuilder
    private func restingBadge(repo: Repo) -> some View {
        MiniRepoDockedRestingView(
            repo: repo,
            pr: currentPR,
            checks: currentChecks,
            dockEdge: dock.edge,
            diff: diff
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }

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
                                 diff: diff,
                                 pr: currentPR,
                                 checks: currentChecks,
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

    // MARK: - Hover (badge peek)

    private func handleHover(_ isOver: Bool) {
        guard isBadge else {
            // Outside badge mode, ensure peek state is cleared.
            if dock.hovered { dock.hovered = false }
            hoverTask?.cancel()
            hoverTask = nil
            return
        }
        hoverTask?.cancel()
        let delay = isOver
            ? MiniWindowMetrics.dockHoverInDelay
            : MiniWindowMetrics.dockHoverOutDelay
        hoverTask = Task { @MainActor in
            let nanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            if !isOver, MiniWindowController.shared.shouldSuppressDockHoverExit() {
                return
            }
            if dock.hovered != isOver {
                dock.hovered = isOver
            }
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
