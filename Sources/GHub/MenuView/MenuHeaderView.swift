import SwiftUI

struct MenuHeaderView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
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
            } else {
                SyncedLabel(date: state.lastSyncedAt)
            }
            Button {
                Task { await SyncManager.shared.syncAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh all")
            .disabled(state.isSyncing)
            Button {
                MiniWindowController.shared.hide()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close mini window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
