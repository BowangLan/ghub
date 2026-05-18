import SwiftUI
import AppKit

@main
struct GHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
                .frame(minWidth: 540, minHeight: 380)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MiniWindowController.shared.show()
        Task {
            await SyncManager.shared.start()
            AppState.shared.ensureValidSelection()
            AppState.shared.applyWatcher()
            if AppState.shared.ciMonitorEnabled {
                CIMonitor.shared.start()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MiniWindowController.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SyncManager.shared.stop()
        CIMonitor.shared.stop()
        RepoWatcher.shared.stop()
    }
}
