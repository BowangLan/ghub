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
            scmIconButton(
                icon: "arrow.down",
                help: "Pull (fast-forward)",
                badge: repo.behind,
                inFlight: pullInFlight,
                disabled: pullInFlight || repo.behind == 0
            ) { Task { await runPull() } }
            scmIconButton(
                icon: "arrow.up",
                help: "Push",
                badge: repo.ahead,
                inFlight: pushInFlight,
                disabled: pushInFlight || repo.ahead == 0
            ) { Task { await runPush() } }
            scmIconButton(
                icon: "arrow.clockwise",
                help: "Fetch / sync",
                badge: 0,
                inFlight: state.isSyncing,
                disabled: state.isSyncing
            ) { Task { await SyncManager.shared.syncRepo(id: repo.id) } }
            Spacer(minLength: 6)
            SyncedLabel(repo: repo)
        }
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

    private func scmIconButton(icon: String,
                               help: String,
                               badge: Int,
                               inFlight: Bool,
                               disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SCMIconButtonLabel(icon: icon, badge: badge, inFlight: inFlight)
        }
        .buttonStyle(SCMIconButtonStyle())
        .disabled(disabled)
        .help(help)
        .pointingHand()
    }

    private func runPush() async {
        guard !pushInFlight else { return }
        pushInFlight = true
        defer { pushInFlight = false }
        do {
            try await GitClient.push(path: repo.path)
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

struct SyncedLabel: View {
    let repo: Repo

    var body: some View {
        Group {
            if let last = repo.lastSyncedAt {
                HStack(spacing: 4) {
                    Text("Synced")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(last, style: .relative)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Never synced")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
