import SwiftUI

struct GroupWorkflowBar: View {
    let group: GitClient.FileCommitGroup
    let isHidden: Bool
    @Binding var branch: String
    @Binding var createBranch: Bool
    @Binding var message: String
    let isolationWarning: String?
    let operationInFlight: Bool
    let onToggleStash: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DiffGroupHeader(group: group, isHidden: isHidden)
                Text("\(group.fileCount) file\(group.fileCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onToggleStash()
                } label: {
                    Label(isHidden ? "Restore" : "Stash", systemImage: isHidden ? "tray.and.arrow.up" : "archivebox")
                }
                .disabled(operationInFlight || isolationWarning != nil)
                Button {
                    onCommit()
                } label: {
                    Label("Commit group", systemImage: "arrow.triangle.branch")
                }
                .disabled(operationInFlight || isHidden || isolationWarning != nil || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let isolationWarning {
                Text(isolationWarning)
                    .font(.caption)
                    .foregroundStyle(DT.Color.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TextField("Commit message", text: $message)
                    .textFieldStyle(.roundedBorder)
                TextField("Branch (optional)", text: $branch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                Toggle("New", isOn: $createBranch)
                    .toggleStyle(.checkbox)
                    .help("Create the target branch before committing")
            }
            .disabled(operationInFlight || isHidden)
        }
        .padding(12)
        .background(DT.Color.surface)
    }
}
