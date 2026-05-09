import SwiftUI
import AppKit

struct CommitPopover: View {
    let repo: Repo
    let stagedCount: Int
    @Binding var message: String
    @Binding var inFlight: Bool
    @Binding var error: String?
    @Binding var isPresented: Bool
    let onAfterCommit: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                BranchReferenceView(
                    name: repo.currentBranch ?? "—",
                    style: .compact,
                    muted: true
                )
                Spacer()
                Text("\(stagedCount) staged")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            TextField("Message (Cmd+Enter to commit)",
                      text: $message,
                      axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(DT.Color.surface, in: RoundedRectangle(cornerRadius: DT.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.sm)
                        .stroke(DT.Color.border, lineWidth: 0.5)
                )
                .frame(width: 320)
                .onSubmit { Task { await runCommit() } }
            if let err = error {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(DT.Color.red)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            HStack(spacing: 6) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await runCommit() }
                } label: {
                    HStack(spacing: 6) {
                        if inFlight { ProgressView().controlSize(.small).scaleEffect(0.7) }
                        Text("Commit")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || inFlight
                          || stagedCount == 0)
            }
        }
        .padding(14)
    }

    private func runCommit() async {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !inFlight else { return }
        inFlight = true
        error = nil
        defer { inFlight = false }
        do {
            try await GitClient.commit(path: repo.path, message: msg)
            message = ""
            isPresented = false
            await SyncManager.shared.syncRepo(id: repo.id)
            await onAfterCommit()
        } catch let e {
            error = friendlyShellError(e)
        }
    }

    private func friendlyShellError(_ err: Error) -> String {
        let raw = String(describing: err)
        return raw.replacingOccurrences(of: "ShellError.", with: "")
    }
}
