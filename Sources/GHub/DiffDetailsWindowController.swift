import AppKit
import SwiftUI

@MainActor
final class DiffDetailsWindowController: NSObject, NSWindowDelegate {
    static let shared = DiffDetailsWindowController()

    private var panel: NSPanel?

    func show(repo: Repo) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            p.titleVisibility = .visible
            p.isReleasedWhenClosed = false
            p.isFloatingPanel = true
            p.collectionBehavior = [.fullScreenAuxiliary]
            p.minSize = NSSize(width: 740, height: 460)
            p.delegate = self
            p.center()
            panel = p
        }

        panel?.title = "Diff Details - \(repo.name)"
        panel?.contentViewController = NSHostingController(rootView: DiffDetailsView(repo: repo))
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
