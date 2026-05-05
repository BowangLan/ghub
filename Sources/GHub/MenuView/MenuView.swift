import SwiftUI
import AppKit

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            MenuHeaderView()
            Divider()
            if state.repos.isEmpty {
                MenuEmptyStateView(onAddRepo: addRepo)
            } else {
                repoList
            }
            Divider()
            MenuFooterView(onAddRepo: addRepo)
        }
        .frame(width: 380)
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
        .frame(maxHeight: 580)
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
