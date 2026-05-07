import SwiftUI

struct BranchRowSection: View {
    let repo: Repo
    let baseBranch: String

    var body: some View {
        HStack(spacing: 8) {
            BranchLabel(name: repo.currentBranch ?? "—", muted: false)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            BranchLabel(name: baseBranch, muted: true)
            Spacer(minLength: 0)
            if repo.ahead > 0 {
                AheadBehindChip(symbol: "arrow.up", count: repo.ahead, color: DT.Color.sky)
            }
            if repo.behind > 0 {
                AheadBehindChip(symbol: "arrow.down", count: repo.behind, color: DT.Color.amber)
            }
        }
    }
}

struct BranchLabel: View {
    let name: String
    let muted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct AheadBehindChip: View {
    let symbol: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .pill(color, size: .small)
    }
}
