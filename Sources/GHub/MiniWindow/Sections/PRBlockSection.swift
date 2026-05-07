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
                CIProgressBar(groups: ciStatusGroups,
                              total: checks.count,
                              checks: checks,
                              prURL: pr.url)
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

enum CIVariant { case success, running, failed, skip

    static func bucket(for check: CICheck) -> CIVariant {
        if check.isFailing { return .failed }
        if check.isPending { return .running }
        if (check.conclusion?.uppercased() ?? "") == "SKIPPED" { return .skip }
        if check.isSuccess { return .success }
        return .skip
    }
}

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

    var iconName: String {
        switch variant {
        case .success: return "checkmark.circle.fill"
        case .running: return "clock.fill"
        case .failed:  return "xmark.octagon.fill"
        case .skip:    return "minus.circle"
        }
    }
}

// MARK: - Sub-views

private struct CIProgressBar: View {
    let groups: [CIGroup]
    let total: Int
    let checks: [CICheck]
    let prURL: String

    private let visualHeight: CGFloat = 6
    private let hitHeight: CGFloat = 22

    @State private var hoveredVariant: CIVariant?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        let denom = max(total, 1)
        return GeometryReader { geo in
            ZStack {
                visualBar(geo: geo, denom: denom)
                hitOverlay(geo: geo, denom: denom)
            }
        }
        .frame(height: hitHeight)
    }

    private func visualBar(geo: GeometryProxy, denom: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(groups, id: \.variant) { g in
                Rectangle()
                    .fill(g.color)
                    .frame(width: width(for: g, in: geo, denom: denom))
                    .pulseIfRunning(g.variant == .running)
            }
            if groups.isEmpty {
                Rectangle().fill(DT.Color.border)
            }
        }
        .frame(height: visualHeight)
        .background(DT.Color.border, in: Capsule())
        .clipShape(Capsule())
    }

    private func hitOverlay(geo: GeometryProxy, denom: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(groups, id: \.variant) { g in
                hitSegment(g, width: width(for: g, in: geo, denom: denom))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func hitSegment(_ g: CIGroup, width: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .onTapGesture { openChecksPage() }
            .onHover { hovering in handleHover(g.variant, hovering: hovering) }
            .pointingHand()
            .popover(
                isPresented: Binding(
                    get: { hoveredVariant == g.variant },
                    set: { newValue in if !newValue { hoveredVariant = nil } }
                ),
                arrowEdge: .bottom
            ) {
                CIChecksPopover(
                    group: g,
                    checks: filteredChecks(for: g.variant),
                    onSelectCheck: { c in
                        if let s = c.url, let url = URL(string: s) {
                            NSWorkspace.shared.open(url)
                        } else {
                            openChecksPage()
                        }
                    },
                    onOpenAll: { openChecksPage() },
                    onContentHover: { inside in
                        if inside {
                            dismissTask?.cancel()
                        } else {
                            handleHover(nil, hovering: false)
                        }
                    }
                )
            }
    }

    private func width(for g: CIGroup, in geo: GeometryProxy, denom: Int) -> CGFloat {
        geo.size.width * (CGFloat(g.count) / CGFloat(denom))
    }

    private func handleHover(_ variant: CIVariant?, hovering: Bool) {
        dismissTask?.cancel()
        if hovering, let variant {
            hoveredVariant = variant
        } else {
            dismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                if !Task.isCancelled { hoveredVariant = nil }
            }
        }
    }

    private func filteredChecks(for variant: CIVariant) -> [CICheck] {
        checks.filter { CIVariant.bucket(for: $0) == variant }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func openChecksPage() {
        let trimmed = prURL.hasSuffix("/") ? String(prURL.dropLast()) : prURL
        guard let url = URL(string: trimmed + "/checks") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct CIChecksPopover: View {
    let group: CIGroup
    let checks: [CICheck]
    let onSelectCheck: (CICheck) -> Void
    let onOpenAll: () -> Void
    let onContentHover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(group.color)
                    .frame(width: 6, height: 6)
                    .pulseIfRunning(group.variant == .running)
                Text("\(checks.count) \(group.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Button(action: onOpenAll) {
                    HStack(spacing: 3) {
                        Text("All checks")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHand()
            }
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(checks) { c in
                    CIChecksPopoverRow(check: c, color: group.color, onTap: { onSelectCheck(c) })
                }
            }
        }
        .padding(10)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
        .onHover { onContentHover($0) }
    }
}

private struct CIChecksPopoverRow: View {
    let check: CICheck
    let color: Color
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 12)
                Text(check.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if check.url != nil {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                        .foregroundStyle(hovered ? .secondary : .tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovered ? DT.Color.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovered = $0 }
    }

    private var iconName: String {
        if check.isFailing { return "xmark.circle.fill" }
        if check.isPending { return "clock.fill" }
        if (check.conclusion?.uppercased() ?? "") == "SKIPPED" { return "minus.circle" }
        if check.isSuccess { return "checkmark.circle.fill" }
        return "circle"
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
