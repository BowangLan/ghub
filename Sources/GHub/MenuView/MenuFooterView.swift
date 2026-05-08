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
            if state.ciMonitoringActive {
                CIMonitorBadge(count: state.ciMonitoringRepoIDs.count)
            }
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

private struct CIMonitorBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .semibold))
            Text("Watching \(count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.secondary.opacity(0.12))
        )
        .help("Auto-monitoring \(count) repo\(count == 1 ? "" : "s") with running checks")
    }
}
