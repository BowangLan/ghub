import SwiftUI
import AppKit

struct BranchRowSection: View {
    let repo: Repo
    let baseBranch: String
    let onAfterSwitch: @MainActor () async -> Void

    @State private var branches: [Branch] = []
    @State private var isSwitching: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            BranchSwitcher(
                currentBranch: repo.currentBranch ?? "—",
                branches: branches,
                isSwitching: isSwitching,
                onSwitch: { branch in await switchTo(branch) }
            )
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
        .task(id: repo.id) { await loadBranches() }
        .onChange(of: repo.lastSyncedAt) { _, _ in
            Task { await loadBranches() }
        }
    }

    private func loadBranches() async {
        let br = (try? await Database.shared.branches(repoID: repo.id)) ?? []
        self.branches = br
    }

    @MainActor
    private func switchTo(_ branch: Branch) async {
        guard !branch.isCurrent, !isSwitching else { return }
        withAnimation(.easeOut(duration: 0.15)) { isSwitching = true }
        do {
            try await GitClient.checkout(path: repo.path, branch: branch.name)
            await SyncManager.shared.syncRepo(id: repo.id)
            await onAfterSwitch()
            await loadBranches()
        } catch {
            presentSwitchError(error)
        }
        withAnimation(.easeOut(duration: 0.15)) { isSwitching = false }
    }

    private func presentSwitchError(_ error: Error) {
        let message: String
        if let shell = error as? ShellError {
            message = shell.description
        } else {
            message = error.localizedDescription
        }
        let alert = NSAlert()
        alert.messageText = "Could not switch branch"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

struct BranchSwitcher: View {
    let currentBranch: String
    let branches: [Branch]
    let isSwitching: Bool
    let onSwitch: @MainActor (Branch) async -> Void

    @State private var hovering = false

    var body: some View {
        Menu {
            if branches.isEmpty {
                Text("Loading branches…").foregroundStyle(.secondary)
            } else {
                ForEach(orderedBranches) { b in
                    Button {
                        Task { await onSwitch(b) }
                    } label: {
                        if b.isCurrent {
                            Label(b.name, systemImage: "checkmark")
                        } else {
                            Text(b.name)
                        }
                    }
                    .disabled(b.isCurrent)
                }
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 14, height: 14)
                Text(currentBranch)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.7, anchor: .leading)
                    .frame(width: hovering ? 8 : 0, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .fill(hovering ? DT.Color.surfaceHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .stroke(hovering ? DT.Color.border : Color.clear, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isSwitching)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: isSwitching)
        .pointingHand()
        .help("Switch branch")
    }

    private var orderedBranches: [Branch] {
        let current = branches.filter { $0.isCurrent }
        let others = branches.filter { !$0.isCurrent }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        return current + others
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
