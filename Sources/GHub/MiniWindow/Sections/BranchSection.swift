import SwiftUI

struct BranchSection: View {
    let repo: Repo
    let diff: GitClient.WorkingTreeDiff
    let baseBranch: String
    let onAfterSwitch: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.v / 2) {
            BranchRowSection(
                repo: repo,
                baseBranch: baseBranch,
                onAfterSwitch: onAfterSwitch
            )
            StatsGridSection(diff: diff)
            BreakdownChipsSection(
                stagedCount: diff.staged.filesChanged,
                unstagedCount: diff.unstaged.filesChanged,
                untrackedCount: repo.untrackedCount
            )
        }
        .padding(.horizontal, DT.Spacing.windowPaddingHorizontal)
    }
}
