import AppKit
import SwiftUI

struct BranchReferenceView: View {
    enum Style {
        case compact
        case regular
        case subtle
    }

    let name: String
    var style: Style = .regular
    var muted: Bool = false
    var branches: [Branch]? = nil
    var isSwitching: Bool = false
    var onSwitch: (@MainActor (Branch) async -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        if let branches, let onSwitch {
            Menu {
                if branches.isEmpty {
                    Text("Loading branches…").foregroundStyle(.secondary)
                } else {
                    ForEach(orderedBranches(branches)) { branch in
                        Button {
                            Task { await onSwitch(branch) }
                        } label: {
                            if branch.isCurrent {
                                Label(branch.name, systemImage: "checkmark")
                            } else {
                                Text(branch.name)
                            }
                        }
                        .disabled(branch.isCurrent)
                    }
                }
            } label: {
                label(showChevron: true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isSwitching)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.2), value: isSwitching)
            .pointingHand()
            .help("Switch branch")
        } else {
            label(showChevron: false)
                .fixedSize(horizontal: false, vertical: true)
                .help(name)
        }
    }

    private func label(showChevron: Bool) -> some View {
        HStack(spacing: spec.spacing) {
            ZStack {
                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                } else {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: spec.iconSize, weight: .medium))
                        .foregroundStyle(iconStyle)
                }
            }
            .frame(width: spec.iconFrame, height: spec.iconFrame)

            Text(name)
                .font(spec.font)
                .foregroundStyle(textStyle)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.numericText())

            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.7, anchor: .leading)
                    .frame(width: hovering ? 8 : 0, alignment: .leading)
            }
        }
        .padding(.horizontal, showChevron ? 6 : 0)
        .padding(.vertical, showChevron ? 3 : 0)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm)
                .fill(showChevron && hovering ? DT.Color.surfaceHover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.sm)
                .stroke(showChevron && hovering ? DT.Color.border : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private func orderedBranches(_ branches: [Branch]) -> [Branch] {
        let current = branches.filter { $0.isCurrent }
        let others = branches.filter { !$0.isCurrent }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        return current + others
    }

    private var iconStyle: AnyShapeStyle {
        switch style {
        case .compact, .subtle:
            return AnyShapeStyle(.tertiary)
        case .regular:
            return AnyShapeStyle(.secondary)
        }
    }

    private var textStyle: AnyShapeStyle {
        muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    private struct Spec {
        let spacing: CGFloat
        let iconSize: CGFloat
        let iconFrame: CGFloat
        let font: Font
    }

    private var spec: Spec {
        switch style {
        case .compact:
            return Spec(spacing: 5, iconSize: 10, iconFrame: 12,
                        font: .system(size: 11, design: .monospaced))
        case .regular:
            return Spec(spacing: 6, iconSize: 11, iconFrame: 14,
                        font: .system(size: 12, weight: .medium, design: .monospaced))
        case .subtle:
            return Spec(spacing: 5, iconSize: 11, iconFrame: 12,
                        font: .system(size: 12, design: .monospaced))
        }
    }
}

struct PRReferenceView: View {
    enum Style {
        case compact
        case regular
        case resting
    }

    let pr: PullRequest
    var style: Style = .regular
    var showTitle: Bool = false

    var body: some View {
        Button {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: spec.spacing) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: spec.iconSize, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("#\(pr.number)")
                    .font(spec.numberFont)
                    .foregroundStyle(spec.numberStyle)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if showTitle {
                    Text(pr.title)
                        .font(spec.titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help("Open PR #\(pr.number)")
    }

    private struct Spec {
        let spacing: CGFloat
        let iconSize: CGFloat
        let numberFont: Font
        let titleFont: Font
        let numberStyle: AnyShapeStyle
    }

    private var spec: Spec {
        switch style {
        case .compact:
            return Spec(spacing: 4,
                        iconSize: 10,
                        numberFont: .system(size: 11, weight: .medium),
                        titleFont: .system(size: 11),
                        numberStyle: AnyShapeStyle(.secondary))
        case .regular:
            return Spec(spacing: 6,
                        iconSize: 11,
                        numberFont: .system(size: 13, weight: .medium, design: .monospaced),
                        titleFont: .system(size: 12),
                        numberStyle: AnyShapeStyle(.primary))
        case .resting:
            return Spec(spacing: 5,
                        iconSize: 10,
                        numberFont: .system(size: 12, weight: .semibold),
                        titleFont: .system(size: 12, weight: .regular),
                        numberStyle: AnyShapeStyle(.primary))
        }
    }
}
