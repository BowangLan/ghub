import SwiftUI

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

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 3) {
                ZStack(alignment: .bottomTrailing) {
                    RepoSelectorView(repo: repo, style: .compact)
                        .padding(.trailing, pr == nil ? 0 : 52)
                    if let pr {
                        PRReferenceView(pr: pr, style: .compact)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 6)

                HStack(alignment: .center, spacing: 2) {
                    ToggleModeButton(minified: true, action: onToggleMode)
                    CloseMiniButton()
                }
            }
            .layoutPriority(1)

            HStack(spacing: 6) {
                Text("+\(ins)")
                    .foregroundStyle(ins == 0 ? Color.primary.opacity(0.30) : DT.Color.emerald)
                Text("-\(del)")
                    .foregroundStyle(del == 0 ? Color.primary.opacity(0.30) : DT.Color.red)
            }
            .font(.system(size: 16, weight: .medium))
            .monospacedDigit()
            .fixedSize()

            CompactCIBar(checks: checks, prURL: pr?.url)
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
            (.failed, "failing"),
            (.skip, "skipped"),
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

    var body: some View {
        IconButton(
            systemName: minified
                ? "arrow.up.left.and.arrow.down.right"
                : "arrow.down.right.and.arrow.up.left",
            help: minified ? "Expand" : "Compact",
            size: .sm,
            action: action
        )
    }
}

struct CloseMiniButton: View {
    var body: some View {
        IconButton(systemName: "xmark", help: "Close", size: .sm) {
            MiniWindowController.shared.hide()
        }
    }
}
