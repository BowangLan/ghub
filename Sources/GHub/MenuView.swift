import SwiftUI
import AppKit

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.repos.isEmpty {
                emptyState
            } else {
                repoList
            }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.menuBarSymbol)
                .foregroundStyle(state.totalFailing > 0 ? Color.red : .primary)
            Text("GHub")
                .font(.headline)
            Spacer()
            if !state.ghAvailable {
                Label("gh missing", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !state.ghAuthenticated {
                Label("gh not logged in", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if state.isSyncing {
                ProgressView().controlSize(.small)
            } else if let last = state.lastSyncedAt {
                Text(last, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await SyncManager.shared.syncAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh all")
            .disabled(state.isSyncing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No repositories tracked")
                .font(.subheadline)
            Text("Add a local Git repository to start tracking commits, branches, PRs, and CI.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("Add Repository…") { addRepo() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - List

    private var repoList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.repos) { repo in
                    RepoRow(
                        repo: repo,
                        isExpanded: expanded.contains(repo.id),
                        toggle: {
                            if expanded.contains(repo.id) { expanded.remove(repo.id) }
                            else { expanded.insert(repo.id) }
                        }
                    )
                    Divider()
                }
            }
        }
        .frame(maxHeight: 480)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Add Repo…") { addRepo() }
            Button("Refresh") { Task { await SyncManager.shared.syncAll() } }
                .disabled(state.isSyncing)
            Spacer()
            SettingsLink { Text("Settings…") }
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.callout)
    }

    // MARK: - Actions

    private func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a Git repository folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await state.addRepoFolder(url) }
            catch { presentError(error) }
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "GHub"
        alert.informativeText = (error as NSError).localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Row

struct RepoRow: View {
    let repo: Repo
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var branches: [Branch] = []
    @State private var prs: [PullRequest] = []
    @State private var commits: [Commit] = []
    @State private var checksByPR: [Int: [CICheck]] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    statusDot
                    VStack(alignment: .leading, spacing: 1) {
                        Text(repo.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(repo.currentBranch ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    badges
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedBody
                    .padding(.leading, 22)
                    .padding(.top, 4)
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
        VStack(alignment: .leading, spacing: 10) {
            if let slug = repo.slug {
                HStack(spacing: 4) {
                    Image(systemName: "link").font(.caption2)
                    Text(slug)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No GitHub remote detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !branches.isEmpty {
                section("Branches") {
                    ForEach(branches.prefix(8)) { b in
                        HStack {
                            Image(systemName: b.isCurrent ? "arrow.right.circle.fill" : "circle")
                                .foregroundStyle(b.isCurrent ? Color.accentColor : .secondary)
                                .font(.caption)
                                .frame(width: 14)
                            Text(b.name)
                                .font(.caption)
                                .lineLimit(1)
                            if b.ahead > 0 {
                                Text("⇡\(b.ahead)").font(.caption2).foregroundStyle(.secondary)
                            }
                            if b.behind > 0 {
                                Text("⇣\(b.behind)").font(.caption2).foregroundStyle(.secondary)
                            }
                            if b.upstream == nil {
                                Text("no upstream")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if let d = b.lastCommitAt {
                                Text(d, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(pr.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                if pr.isDraft {
                                    Text("draft")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .background(Color.secondary.opacity(0.15), in: Capsule())
                                }
                                Spacer()
                                Text(pr.headBranch)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if repo.slug != nil {
                Text("No open pull requests")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !commits.isEmpty {
                section("Recent commits") {
                    ForEach(commits.prefix(5)) { c in
                        HStack(alignment: .top, spacing: 8) {
                            Text(c.shortSHA)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.message)
                                    .font(.caption)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(c.author)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let d = c.date {
                                        Text("·").font(.caption2).foregroundStyle(.secondary)
                                        Text(d, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
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
            .font(.caption)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
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
        return Image(systemName: symbol).foregroundStyle(color).font(.caption)
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
    }
}
