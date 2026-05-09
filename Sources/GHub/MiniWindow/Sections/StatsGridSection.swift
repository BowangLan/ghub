import SwiftUI

struct StatsGridSection: View {
    let diff: GitClient.WorkingTreeDiff

    var body: some View {
        let st = diff.staged
        let us = diff.unstaged
        let totalChanged = st.filesChanged + us.filesChanged
        let ins = st.insertions + us.insertions
        let del = st.deletions + us.deletions

        return HStack(alignment: .top, spacing: 12) {
            StatColumn(value: totalChanged,
                       label: "changed",
                       color: .primary,
                       muted: totalChanged == 0)
            StatColumn(value: ins,
                       prefix: "+",
                       label: "additions",
                       color: DT.Color.emerald,
                       muted: ins == 0,
                       direction: .up)
            StatColumn(value: del,
                       prefix: "-",
                       label: "deletions",
                       color: DT.Color.red,
                       muted: del == 0,
                       direction: .down)
        }
    }
}

struct StatColumn: View {
    let value: Int
    var prefix: String = ""
    let label: String
    let color: Color
    let muted: Bool
    var direction: AnimatedNumberDirection = .automatic

    var body: some View {
        let valueColor: Color = muted ? Color.primary.opacity(0.30) : color
        return VStack(alignment: .leading, spacing: 2) {
            AnimatedNumberText(
                value,
                prefix: prefix,
                color: valueColor,
                flashColor: muted ? Color.primary.opacity(0.65) : color,
                direction: direction
            )
                .font(.system(size: 22, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
