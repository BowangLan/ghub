import SwiftUI
import AppKit

struct RepoRow: View {
    let repo: Repo
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var branches: [Branch] = []
    @State private var prs: [PullRequest] = []
    @State private var commits: [Commit] = []
    @State private var checksByPR: [Int: [CICheck]] = [:]
    @State private var isSwitchingBranch = false
    @State private var workingTreeDiff: GitClient.WorkingTreeDiff = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    statusDot
                    Text(repo.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    badges
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedBody
                    .padding(.leading, 22)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: "\(repo.id)-\(isExpanded)") {
            if isExpanded { await loadDetails() }
        }
    }

    private var statusDot: some View {
        let color: Color = {
            if repo.failingCheckCount > 0 { return .red }
            if repo.isDirty { return .orange }
            if repo.ahead > 0 || repo.behind > 0 { return .yellow }
            return .green
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 8) {
            if repo.ahead > 0 {
                Label("\(repo.ahead)", systemImage: "arrow.up")
                    .labelStyle(.titleAndIcon)
            }
            if repo.behind > 0 {
                Label("\(repo.behind)", systemImage: "arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            if repo.isDirty {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.orange)
            }
            if repo.openPRCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.pull")
                    Text("\(repo.openPRCount)")
                }
            }
            if repo.failingCheckCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text("\(repo.failingCheckCount)").foregroundStyle(.red)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let slug = repo.slug {
                HStack(spacing: 4) {
                    Image(systemName: "link").font(.caption)
                    Text(slug)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No GitHub remote detected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !branches.isEmpty {
                section("Branches") {
                    ForEach(branches.prefix(8)) { b in
                        if b.isCurrent {
                            branchRowStack(b)
                                .padding(.vertical, 2)
                        } else {
                            Button {
                                Task { @MainActor in
                                    await switchToBranch(b)
                                }
                            } label: {
                                branchRowStack(b)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSwitchingBranch)
                        }
                    }
                }
            }

            if !prs.isEmpty {
                section("Pull Requests") {
                    ForEach(prs.prefix(8)) { pr in
                        Button {
                            if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack(spacing: 6) {
                                checkBadge(for: pr)
                                Text("#\(pr.number)")
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(pr.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if pr.isDraft {
                                    Text("draft")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                }
                                Spacer()
                                Text(pr.headBranch)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if repo.slug != nil {
                Text("No open pull requests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !commits.isEmpty {
                section("Recent commits") {
                    ForEach(commits.prefix(5)) { c in
                        HStack(alignment: .top, spacing: 8) {
                            Text(c.shortSHA)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.message)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(c.author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let d = c.date {
                                        Text("·").font(.caption).foregroundStyle(.secondary)
                                        Text(d, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            HStack(spacing: 14) {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo.path)])
                }
                if let slug = repo.slug, let url = URL(string: "https://github.com/\(slug)") {
                    Button("GitHub") { NSWorkspace.shared.open(url) }
                }
                Button("Sync now") {
                    Task { await SyncManager.shared.syncRepo(id: repo.id) }
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    @ViewBuilder
    private func branchRowStack(_ b: Branch) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: b.isCurrent ? "arrow.right.circle.fill" : "circle")
                    .foregroundStyle(b.isCurrent ? Color.accentColor : .secondary)
                    .font(.subheadline)
                    .frame(width: 16)
                Text(b.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if b.ahead > 0 {
                    Text("⇡\(b.ahead)").font(.caption).foregroundStyle(.secondary)
                }
                if b.behind > 0 {
                    Text("⇣\(b.behind)").font(.caption).foregroundStyle(.secondary)
                }
                if b.upstream == nil {
                    Text("no upstream")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let d = b.lastCommitAt {
                    Text(d, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if b.isCurrent {
                workingTreeDiffSubtitle(
                    diff: workingTreeDiff,
                    untracked: repo.untrackedCount,
                    tipSHA: b.shortHeadSHA
                )
                .padding(.leading, 24)
            }
        }
    }

    @ViewBuilder
    private func workingTreeDiffSubtitle(diff: GitClient.WorkingTreeDiff, untracked: Int, tipSHA: String) -> some View {
        let st = diff.staged
        let us = diff.unstaged
        let hasDelta = st.hasDelta || us.hasDelta
        let clean = !hasDelta && untracked == 0

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(tipSHA)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            if clean {
                Text("·")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.quaternary)
                Text("Working tree clean")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                if st.hasDelta {
                    Text("·")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                    diffStatLine(label: "Staged", stat: st)
                }
                if us.hasDelta {
                    Text("·")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                    diffStatLine(label: "Unstaged", stat: us)
                }
                if untracked > 0 {
                    Text("·")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.quaternary)
                    Text(untracked == 1 ? "1 untracked" : "\(untracked) untracked")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func diffStatLine(label: String, stat: GitClient.DiffShortstat) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if stat.insertions > 0 {
                Text("+\(stat.insertions)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(red: 0.13, green: 0.58, blue: 0.36))
            }
            if stat.deletions > 0 {
                Text("−\(stat.deletions)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(red: 0.83, green: 0.22, blue: 0.24))
            }
            if stat.filesChanged > 0, stat.insertions == 0, stat.deletions == 0 {
                Text("\(stat.filesChanged) file\(stat.filesChanged == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkBadge(for pr: PullRequest) -> some View {
        let checks = checksByPR[pr.number] ?? []
        let symbol: String
        let color: Color
        if checks.contains(where: { $0.isFailing }) {
            symbol = "xmark.octagon.fill"; color = .red
        } else if checks.contains(where: { $0.isPending }) {
            symbol = "clock"; color = .yellow
        } else if !checks.isEmpty {
            symbol = "checkmark.circle.fill"; color = .green
        } else {
            symbol = "circle.dotted"; color = .secondary
        }
        return Image(systemName: symbol).foregroundStyle(color).font(.subheadline)
    }

    private func loadDetails() async {
        let id = repo.id
        let br = (try? await Database.shared.branches(repoID: id)) ?? []
        let pr = (try? await Database.shared.pullRequests(repoID: id)) ?? []
        let cm = (try? await Database.shared.commits(repoID: id, limit: 10)) ?? []
        var byPR: [Int: [CICheck]] = [:]
        for p in pr {
            byPR[p.number] = (try? await Database.shared.checks(repoID: id, prNumber: p.number)) ?? []
        }
        self.branches = br
        self.prs = pr
        self.commits = cm
        self.checksByPR = byPR
        self.workingTreeDiff = (try? await GitClient.workingTreeDiff(path: repo.path)) ?? .empty
    }

    @MainActor
    private func switchToBranch(_ branch: Branch) async {
        guard !branch.isCurrent else { return }
        isSwitchingBranch = true
        defer { isSwitchingBranch = false }
        do {
            try await GitClient.checkout(path: repo.path, branch: branch.name)
            await SyncManager.shared.syncRepo(id: repo.id)
            await loadDetails()
        } catch {
            let message: String
            if let shell = error as? ShellError {
                message = shell.description
            } else {
                message = error.localizedDescription
            }
            presentBranchSwitchError(message)
        }
    }

    private func presentBranchSwitchError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not switch branch"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
