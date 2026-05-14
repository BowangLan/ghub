import SwiftUI

struct DiffDetailsView: View {
    let repo: Repo

    @State private var detail: GitClient.DetailedWorkingTreeDiff = .empty
    @State private var selectedID: GitClient.FileDiff.ID?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var operationError: String?
    @State private var operationInFlight = false
    @State private var hiddenGroups: [String: HiddenDiffGroup] = [:]
    @State private var groupRecords: [DiffFileGroupRecord] = []
    @State private var fileAssignments: [String: String] = [:]
    @State private var branchByGroup: [String: String] = [:]
    @State private var createBranchByGroup: [String: Bool] = [:]
    @State private var messageByGroup: [String: String] = [:]

    private var allGroups: [GitClient.FileCommitGroup] {
        buildFileCommitGroups(
            files: detail.files,
            records: groupRecords,
            assignments: fileAssignments,
            hiddenGroups: hiddenGroups
        )
    }

    private var selectedFile: GitClient.FileDiff? {
        allGroups.flatMap(\.files).first { $0.id == selectedID } ?? allGroups.flatMap(\.files).first
    }

    private var selectedGroup: GitClient.FileCommitGroup? {
        guard let selectedFile else { return allGroups.first }
        return allGroups.first { group in
            group.files.contains { $0.id == selectedFile.id }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DiffDetailsToolbar(repo: repo, isLoading: isLoading) {
                Task { await load() }
            }
            Divider()
            content
        }
        .frame(minWidth: 740, minHeight: 460)
        .task(id: repo.id) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView(
                "Could not load diffs",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading && detail.isEmpty {
            ProgressView("Loading diffs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if detail.isEmpty && hiddenGroups.isEmpty {
            ContentUnavailableView(
                "Working tree clean",
                systemImage: "checkmark.circle",
                description: Text("There are no staged, unstaged, or untracked file diffs.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                DiffFileSidebar(
                    groups: allGroups,
                    hiddenGroupIDs: Set(hiddenGroups.keys),
                    selectedID: $selectedID,
                    onCreateGroup: { Task { await createGroup() } },
                    onMoveFile: { file, group in Task { await move(file: file, to: group) } }
                )
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 430)

                DiffDetailsPane(
                    selectedFile: selectedFile,
                    selectedGroup: selectedGroup,
                    isGroupHidden: selectedGroup.map { hiddenGroups[$0.id] != nil } ?? false,
                    operationError: operationError,
                    operationInFlight: operationInFlight,
                    branch: selectedGroupBranchBinding(defaultValue: selectedGroup?.branch ?? ""),
                    createBranch: selectedGroupBinding(in: $createBranchByGroup, defaultValue: false),
                    message: selectedGroupBinding(
                        in: $messageByGroup,
                        defaultValue: selectedGroup.map(defaultCommitMessage(for:)) ?? ""
                    ),
                    isolationWarning: selectedGroup.flatMap(isolationWarning(for:)),
                    onToggleStash: {
                        if let selectedGroup {
                            Task { await toggleStash(selectedGroup) }
                        }
                    },
                    onCommit: {
                        if let selectedGroup {
                            Task { await commitGroup(selectedGroup) }
                        }
                    }
                )
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await GitClient.detailedWorkingTreeDiff(path: repo.path)
            let records = try await Database.shared.diffFileGroups(repoID: repo.id)
            let assignments = try await Database.shared.diffFileGroupAssignments(repoID: repo.id)
            detail = loaded
            groupRecords = records
            fileAssignments = assignments
            if let selectedID, loaded.files.contains(where: { $0.id == selectedID }) {
                self.selectedID = selectedID
            } else {
                self.selectedID = allGroups.flatMap(\.files).first?.id
            }
        } catch {
            errorMessage = friendlyDiffDetailsError(error)
            detail = .empty
            selectedID = nil
        }
    }

    private func createGroup() async {
        do {
            let index = groupRecords.count + 1
            let record = try await Database.shared.createDiffFileGroup(repoID: repo.id, name: "Group \(index)")
            groupRecords.append(record)
        } catch {
            operationError = friendlyDiffDetailsError(error)
        }
    }

    private func move(file: GitClient.FileDiff, to group: GitClient.FileCommitGroup) async {
        let groupID = group.isDefault ? nil : group.id
        do {
            try await Database.shared.assignDiffFile(repoID: repo.id, fileKey: diffFileKey(file), to: groupID)
            if let groupID {
                fileAssignments[diffFileKey(file)] = groupID
            } else {
                fileAssignments.removeValue(forKey: diffFileKey(file))
            }
            selectedID = file.id
        } catch {
            operationError = friendlyDiffDetailsError(error)
        }
    }

    private func toggleStash(_ group: GitClient.FileCommitGroup) async {
        guard !operationInFlight else { return }
        operationInFlight = true
        operationError = nil
        defer { operationInFlight = false }
        do {
            if let hidden = hiddenGroups[group.id] {
                try await GitClient.popStash(path: repo.path, id: hidden.stash.id)
                hiddenGroups[group.id] = nil
            } else if let stash = try await GitClient.stashGroup(path: repo.path, group: group) {
                hiddenGroups[group.id] = HiddenDiffGroup(group: group, stash: stash)
            }
            await load()
        } catch {
            operationError = friendlyDiffDetailsError(error)
        }
    }

    private func commitGroup(_ group: GitClient.FileCommitGroup) async {
        guard !operationInFlight else { return }
        let message = (messageByGroup[group.id] ?? defaultCommitMessage(for: group))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            operationError = "Commit message is required."
            return
        }
        operationInFlight = true
        operationError = nil
        defer { operationInFlight = false }
        do {
            if !group.isDefault {
                try await Database.shared.updateDiffFileGroupBranch(id: group.id, branch: branchByGroup[group.id])
            }
            try await GitClient.commitGroupToBranch(
                path: repo.path,
                group: group,
                branch: branchByGroup[group.id],
                createBranch: createBranchByGroup[group.id] ?? false,
                message: message
            )
            hiddenGroups[group.id] = nil
            await SyncManager.shared.syncRepo(id: repo.id)
            await load()
        } catch {
            operationError = friendlyDiffDetailsError(error)
        }
    }

    private func selectedGroupBinding<T>(
        in storage: Binding<[String: T]>,
        defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: {
                guard let selectedGroup else { return defaultValue }
                return storage.wrappedValue[selectedGroup.id] ?? defaultValue
            },
            set: {
                guard let selectedGroup else { return }
                storage.wrappedValue[selectedGroup.id] = $0
            }
        )
    }

