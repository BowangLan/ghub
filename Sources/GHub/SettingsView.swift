import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            reposTab.tabItem { Label("Repositories", systemImage: "folder") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 380)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Sync") {
                Stepper(value: $state.refreshIntervalMinutes, in: 1...120) {
                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Text("\(state.refreshIntervalMinutes) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Button("Sync all now") {
                    Task { await SyncManager.shared.syncAll() }
                }
                .disabled(state.isSyncing)
            }
            Section("Tools") {
                LabeledContent("git", value: GitClient.bin)
                LabeledContent("gh", value: GHClient.bin ?? "Not installed (brew install gh)")
                if !state.ghAuthenticated && state.ghAvailable {
                    Text("Run `gh auth login` in Terminal to fetch PRs and CI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Storage") {
                Button("Reveal database in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Database.shared.fileURL])
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Repos

    private var reposTab: some View {
        Form {
            Section {
                if state.repos.isEmpty {
                    Text("No repositories. Add one to begin.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.repos) { repo in
                        RepoSettingsRow(repo: repo, onRemove: { confirmRemove(repo) })
                    }
                }
            } header: {
                HStack {
                    Text("Tracked Repositories")
                    Spacer()
                    Button("Add…") { addRepo() }
                }
            } footer: {
                Text("PR filters use GitHub search syntax. Changes are saved automatically and refetch pull requests after a short pause.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("GHub").font(.title2).bold()
            Text("A menu bar tracker for local Git repositories and their GitHub PRs.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a Git repository folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await state.addRepoFolder(url) }
            catch { presentError(error) }
        }
    }

    private func confirmRemove(_ repo: Repo) {
        let alert = NSAlert()
        alert.messageText = "Remove \(repo.name) from GHub?"
        alert.informativeText = "This only removes it from tracking. The repository on disk is untouched."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await state.removeRepo(id: repo.id) }
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "GHub"
        alert.informativeText = (error as NSError).localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct RepoSettingsRow: View {
    @EnvironmentObject var state: AppState
    let repo: Repo
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                        .font(.body.weight(.medium))
                    Text(repo.slug ?? "No GitHub remote detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sync Now") {
                    Task { await SyncManager.shared.syncRepo(id: repo.id) }
                }
                .disabled(state.isSyncing)
                Button("Remove", role: .destructive, action: onRemove)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Location")
                        .foregroundStyle(.secondary)
                    Text(repo.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Sync")
                        .foregroundStyle(.secondary)
                    Toggle("Include in automatic sync", isOn: Binding(
                        get: { repo.syncEnabled },
                        set: { newValue in
                            Task { await state.setSyncEnabled(repoID: repo.id, enabled: newValue) }
                        }
                    ))
                }
                GridRow {
                    Text("PR Filter")
                        .foregroundStyle(.secondary)
                    RepoPRFilterField(repo: repo)
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 6)
    }
}

private struct RepoPRFilterField: View {
    @EnvironmentObject var state: AppState
    let repo: Repo
    @State private var draft: String
    @State private var phase: SavePhase = .idle
    @State private var saveTask: Task<Void, Never>?

    init(repo: Repo) {
        self.repo = repo
        _draft = State(initialValue: repo.prFilterQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("GitHub search, e.g. author:@me label:bug", text: $draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .frame(minWidth: 300)
                .onChange(of: draft) { _, newValue in
                    scheduleSave(newValue)
                }
                .onChange(of: repo.prFilterQuery) { _, newValue in
                    if newValue != draft { draft = newValue }
                }
            HStack(spacing: 6) {
                if phase.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }
                Text(phase.message)
                    .font(.caption)
                    .foregroundStyle(phase == .failed ? .red : .secondary)
            }
            .frame(height: 16, alignment: .leading)
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    private func scheduleSave(_ query: String) {
        saveTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == repo.prFilterQuery {
            phase = .idle
            return
        }
        phase = .pending
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }
            await MainActor.run { phase = .saving }
            await state.setPRFilterQuery(repoID: repo.id, query: trimmed)
            if Task.isCancelled { return }
            await MainActor.run { phase = .refetching }
            await SyncManager.shared.syncRepo(id: repo.id)
            if Task.isCancelled { return }
            await MainActor.run { phase = .saved }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await MainActor.run { phase = .idle }
        }
    }
}

private enum SavePhase: Equatable {
    case idle
    case pending
    case saving
    case refetching
    case saved
    case failed

    var message: String {
        switch self {
        case .idle:
            return "Uses GitHub search syntax."
        case .pending:
            return "Waiting to save..."
        case .saving:
            return "Saving filter..."
        case .refetching:
            return "Refetching pull requests..."
        case .saved:
            return "Saved and updated."
        case .failed:
            return "Could not save filter."
        }
    }

    var showsProgress: Bool {
        self == .saving || self == .refetching
    }
}
