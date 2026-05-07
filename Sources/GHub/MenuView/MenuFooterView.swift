import SwiftUI
import AppKit

struct MenuFooterView: View {
    @EnvironmentObject var state: AppState
    var onAddRepo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button("Add Repo…", action: onAddRepo)
            Button("Refresh") { Task { await SyncManager.shared.syncAll() } }
                .disabled(state.isSyncing)
            Button("Mini") { MiniWindowController.shared.toggle() }
            Spacer()
            SettingsLink { Text("Settings…") }
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.callout)
    }
}
