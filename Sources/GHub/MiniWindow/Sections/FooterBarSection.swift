import SwiftUI
import AppKit

struct FooterBarSection: View {
    let repo: Repo
    let diff: GitClient.WorkingTreeDiff
    let pr: PullRequest?
    let checks: [CICheck]
    let onAfterAction: @MainActor () async -> Void

    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var showCommit: Bool = false
    @State private var commitMessage: String = ""
    @State private var commitInFlight: Bool = false
    @State private var commitError: String?
    @State private var pushInFlight: Bool = false
    @State private var pullInFlight: Bool = false
    @State private var showMerge: Bool = false
    @State private var mergeSubject: String = ""
    @State private var mergeBody: String = ""
    @State private var mergeLoadingDefaults: Bool = false
    @State private var mergeInFlight: Bool = false
    @State private var mergeError: String?

    private var stagedCount: Int { diff.staged.filesChanged }

    var body: some View {
        HStack(spacing: 6) {
            if diff.hasDelta {
                commitButton
            }
            if pr != nil {
                squashMergeButton
            }
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
            IconButton(
                systemName: "doc.text.magnifyingglass",
                help: "Show diff details",
                variant: .outline,
                badge: diff.staged.filesChanged + diff.unstaged.filesChanged + repo.untrackedCount
            ) {
                DiffDetailsWindowController.shared.show(repo: repo)
            }
            Spacer(minLength: 6)
            IconButton(
                systemName: "gearshape",
                help: "Settings",
                variant: .ghost
            ) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
        .padding(.horizontal, DT.Spacing.windowPaddingHorizontal)
        .padding(.bottom, DT.Spacing.windowPaddingVertical)
    }

    private var commitButton: some View {
        let enabled = stagedCount > 0 && !commitInFlight
        return IconButton(
            systemName: "checkmark",
            help: enabled ? "Commit \(stagedCount) staged change\(stagedCount == 1 ? "" : "s")"
                          : "Stage changes first (git add)",
            variant: .primary,
            badge: stagedCount,
            inFlight: commitInFlight
        ) {
            commitMessage = ""
            commitError = nil
            showCommit = true
        }
        .disabled(!enabled)
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

    private var squashMergeButton: some View {
        let enabled = canSquashMerge && !mergeInFlight && !mergeLoadingDefaults
        return Button {
            showMerge = true
            Task { await loadMergeDefaults() }
        } label: {
            HStack(spacing: 6) {
                if mergeInFlight || mergeLoadingDefaults {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("Squash & merge")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .fill(enabled ? DT.Color.emerald : DT.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .stroke(enabled ? Color.clear : DT.Color.border, lineWidth: 0.5)
            )
            .foregroundStyle(enabled ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(!enabled)
        .help(squashMergeHelp)
        .popover(isPresented: $showMerge, arrowEdge: .top) {
            SquashMergePopover(
                pr: pr,
                subject: $mergeSubject,
                mergeBody: $mergeBody,
                loadingDefaults: $mergeLoadingDefaults,
                inFlight: $mergeInFlight,
                error: $mergeError,
                isPresented: $showMerge,
                canMerge: canSquashMerge,
                onReloadDefaults: { await loadMergeDefaults(force: true) },
                onMerge: { await runSquashMerge() }
            )
        }
    }

    private var canSquashMerge: Bool {
        guard let pr, pr.state.uppercased() == "OPEN", !pr.isDraft, !checks.isEmpty else { return false }
        return checks.allSatisfy { $0.isSuccess }
    }

    private var squashMergeHelp: String {
        guard let pr else { return "No PR for this branch" }
        if pr.isDraft { return "Draft PRs cannot be merged" }
        if checks.isEmpty { return "No CI checks loaded" }
        if checks.contains(where: { $0.isFailing }) { return "Fix failing CI before merging" }
        if checks.contains(where: { $0.isPending }) { return "Wait for CI to finish" }
        return "Squash and merge PR #\(pr.number)"
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
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
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
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    private func loadMergeDefaults(force: Bool = false) async {
        guard let pr, let slug = repo.slug else { return }
        if !force, (!mergeSubject.isEmpty || mergeLoadingDefaults) { return }
        mergeLoadingDefaults = true
        mergeError = nil
        defer { mergeLoadingDefaults = false }
        do {
            let message = try await GHClient.defaultSquashMergeMessage(slug: slug, prNumber: pr.number)
            mergeSubject = message.subject
            mergeBody = message.body
        } catch {
            mergeError = friendlyShellError(error)
        }
    }

    private func runSquashMerge() async {
        guard let pr, let slug = repo.slug, canSquashMerge, !mergeInFlight else { return }
        let subject = mergeSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { return }
        mergeInFlight = true
        mergeError = nil
        defer { mergeInFlight = false }
        do {
            try await GHClient.squashMerge(slug: slug, prNumber: pr.number, subject: subject, body: mergeBody)
            AppSoundPlayer.play(.squashMerge)
            showMerge = false
            mergeSubject = ""
            mergeBody = ""
            await SyncManager.shared.syncRepo(id: repo.id)
            await onAfterAction()
        } catch {
            mergeError = friendlyShellError(error)
        }
    }

    private func friendlyShellError(_ err: Error) -> String {
        String(describing: err).replacingOccurrences(of: "ShellError.", with: "")
    }
}

private struct SquashMergePopover: View {
    let pr: PullRequest?
    @Binding var subject: String
    @Binding var mergeBody: String
    @Binding var loadingDefaults: Bool
    @Binding var inFlight: Bool
    @Binding var error: String?
    @Binding var isPresented: Bool
    let canMerge: Bool
    let onReloadDefaults: @MainActor () async -> Void
    let onMerge: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let pr {
                    PRReferenceView(pr: pr, style: .compact)
                }
                Spacer()
                Button {
                    Task { await onReloadDefaults() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(loadingDefaults || inFlight)
                .help("Regenerate GitHub default message")
                .pointingHand()
            }

            TextField("Commit message", text: $subject, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(8)
                .background(DT.Color.surface, in: RoundedRectangle(cornerRadius: DT.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.sm)
                        .stroke(DT.Color.border, lineWidth: 0.5)
                )
                .frame(width: 360)

            TextEditor(text: $mergeBody)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(DT.Color.surface, in: RoundedRectangle(cornerRadius: DT.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.sm)
                        .stroke(DT.Color.border, lineWidth: 0.5)
                )
                .frame(width: 360, height: 156)

            if loadingDefaults {
                Label("Generating GitHub squash message", systemImage: "wand.and.sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(DT.Color.red)
                    .frame(maxWidth: 360, alignment: .leading)
            }

            HStack(spacing: 6) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await onMerge() }
                } label: {
                    HStack(spacing: 6) {
                        if inFlight { ProgressView().controlSize(.small).scaleEffect(0.7) }
                        Text("Squash & merge")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canMerge
                          || loadingDefaults
                          || inFlight
                          || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }
}
