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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracked repositories")
                    .font(.headline)
                Spacer()
                Button("Add…") { addRepo() }
            }
            if state.repos.isEmpty {
                Text("No repositories. Add one to begin.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.repos) { repo in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.name).font(.body.weight(.medium))
                            Text(repo.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let slug = repo.slug {
                                Text(slug).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { repo.syncEnabled },
                            set: { newVal in
                                Task { await state.setSyncEnabled(repoID: repo.id, enabled: newVal) }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Include in sync")
                        Button {
                            Task { await SyncManager.shared.syncRepo(id: repo.id) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Sync now")
                        Button(role: .destructive) {
                            confirmRemove(repo)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
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
