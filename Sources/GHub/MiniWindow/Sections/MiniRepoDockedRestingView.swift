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

        VStack(alignment: .leading, spacing: 6) {
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

            branchLabel
            diffLabel(insertions: stats.insertions, deletions: stats.deletions)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
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
        HStack(spacing: 6) {
            if let branch = repo.currentBranch, !branch.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(branch)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
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
                Text("#\(pr.number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(pr.title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
