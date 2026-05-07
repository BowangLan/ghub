import SwiftUI
import AppKit

// MARK: - Design tokens (port of Tailwind palette used in git-project-summary-card.tsx)

private enum DT {
    static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let red     = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let amber   = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let sky     = Color(red: 0.055, green: 0.647, blue: 0.914)

    static let border       = Color.primary.opacity(0.10)
    static let surface      = Color.primary.opacity(0.05)
    static let surfaceHover = Color.primary.opacity(0.09)

    static let radius:   CGFloat = 10
    static let radiusSm: CGFloat = 6

    static let hPad: CGFloat = 16
    static let vGap: CGFloat = 16

    static let footerBtnHeight: CGFloat = 26
}

private struct Divider50: View {
    var body: some View {
        Rectangle().fill(DT.border).frame(height: 0.5)
    }
}

// MARK: - Main view

struct MiniRepoView: View {
    @EnvironmentObject var state: AppState
    @State private var diff: GitClient.WorkingTreeDiff = .empty
    @State private var currentPR: PullRequest?
    @State private var currentChecks: [CICheck] = []
    @State private var loadToken: UUID = UUID()

    @State private var showCommit: Bool = false
    @State private var commitMessage: String = ""
    @State private var commitInFlight: Bool = false
    @State private var commitError: String?
    @State private var pushInFlight: Bool = false
    @State private var pullInFlight: Bool = false

