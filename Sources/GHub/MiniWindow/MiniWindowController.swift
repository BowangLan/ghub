import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Always-on-top compact window showing the currently selected repo's status.
/// Visible across spaces and over fullscreen apps. Frame is autosaved.
@MainActor
final class MiniWindowController {
    static let shared = MiniWindowController()

    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var appliedMinified: Bool = false
    private var resizeAnimator: WindowResizeAnimator?

    private static let lastExpandedWKey = "MiniWindow.lastExpandedW"
    private static let lastExpandedHKey = "MiniWindow.lastExpandedH"

    private init() {}

    func show() {
        if panel == nil {
            let initialSize = MiniWindowMetrics.expandedDefaultSize
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = true
            p.isMovableByWindowBackground = true
            p.isReleasedWhenClosed = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.setFrameAutosaveName("GHubMiniWindow")
            if p.frame.origin == .zero { p.center() }

            let host = NSHostingController(rootView: MiniRepoView()
                .environmentObject(AppState.shared))
            host.view.wantsLayer = true
            // Layer-level mask so the rounded shape survives even if the
            // hosting view paints an opaque background underneath the SwiftUI
            // clip (otherwise the panel renders with square corners).
            if let layer = host.view.layer {
                layer.backgroundColor = NSColor.clear.cgColor
                layer.cornerRadius = MiniWindowMetrics.shellCornerRadius
                layer.cornerCurve = .continuous
                layer.masksToBounds = true
            }
            p.contentViewController = host
            p.contentMinSize = NSSize(width: MiniWindowMetrics.minWidth,
                                      height: MiniWindowMetrics.expandedContentMinHeight)
            panel = p

            subscribeToMode()

            // Reconcile to persisted minified state without animation.
            // If currently expanded, leave the autosaved frame alone.
            if AppState.shared.miniMinified {
                applyMode(true, animated: false)
            } else {
                appliedMinified = false
            }
        }
        panel?.orderFrontRegardless()
    }

    func toggle() {
        if let p = panel, p.isVisible { p.orderOut(nil) } else { show() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func isVisible() -> Bool { panel?.isVisible ?? false }

    // MARK: - Mode <-> window size

    private func subscribeToMode() {
        AppState.shared.$miniMinified
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] minified in
                Task { @MainActor in
                    await Task.yield()
                    self?.applyMode(minified, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    private func applyMode(_ minified: Bool, animated: Bool) {
        guard let p = panel else { return }

        let curFrame = p.frame
        let curContentSize = p.contentRect(forFrameRect: curFrame).size

        // Snapshot the current expanded size before collapsing.
        if minified, !appliedMinified {
            saveExpandedContentSize(curContentSize)
        }

        let targetContent: NSSize
        if minified {
            targetContent = compactContentSize(for: p, currentContentSize: curContentSize)
        } else {
            targetContent = loadExpandedContentSize()
                ?? NSSize(width: MiniWindowMetrics.expandedDefaultSize.width,
                          height: MiniWindowMetrics.expandedDefaultSize.height)
        }

        // Adjust min size to match the mode so the user can't manually shrink past it.
        p.contentMinSize = NSSize(
            width: MiniWindowMetrics.minWidth,
            height: minified ? targetContent.height
                             : MiniWindowMetrics.expandedContentMinHeight
        )

        let newFrameRect = p.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContent)
        )
        let topY = curFrame.maxY
        let newOrigin = NSPoint(x: curFrame.minX, y: topY - newFrameRect.size.height)
        let newFrame = NSRect(origin: newOrigin, size: newFrameRect.size)

        appliedMinified = minified

        resizeAnimator?.cancel()
        resizeAnimator = nil

        if animated {
            let anim = WindowResizeAnimator(
                window: p,
                from: curFrame,
                to: newFrame,
                duration: MiniWindowMetrics.modeAnimationDuration
            ) { [weak self] in
                self?.resizeAnimator = nil
            }
            resizeAnimator = anim
            anim.start()
        } else {
            p.setFrame(newFrame, display: true)
        }
    }

    private func compactContentSize(for panel: NSPanel, currentContentSize: NSSize) -> NSSize {
        let width = max(MiniWindowMetrics.minWidth, currentContentSize.width)
        guard let hostView = panel.contentViewController?.view else {
            return NSSize(width: width, height: currentContentSize.height)
        }

        hostView.setFrameSize(NSSize(width: width, height: hostView.frame.height))
        hostView.needsLayout = true
        hostView.layoutSubtreeIfNeeded()

        return NSSize(width: width, height: max(1, hostView.fittingSize.height))
    }

    // MARK: - Persisted last-expanded size

    private func loadExpandedContentSize() -> NSSize? {
        let w = UserDefaults.standard.double(forKey: Self.lastExpandedWKey)
        let h = UserDefaults.standard.double(forKey: Self.lastExpandedHKey)
        guard w >= MiniWindowMetrics.persistedExpandedMinWidth,
              h >= MiniWindowMetrics.persistedExpandedMinHeight
        else { return nil }
        return NSSize(width: w, height: h)
    }

    private func saveExpandedContentSize(_ size: NSSize) {
        UserDefaults.standard.set(size.width, forKey: Self.lastExpandedWKey)
        UserDefaults.standard.set(size.height, forKey: Self.lastExpandedHKey)
    }
}

/// Drives `NSWindow.setFrame` directly per-frame via a display link, so origin and
/// size update atomically each tick. Avoids the corner-anchor wobble that
/// `NSWindow.animator().setFrame` produces when origin and size are interpolated
/// with subtly different timing inside AppKit.
@MainActor
private final class WindowResizeAnimator: NSObject {
    private weak var window: NSWindow?
    private let fromFrame: NSRect
    private let toFrame: NSRect
    private let duration: CFTimeInterval
    private let onComplete: () -> Void

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    init(window: NSWindow,
         from: NSRect,
         to: NSRect,
         duration: CFTimeInterval,
         onComplete: @escaping () -> Void) {
        self.window = window
        self.fromFrame = from
        self.toFrame = to
        self.duration = duration
        self.onComplete = onComplete
    }

    func start() {
        guard let win = window else { onComplete(); return }
        startTime = CACurrentMediaTime()
        let screen = win.screen ?? NSScreen.main
        guard let link = screen?.displayLink(target: self, selector: #selector(tick(_:))) else {
            win.setFrame(toFrame, display: true)
            onComplete()
            return
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let win = window else {
            link.invalidate()
            displayLink = nil
            return
        }
        let now = CACurrentMediaTime()
        let raw = duration > 0 ? (now - startTime) / duration : 1
        let t = min(max(raw, 0), 1)
        let eased = Self.easeInOut(t)

        let cur = NSRect(
            x: fromFrame.minX + (toFrame.minX - fromFrame.minX) * eased,
            y: fromFrame.minY + (toFrame.minY - fromFrame.minY) * eased,
            width: fromFrame.width + (toFrame.width - fromFrame.width) * eased,
            height: fromFrame.height + (toFrame.height - fromFrame.height) * eased
        )
        win.setFrame(cur, display: true)

        if t >= 1 {
            link.invalidate()
            displayLink = nil
            onComplete()
        }
    }

    /// Cubic ease-in-out — visually matches SwiftUI's `.easeInOut` close enough at
    /// sub-second durations.
    private static func easeInOut(_ t: Double) -> Double {
        if t < 0.5 { return 4 * t * t * t }
        let u = -2 * t + 2
        return 1 - (u * u * u) / 2
    }
}