    private func selectedGroupBranchBinding(defaultValue: String) -> Binding<String> {
        Binding(
            get: {
                guard let selectedGroup else { return defaultValue }
                return branchByGroup[selectedGroup.id] ?? selectedGroup.branch ?? defaultValue
            },
            set: { newValue in
                guard let selectedGroup else { return }
                branchByGroup[selectedGroup.id] = newValue
                guard !selectedGroup.isDefault else { return }
                Task {
                    try? await Database.shared.updateDiffFileGroupBranch(id: selectedGroup.id, branch: newValue)
                }
                if let index = groupRecords.firstIndex(where: { $0.id == selectedGroup.id }) {
                    groupRecords[index].branch = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
                }
            }
        )
    }

    private func defaultCommitMessage(for group: GitClient.FileCommitGroup) -> String {
        "Commit \(group.title.lowercased()) changes"
    }

    private func isolationWarning(for group: GitClient.FileCommitGroup) -> String? {
        let scopes = Set(group.files.map(\.scope))
        if scopes.count > 1 {
            return "This group mixes staged, unstaged, and untracked files. Git stash can only isolate one state at a time; split the files into separate groups before stashing or committing."
        }
        guard scopes.first == .staged else { return nil }
        let unstagedPaths = Set(detail.files.filter { $0.scope == .unstaged }.map(\.path))
        if group.paths.contains(where: { unstagedPaths.contains($0) }) {
            return "Some staged files also have unstaged changes. Git cannot safely toggle or commit just the staged copy for those paths through stash."
        }
        return nil
    }
}