    private var selected: Repo? { state.selectedRepo }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let repo = selected {
                VStack(alignment: .leading, spacing: DT.vGap) {
                    Divider50()
                    branchRow(repo)
                    statsGrid(repo)
                        .padding(.vertical, -DT.vGap / 2)
                    breakdownChips(repo)
                    Divider50()
                    prBlock(repo)
                    Spacer(minLength: 0)
                    Divider50()
                    footerBar(repo)
                }
                .padding(.horizontal, DT.hPad)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                emptyState
                    .padding(.horizontal, DT.hPad)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 380, minHeight: 480)
        .task(id: state.selectedRepoID ?? "_none_") { await reload() }
        .onChange(of: selected?.lastSyncedAt) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: - Header (repo title + path on left, PR state pill on right)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                repoMenu
                if let repo = selected {
                    Text((repo.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if state.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
            if let pr = currentPR {
                statePill(pr: pr)
            } else if selected != nil {
                statePill(custom: ("No PR", DT.amber, false))
            }
        }
        .padding(.horizontal, DT.hPad)
        .padding(.top, DT.hPad)
        .padding(.bottom, 12)
    }

    private var repoMenu: some View {
        Menu {
            if state.repos.isEmpty {
                Text("No repos tracked").foregroundStyle(.secondary)
            } else {
                ForEach(state.repos) { r in
                    Button {
                        state.selectedRepoID = r.id
                    } label: {
                        if r.id == state.selectedRepoID {
                            Label(r.name, systemImage: "checkmark")
                        } else {
                            Text(r.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selected?.name ?? "Select repo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Branch row (head -> base)

    private func branchRow(_ repo: Repo) -> some View {
        HStack(spacing: 8) {
            branchLabel(repo.currentBranch ?? "—", muted: false)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            branchLabel(baseBranch(for: repo) ?? repo.defaultBranch ?? "main", muted: true)
            Spacer(minLength: 0)
            if repo.ahead > 0 {
                aheadBehindChip(symbol: "arrow.up", count: repo.ahead, color: DT.sky)
            }
            if repo.behind > 0 {
                aheadBehindChip(symbol: "arrow.down", count: repo.behind, color: DT.amber)
            }
        }
    }

    private func branchLabel(_ name: String, muted: Bool) -> some View {
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

    private func aheadBehindChip(symbol: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Stats grid (changed / additions / deletions)

    private func statsGrid(_ repo: Repo) -> some View {
        let st = diff.staged
        let us = diff.unstaged
        let changed = max(st.filesChanged, us.filesChanged) // git counts overlap; staged ≤ unstaged in most cases
        let totalChanged = st.filesChanged + us.filesChanged // best-effort summary
        let displayChanged = totalChanged == 0 ? 0 : max(changed, 1)
        _ = displayChanged // keep clarity — we display totalChanged below
        let ins = st.insertions + us.insertions
        let del = st.deletions + us.deletions

        return HStack(alignment: .top, spacing: 12) {
            statColumn(value: "\(totalChanged)",
                       label: "changed",
                       color: .primary,
                       muted: totalChanged == 0)
            statColumn(value: "+\(ins)",
                       label: "additions",
                       color: DT.emerald,
                       muted: ins == 0)
            statColumn(value: "-\(del)",
                       label: "deletions",
                       color: DT.red,
                       muted: del == 0)
        }
    }

    private func statColumn(value: String, label: String, color: Color, muted: Bool) -> some View {
        let valueColor: Color = muted ? Color.primary.opacity(0.30) : color
        return VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Breakdown chips (staged / unstaged / untracked)

    private func breakdownChips(_ repo: Repo) -> some View {
        let staged = diff.staged.filesChanged
        let unstaged = diff.unstaged.filesChanged
        let untracked = repo.untrackedCount

        return HStack(spacing: 6) {
            chip("\(staged) staged")
            chip("\(unstaged) unstaged")
            chip("\(untracked) untracked")
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DT.surface, in: Capsule())
    }

    // MARK: - PR block (number link, base branch, pulse text, X/Y, progress, legend)

    @ViewBuilder
    private func prBlock(_ repo: Repo) -> some View {
        if let pr = currentPR {
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
                    Text("\(passingChecks)/\(currentChecks.count) checks passed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(currentChecks.isEmpty ? 0 : 1)
                }
                progressBar
                legend
            }
        } else if selected?.currentBranch != nil {
            mutedRow(icon: "circle.dotted", text: "No PR for this branch")
        } else {
            mutedRow(icon: "link.badge.plus", text: "Not connected to a GitHub remote")
        }
    }

    private var progressBar: some View {
        let groups = ciStatusGroups
        let total = max(currentChecks.count, 1)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(groups, id: \.variant) { g in
                    Rectangle()
                        .fill(g.color)
                        .frame(width: geo.size.width * (CGFloat(g.count) / CGFloat(total)))
                        .modifier(PulseIfRunning(active: g.variant == .running))
                }
                if groups.isEmpty {
                    Rectangle().fill(DT.border)
                }
            }
        }
        .frame(height: 6)
        .background(DT.border, in: Capsule())
        .clipShape(Capsule())
    }

    private var legend: some View {
        let groups = ciStatusGroups
        return HStack(spacing: 12) {
            ForEach(groups, id: \.variant) { g in
                HStack(spacing: 5) {
                    Circle()
                        .fill(g.color)
                        .frame(width: 6, height: 6)
                        .modifier(PulseIfRunning(active: g.variant == .running))
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

    private func mutedRow(icon: String, text: String) -> some View {
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

    // MARK: - Footer (VSCode-style commit / pull / push / fetch + Synced X ago)

    private func footerBar(_ repo: Repo) -> some View {
        let stagedCount = diff.staged.filesChanged
        return HStack(spacing: 6) {
            commitButton(repo: repo, stagedCount: stagedCount)
            scmIconButton(
                icon: "arrow.down",
                help: "Pull (fast-forward)",
                badge: repo.behind,
                inFlight: pullInFlight,
                disabled: pullInFlight || repo.behind == 0
            ) {
                Task { await runPull(repo) }
            }
            scmIconButton(
                icon: "arrow.up",
                help: "Push",
                badge: repo.ahead,
                inFlight: pushInFlight,
                disabled: pushInFlight || repo.ahead == 0
            ) {
                Task { await runPush(repo) }
            }
            scmIconButton(
                icon: "arrow.clockwise",
                help: "Fetch / sync",
                badge: 0,
                inFlight: state.isSyncing,
                disabled: state.isSyncing
            ) {
                Task { await SyncManager.shared.syncRepo(id: repo.id) }
            }
            Spacer(minLength: 6)
            syncedLabel(repo: repo)
        }
    }

    private func commitButton(repo: Repo, stagedCount: Int) -> some View {
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
            .frame(height: DT.footerBtnHeight)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusSm)
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
            commitPopover(repo: repo, stagedCount: stagedCount)
        }
    }

    private func commitPopover(repo: Repo, stagedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(repo.currentBranch ?? "—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(stagedCount) staged")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            TextField("Message (Cmd+Enter to commit)",
                      text: $commitMessage,
                      axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(DT.surface, in: RoundedRectangle(cornerRadius: DT.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.radiusSm)
                        .stroke(DT.border, lineWidth: 0.5)
                )
                .frame(width: 320)
                .onSubmit { Task { await runCommit(repo) } }
            if let err = commitError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(DT.red)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            HStack(spacing: 6) {
                Spacer()
                Button("Cancel") { showCommit = false }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await runCommit(repo) }
                } label: {
                    HStack(spacing: 6) {
                        if commitInFlight { ProgressView().controlSize(.small).scaleEffect(0.7) }
                        Text("Commit")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || commitInFlight
                          || stagedCount == 0)
            }
        }
        .padding(14)
    }

    private func scmIconButton(icon: String,
                               help: String,
                               badge: Int,
                               inFlight: Bool,
                               disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        SCMIconButton(icon: icon,
                      help: help,
                      badge: badge,
                      inFlight: inFlight,
                      disabled: disabled,
                      action: action)
    }

    private func syncedLabel(repo: Repo) -> some View {
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.dashed")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No repository selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(state.repos.isEmpty ? "Add one from the menu bar." : "Pick one above.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - State pill (PR state / no PR)

    private func statePill(pr: PullRequest) -> some View {
        let (label, color): (String, Color) = {
            if pr.isDraft { return ("Draft", DT.amber) }
            switch pr.state.uppercased() {
            case "OPEN":   return ("Open", DT.emerald)
            case "MERGED": return ("Merged", DT.sky)
            case "CLOSED": return ("Closed", DT.red)
            default:       return (pr.state.capitalized, .secondary)
            }
        }()
        return statePill(custom: (label, color, true))
    }

    private func statePill(custom: (label: String, color: Color, dot: Bool)) -> some View {
        HStack(spacing: 5) {
            if custom.dot {
                Circle().fill(custom.color).frame(width: 6, height: 6)
            }
            Text(custom.label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(custom.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(custom.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(custom.color.opacity(0.30), lineWidth: 0.5))
    }

    // MARK: - Action button

    // MARK: - Run actions

    private func runCommit(_ repo: Repo) async {
        let msg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !commitInFlight else { return }
        commitInFlight = true
        commitError = nil
        defer { commitInFlight = false }
        do {
            try await GitClient.commit(path: repo.path, message: msg)
            commitMessage = ""
            showCommit = false
            await SyncManager.shared.syncRepo(id: repo.id)
            await reload()
        } catch {
            commitError = friendlyShellError(error)
        }
    }

    private func runPush(_ repo: Repo) async {
        guard !pushInFlight else { return }
        pushInFlight = true
        defer { pushInFlight = false }
        do {
            try await GitClient.push(path: repo.path)
            await SyncManager.shared.syncRepo(id: repo.id)
            await reload()
        } catch {
            NSSound.beep()
        }
    }

    private func runPull(_ repo: Repo) async {
        guard !pullInFlight else { return }
        pullInFlight = true
        defer { pullInFlight = false }
        do {
            try await GitClient.pull(path: repo.path)
            await SyncManager.shared.syncRepo(id: repo.id)
            await reload()
        } catch {
            NSSound.beep()
        }
    }

    private func friendlyShellError(_ error: Error) -> String {
        let raw = String(describing: error)
        return raw.replacingOccurrences(of: "ShellError.", with: "")
    }

    // MARK: - Derived data

    private var passingChecks: Int {
        currentChecks.filter { $0.isSuccess }.count
    }

    private struct CIGroup {
        let variant: CIVariant
        let label: String
        let count: Int
        var color: Color {
            switch variant {
            case .success: return DT.emerald
            case .running: return DT.amber
            case .failed:  return DT.red
            case .skip:    return Color.primary.opacity(0.30)
            }
        }
    }

    private enum CIVariant { case success, running, failed, skip }

    private var ciStatusGroups: [CIGroup] {
        var success = 0, running = 0, failed = 0, skip = 0
        for c in currentChecks {
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
        for c in currentChecks {
            if c.isFailing { failed += 1 }
            else if c.isPending { running += 1 }
            else if c.isSuccess { success += 1 }
        }
        if failed > 0 { return "Needs a closer look" }
        if !currentChecks.isEmpty, success == currentChecks.count { return "All signals green" }
        if running > 0 { return "Checks still moving" }
        if pr.isDraft { return "Draft, still shaping up" }
        return "Waiting on the last signal"
    }

    private func baseBranch(for repo: Repo) -> String? {
        currentPR?.baseBranch ?? repo.defaultBranch
    }

    // MARK: - Loading

    private func reload() async {
        loadToken = UUID()
        let token = loadToken
        guard let repo = selected else {
            self.diff = .empty
            self.currentPR = nil
            self.currentChecks = []
            return
        }
        let wd = (try? await GitClient.workingTreeDiff(path: repo.path)) ?? .empty
        let allPRs = (try? await Database.shared.pullRequests(repoID: repo.id)) ?? []
        let pr = pickPR(for: repo.currentBranch, from: allPRs)
        let ck: [CICheck]
        if let pr {
            ck = (try? await Database.shared.checks(repoID: repo.id, prNumber: pr.number)) ?? []
        } else {
            ck = []
        }
        if token != loadToken { return }
        self.diff = wd
        self.currentPR = pr
        self.currentChecks = ck
    }

    private func pickPR(for branch: String?, from prs: [PullRequest]) -> PullRequest? {
        guard let branch, !branch.isEmpty else { return nil }
        let matches = prs.filter { $0.headBranch == branch }
        if let open = matches.first(where: { $0.state.uppercased() == "OPEN" }) { return open }
        return matches.max(by: { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) })
    }
}

// MARK: - Reusable atoms

private struct SCMIconButton: View {
    let icon: String
    let help: String
    let badge: Int
    let inFlight: Bool
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ZStack {
                    if inFlight {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 14, height: 14)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: DT.footerBtnHeight)
            .background(
                RoundedRectangle(cornerRadius: DT.radiusSm)
                    .fill(hovering && !disabled ? DT.surfaceHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.radiusSm)
                    .stroke(DT.border, lineWidth: 0.5)
            )
            .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if !disabled { hovering = $0 } }
        .disabled(disabled)
        .help(help)
        .pointingHand()
    }
}

private struct PulseIfRunning: ViewModifier {
    let active: Bool
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        Group {
            if active {
                content
                    .opacity(phase ? 0.55 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: phase)
                    .onAppear { phase = true }
            } else {
                content
            }
        }
    }
}

private extension View {
    func pointingHand() -> some View {
        self.onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
