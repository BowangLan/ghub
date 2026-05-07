import AppKit
import SwiftUI

/// Always-on-top compact window showing the currently selected repo's status.
/// Visible across spaces and over fullscreen apps. Frame is autosaved.
@MainActor
final class MiniWindowController {
    static let shared = MiniWindowController()

    private var panel: NSPanel?

    private init() {}

    func show() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                styleMask: [
                    .titled, .closable, .resizable,
                    .utilityWindow, .nonactivatingPanel,
                    .fullSizeContentView,
                ],
                backing: .buffered,
                defer: false
            )
            p.title = "GHub"
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = true
            p.isMovableByWindowBackground = true
            p.isReleasedWhenClosed = false
            p.backgroundColor = .windowBackgroundColor
            p.setFrameAutosaveName("GHubMiniWindow")
            if p.frame.origin == .zero { p.center() }

            let host = NSHostingController(rootView: MiniRepoView()
                .environmentObject(AppState.shared))
            p.contentViewController = host
            p.contentMinSize = NSSize(width: 360, height: 400)
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func toggle() {
        if let p = panel, p.isVisible { p.orderOut(nil) } else { show() }
    }

    func isVisible() -> Bool { panel?.isVisible ?? false }
}
