import SwiftUI
import AppKit

struct MiniRepoCompactView: View {
    let repo: Repo
    let pr: PullRequest?
    let diff: GitClient.WorkingTreeDiff
    let checks: [CICheck]
    let namespace: Namespace.ID
    let onToggleMode: () -> Void

    var body: some View {
        let st = diff.staged
        let us = diff.unstaged
        let ins = st.insertions + us.insertions
        let del = st.deletions + us.deletions

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    pillView
                        .matchedGeometryEffect(id: "miniWindow.statePill", in: namespace)
                }
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(repo.currentBranch ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let pr {
                        Button {
                            if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
                        } label: {
                            Text("#\(pr.number)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Open PR")
                    }
                }
            }
            .layoutPriority(1)

            HStack(spacing: 6) {
                Text("+\(ins)")
                    .foregroundStyle(ins == 0 ? Color.primary.opacity(0.30) : DT.Color.emerald)
                Text("-\(del)")
                    .foregroundStyle(del == 0 ? Color.primary.opacity(0.30) : DT.Color.red)
            }
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .fixedSize()

            CompactCIBar(checks: checks, prURL: pr?.url)
                .frame(width: 96)

            ToggleModeButton(minified: true, action: onToggleMode)
        }
    }

    @ViewBuilder
    private var pillView: some View {
        if let pr {
            StatePill(kind: .pr(pr))
        } else {
            StatePill(kind: .noPR)
        }
    }
}

// MARK: - Compact CI bar

struct CompactCIBar: View {
    let checks: [CICheck]
    let prURL: String?

    private var groups: [CIGroup] {
        var counts: [CIVariant: Int] = [:]
        for c in checks { counts[CIVariant.bucket(for: c), default: 0] += 1 }
        let raw: [(CIVariant, String)] = [
            (.success, "passing"),
            (.running, "running"),
            (.failed,  "failing"),
            (.skip,    "skipped"),
        ]
        return raw.compactMap { v, l in
            let n = counts[v] ?? 0
            return n > 0 ? CIGroup(variant: v, label: l, count: n) : nil
        }
    }

    var body: some View {
        let total = max(checks.count, 1)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                if groups.isEmpty {
                    Rectangle().fill(DT.Color.border)
                } else {
                    ForEach(groups, id: \.variant) { g in
                        Rectangle()
                            .fill(g.color)
                            .frame(width: geo.size.width * (CGFloat(g.count) / CGFloat(total)))
                            .pulseIfRunning(g.variant == .running)
                    }
                }
            }
            .frame(height: 6)
            .background(DT.Color.border, in: Capsule())
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .contentShape(Rectangle())
        .onTapGesture { openChecksPage() }
        .pointingHand()
        .help(checks.isEmpty ? "No checks" : checkSummary)
    }

    private var checkSummary: String {
        let g = groups
        if g.isEmpty { return "No checks" }
        return g.map { "\($0.count) \($0.label)" }.joined(separator: " · ")
    }

    private func openChecksPage() {
        guard let prURL else { return }
        let trimmed = prURL.hasSuffix("/") ? String(prURL.dropLast()) : prURL
        guard let url = URL(string: trimmed + "/checks") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Toggle button

struct ToggleModeButton: View {
    let minified: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: minified
                  ? "arrow.up.left.and.arrow.down.right"
                  : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovered ? DT.Color.surfaceHover : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(hovered ? DT.Color.border : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(minified ? "Expand" : "Compact")
    }
}
