import SwiftUI

/// Minimal layout shown when the MiniWindow is snapped to a screen edge and
/// the cursor is not hovering.
struct MiniRepoDockedRestingView: View {
    let repo: Repo
    let pr: PullRequest?
    let checks: [CICheck]
    let dockEdge: MiniWindowDockEdge
    let diff: GitClient.WorkingTreeDiff

    var body: some View {
        let stats = diffStats

        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                if dockEdge == .right {
                    statusDot
                }
                Spacer(minLength: 0)
                identifier
                if dockEdge == .left {
                    statusDot
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: dockEdge == .right ? .leading : .trailing
            )
            .help(tooltip)
            .layoutPriority(1)

            branchLabel
                .layoutPriority(2)
            diffLabel(insertions: stats.insertions, deletions: stats.deletions)
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var diffStats: (insertions: Int, deletions: Int) {
        let staged = diff.staged
        let unstaged = diff.unstaged
        return (
            staged.insertions + unstaged.insertions,
            staged.deletions + unstaged.deletions
        )
    }

    @ViewBuilder
    private var branchLabel: some View {
        if let branch = repo.currentBranch, !branch.isEmpty {
            BranchReferenceView(name: branch, style: .compact, muted: true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diffLabel(insertions: Int, deletions: Int) -> some View {
        HStack(spacing: 6) {
            Text("+\(insertions)")
                .foregroundStyle(insertions == 0 ? Color.primary.opacity(0.30) : DT.Color.emerald)
            Text("-\(deletions)")
                .foregroundStyle(deletions == 0 ? Color.primary.opacity(0.30) : DT.Color.red)
        }
        .font(.system(size: 18, weight: .medium))
        .monospacedDigit()
        .fixedSize()
    }

    @ViewBuilder
    private var identifier: some View {
        HStack(spacing: 6) {
            Text(repo.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let pr {
                PRReferenceView(pr: pr, style: .resting, showTitle: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .pulseIfRunning(ciStatus == .running)
    }

    private var ciStatus: CIVariant? {
        guard !checks.isEmpty else { return nil }
        if checks.contains(where: { $0.isFailing }) { return .failed }
        if checks.contains(where: { $0.isPending }) { return .running }
        if checks.contains(where: { $0.isSuccess }) { return .success }
        return .skip
    }

    private var dotColor: Color {
        switch ciStatus {
        case .failed:
            return DT.Color.red
        case .running:
            return DT.Color.amber
        case .success:
            return DT.Color.emerald
        case .skip:
            return Color.primary.opacity(0.30)
        case .none:
            return Color.primary.opacity(0.20)
        }
    }

    private var tooltip: String {
        let status: String
        switch ciStatus {
        case .failed:
            status = "CI failing"
        case .running:
            status = "CI running"
        case .success:
            status = "CI passing"
        case .skip:
            status = "CI skipped"
        case .none:
            status = "No checks"
        }

        var parts = [repo.name]
        if let branch = repo.currentBranch, !branch.isEmpty {
            parts.append(branch)
        }
        if let pr {
            parts.append("#\(pr.number) \(pr.title)")
        }
        return "\(parts.joined(separator: " ")) — \(status)"
    }
}
