import SwiftUI
import AppKit

struct FooterBarSection: View {
    let repo: Repo
    let stagedCount: Int
    let onAfterAction: @MainActor () async -> Void

    @EnvironmentObject var state: AppState
    @State private var showCommit: Bool = false
    @State private var commitMessage: String = ""
    @State private var commitInFlight: Bool = false
    @State private var commitError: String?
    @State private var pushInFlight: Bool = false
    @State private var pullInFlight: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            commitButton
            IconButton(
                systemName: "arrow.down",
                help: "Pull (fast-forward)",
                variant: .outline,
                badge: repo.behind,
                inFlight: pullInFlight
            ) { Task { await runPull() } }
            .disabled(pullInFlight || repo.behind == 0)
            IconButton(
                systemName: "arrow.up",
                help: "Push",
                variant: .outline,
                badge: repo.ahead,
                inFlight: pushInFlight
            ) { Task { await runPush() } }
            .disabled(pushInFlight || repo.ahead == 0)
            IconButton(
                systemName: "arrow.clockwise",
                help: "Fetch / sync",
                variant: .outline,
                inFlight: state.isSyncing
            ) { Task { await SyncManager.shared.syncRepo(id: repo.id) } }
            .disabled(state.isSyncing)
            Spacer(minLength: 6)
        }
        .padding(.horizontal, DT.Spacing.windowPaddingHorizontal)
        .padding(.bottom, DT.Spacing.windowPaddingVertical)
    }

    private var commitButton: some View {
        let enabled = stagedCount > 0 && !commitInFlight
        return Button {
            commitMessage = ""
            commitError = nil
            showCommit = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text(stagedCount > 0 ? "Commit (\(stagedCount))" : "Commit")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: DT.Size.footerBtnHeight)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .fill(enabled ? Color.accentColor : Color.accentColor.opacity(0.35))
            )
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? "Commit \(stagedCount) staged change\(stagedCount == 1 ? "" : "s")"
                      : "Stage changes first (git add)")
        .pointingHand()
        .popover(isPresented: $showCommit, arrowEdge: .top) {
            CommitPopover(
                repo: repo,
                stagedCount: stagedCount,
                message: $commitMessage,
                inFlight: $commitInFlight,
                error: $commitError,
                isPresented: $showCommit,
                onAfterCommit: onAfterAction
            )
        }
    }

    private func runPush() async {
        guard !pushInFlight else { return }
        pushInFlight = true
        defer { pushInFlight = false }
        do {
            try await GitClient.push(path: repo.path)
            AppSoundPlayer.play(.gitPush)
            await SyncManager.shared.syncRepo(id: repo.id)
            await onAfterAction()
        } catch {
            NSSound.beep()
        }
    }

    private func runPull() async {
        guard !pullInFlight else { return }
        pullInFlight = true
        defer { pullInFlight = false }
        do {
            try await GitClient.pull(path: repo.path)
            await SyncManager.shared.syncRepo(id: repo.id)
            await onAfterAction()
        } catch {
            NSSound.beep()
        }
    }
}
