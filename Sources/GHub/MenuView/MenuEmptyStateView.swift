import SwiftUI

struct MenuEmptyStateView: View {
    var onAddRepo: () -> Void

    var body: some View {
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
            Button("Add Repository…", action: onAddRepo)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
