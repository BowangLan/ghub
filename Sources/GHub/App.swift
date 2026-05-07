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
        NSApp.setActivationPolicy(.accessory)
        MiniWindowController.shared.show()
        Task {
            AppState.shared.ghAuthenticated = await GHClient.authStatus()
            await SyncManager.shared.start()
            AppState.shared.ensureValidSelection()
            AppState.shared.applyWatcher()
        }
    }
}
