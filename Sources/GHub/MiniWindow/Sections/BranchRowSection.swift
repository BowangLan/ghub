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
            BranchReferenceView(
                name: repo.currentBranch ?? "—",
                style: .regular,
                branches: branches,
                isSwitching: isSwitching,
                onSwitch: { branch in await switchTo(branch) }
            )
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            BranchReferenceView(name: baseBranch, style: .regular, muted: true)
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
