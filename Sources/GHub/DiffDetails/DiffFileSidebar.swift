import SwiftUI
import UniformTypeIdentifiers

struct DiffFileSidebar: View {
    let groups: [GitClient.FileCommitGroup]
    let hiddenGroupIDs: Set<String>
    @Binding var selectedID: GitClient.FileDiff.ID?
    let onCreateGroup: () -> Void
    let onMoveFile: (GitClient.FileDiff, GitClient.FileCommitGroup) -> Void

    private var filesByID: [GitClient.FileDiff.ID: GitClient.FileDiff] {
        Dictionary(uniqueKeysWithValues: groups.flatMap(\.files).map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("File Groups")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onCreateGroup) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Create file group")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $selectedID) {
                ForEach(groups) { group in
                    Section {
                        if group.files.isEmpty {
                            Text("Drop files here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(group.files) { file in
                                DiffFileRow(file: file, isHidden: hiddenGroupIDs.contains(group.id))
                                    .tag(file.id)
                                    .onDrag {
                                        NSItemProvider(object: file.id as NSString)
                                    }
                            }
                        }
                    } header: {
                        DiffGroupHeader(group: group, isHidden: hiddenGroupIDs.contains(group.id))
                            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                                handleDrop(providers, into: group)
                            }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], into group: GitClient.FileCommitGroup) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let id: String?
            if let data = item as? Data {
                id = String(data: data, encoding: .utf8)
            } else {
                id = item as? String
            }
            guard let id, let file = filesByID[id] else { return }
            Task { @MainActor in
                onMoveFile(file, group)
            }
        }
        return true
    }
}

struct DiffGroupHeader: View {
    let group: GitClient.FileCommitGroup
    let isHidden: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.isDefault ? "tray" : "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(group.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(group.fileCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            if isHidden {
                Image(systemName: "archivebox.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}
