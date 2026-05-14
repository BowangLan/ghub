import SwiftUI

struct DiffDetailsPane: View {
    let selectedFile: GitClient.FileDiff?
    let selectedGroup: GitClient.FileCommitGroup?
    let isGroupHidden: Bool
    let operationError: String?
    let operationInFlight: Bool
    @Binding var branch: String
    @Binding var createBranch: Bool
    @Binding var message: String
    let isolationWarning: String?
    let onToggleStash: () -> Void
    let onCommit: () -> Void

    var body: some View {
        if let selectedFile {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedGroup {
                    GroupWorkflowBar(
                        group: selectedGroup,
                        isHidden: isGroupHidden,
                        branch: $branch,
                        createBranch: $createBranch,
                        message: $message,
                        isolationWarning: isolationWarning,
                        operationInFlight: operationInFlight,
                        onToggleStash: onToggleStash,
                        onCommit: onCommit
                    )
                    Divider()
                }
                DiffFileHeader(file: selectedFile)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    DiffTextView(diff: selectedFile.diff)
                }
                .background(Color(nsColor: .textBackgroundColor))
                if let operationError {
                    Divider()
                    Text(operationError)
                        .font(.caption)
                        .foregroundStyle(DT.Color.red)
                        .lineLimit(3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct DiffFileHeader: View {
    let file: GitClient.FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DiffScopePill(scope: file.scope)
                Text(file.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(file.path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            if let oldPath = file.oldPath {
                Text("from \(oldPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
    }
}
