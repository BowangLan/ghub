import SwiftUI
import AppKit

struct PRBlockSection: View {
    let pr: PullRequest?
    let currentBranch: String?
    let checks: [CICheck]

    var body: some View {
        if let pr {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.pull")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Button {
                                if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
                            } label: {
                                Text("#\(pr.number)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(pr.baseBranch)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(pulseText(pr: pr))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 6)
                    Text("\(passingCount)/\(checks.count) checks passed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(checks.isEmpty ? 0 : 1)
                }
                CIProgressBar(groups: ciStatusGroups, total: checks.count)
                CILegend(groups: ciStatusGroups)
            }
        } else if currentBranch != nil {
            MutedRow(icon: "circle.dotted", text: "No PR for this branch")
        } else {
            MutedRow(icon: "link.badge.plus", text: "Not connected to a GitHub remote")
        }
    }

    private var passingCount: Int { checks.filter { $0.isSuccess }.count }

    private var ciStatusGroups: [CIGroup] {
        var success = 0, running = 0, failed = 0, skip = 0
        for c in checks {
            if c.isFailing { failed += 1 }
            else if c.isPending { running += 1 }
            else if (c.conclusion?.uppercased() ?? "") == "SKIPPED" { skip += 1 }
            else if c.isSuccess { success += 1 }
            else { skip += 1 }
        }
        let raw: [(CIVariant, String, Int)] = [
            (.success, "passing", success),
            (.running, "running", running),
            (.failed,  "failing", failed),
            (.skip,    "skipped", skip),
        ]
        return raw.compactMap { v, l, c in c > 0 ? CIGroup(variant: v, label: l, count: c) : nil }
    }

    private func pulseText(pr: PullRequest) -> String {
        var failed = 0, running = 0, success = 0
        for c in checks {
            if c.isFailing { failed += 1 }
            else if c.isPending { running += 1 }
            else if c.isSuccess { success += 1 }
        }
        if failed > 0 { return "Needs a closer look" }
        if !checks.isEmpty, success == checks.count { return "All signals green" }
        if running > 0 { return "Checks still moving" }
        if pr.isDraft { return "Draft, still shaping up" }
        return "Waiting on the last signal"
    }
}

// MARK: - CI status data

enum CIVariant { case success, running, failed, skip }

struct CIGroup {
    let variant: CIVariant
    let label: String
    let count: Int

    var color: Color {
        switch variant {
        case .success: return DT.Color.emerald
        case .running: return DT.Color.amber
        case .failed:  return DT.Color.red
        case .skip:    return Color.primary.opacity(0.30)
        }
    }
}

// MARK: - Sub-views

private struct CIProgressBar: View {
    let groups: [CIGroup]
    let total: Int

    var body: some View {
        let denom = max(total, 1)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(groups, id: \.variant) { g in
                    Rectangle()
                        .fill(g.color)
                        .frame(width: geo.size.width * (CGFloat(g.count) / CGFloat(denom)))
                        .pulseIfRunning(g.variant == .running)
                }
                if groups.isEmpty {
                    Rectangle().fill(DT.Color.border)
                }
            }
        }
        .frame(height: 6)
        .background(DT.Color.border, in: Capsule())
        .clipShape(Capsule())
    }
}

private struct CILegend: View {
    let groups: [CIGroup]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(groups, id: \.variant) { g in
                HStack(spacing: 5) {
                    Circle()
                        .fill(g.color)
                        .frame(width: 6, height: 6)
                        .pulseIfRunning(g.variant == .running)
                    Text("\(g.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(g.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(groups.isEmpty ? 0 : 1)
    }
}

private struct MutedRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}
