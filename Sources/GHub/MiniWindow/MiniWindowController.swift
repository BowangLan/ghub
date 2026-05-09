import AppKit
import Combine
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
    private var peekAnimator: WindowResizeAnimator?
    private var peekAnimationGeneration = 0
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var dragStartFrame: NSRect?
    /// Bottom anchor preserved across resting <-> peeked transitions so the
    /// badge grows upward while the bottom edge stays pinned.
    private var lastDockedMinY: CGFloat?

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
                .environmentObject(AppState.shared)
                .environmentObject(MiniWindowDockState.shared))
            host.view.wantsLayer = true
            // Layer-level mask so the rounded shape survives even if the
            // hosting view paints an opaque background underneath the SwiftUI
            // clip (otherwise the panel renders with square corners).
            // `maskedCorners` is updated on dock-state changes so that, when
            // the badge is snapped to a screen edge, the dock-side corners
            // stay flat (only outer corners round).
            if let layer = host.view.layer {
                layer.backgroundColor = NSColor.clear.cgColor
                layer.cornerRadius = MiniWindowMetrics.shellCornerRadius
                layer.cornerCurve = .continuous
                layer.masksToBounds = true
                layer.maskedCorners = [
                    .layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner
                ]
            }
            p.contentViewController = host
            p.contentMinSize = NSSize(width: MiniWindowMetrics.minWidth,
                                      height: MiniWindowMetrics.expandedContentMinHeight)
            panel = p

            installDragMonitors()
            subscribeToMode()
            subscribeToDockState()

            // Reconcile to persisted minified state without animation.
            // If currently expanded, leave the autosaved frame alone.
            if AppState.shared.miniMinified {
                applyMode(true, animated: false)
            } else {
                appliedMinified = false
            }
            detectInitialDockState()
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

    func shouldSuppressDockHoverExit() -> Bool {
        guard AppState.shared.miniMinified,
              MiniWindowDockState.shared.isDocked,
              peekAnimator != nil,
              let p = panel
        else { return false }

        let current = p.frame
        let resting = restingDockedFrame(reference: current)
        let peeked = peekedFrame(restingFrame: resting)
        let transitionEnvelope = current
            .union(resting)
            .union(peeked)
            .insetBy(dx: -2, dy: -2)

        return transitionEnvelope.contains(NSEvent.mouseLocation)
    }

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

        // Leaving minified mode: cancel any peek so the resize animation
        // doesn't fight the hover-driven peek animation mid-flight.
        if !minified {
            MiniWindowDockState.shared.hovered = false
        }

        let dockEdge = MiniWindowDockState.shared.edge
        let isDocked = dockEdge != .none

        let newFrame = targetFrame(
            forMinified: minified,
            isDocked: isDocked,
            dockEdge: dockEdge,
            curFrame: curFrame,
            curContentSize: curContentSize,
            for: p
        )

        // Adjust min size to match the mode. Docked-resting bypasses the
        // global minWidth so the badge can be much narrower than the
        // floating-minified panel.
        if minified, isDocked {
            p.contentMinSize = NSSize(width: newFrame.width, height: newFrame.height)
        } else {
            p.contentMinSize = NSSize(
                width: MiniWindowMetrics.minWidth,
                height: minified ? newFrame.height
                                 : MiniWindowMetrics.expandedContentMinHeight
            )
        }

        if minified, isDocked {
            lastDockedMinY = newFrame.minY
        }

        appliedMinified = minified

        resizeAnimator?.cancel()
        resizeAnimator = nil
        peekAnimator?.cancel()
        peekAnimator = nil
        peekAnimationGeneration += 1

        if animated {
            let anim = WindowResizeAnimator(
                window: p,
                from: curFrame,
                to: newFrame,
                duration: MiniWindowMetrics.modeAnimationDuration
            ) { [weak self] in
                self?.resizeAnimator = nil
                Task { @MainActor in self?.updateMaskedCorners() }
            }
            resizeAnimator = anim
            anim.start()
        } else {
            p.setFrame(newFrame, display: true)
            updateMaskedCorners()
        }
    }

    /// Compute the target frame for a mode transition, accounting for dock
    /// state so docked-right windows anchor to the right edge during expand,
    /// and docked-minified targets the badge dimensions.
    private func targetFrame(
        forMinified minified: Bool,
        isDocked: Bool,
        dockEdge: MiniWindowDockEdge,
        curFrame: NSRect,
        curContentSize: NSSize,
        for panel: NSPanel
    ) -> NSRect {
        if minified, isDocked {
            return restingDockedFrame(reference: curFrame)
        }

        let targetContent: NSSize
        if minified {
            targetContent = compactContentSize(for: panel, currentContentSize: curContentSize)
        } else {
            targetContent = loadExpandedContentSize()
                ?? NSSize(width: MiniWindowMetrics.expandedDefaultSize.width,
                          height: MiniWindowMetrics.expandedDefaultSize.height)
        }
        let frameRect = panel.frameRect(forContentRect: NSRect(origin: .zero, size: targetContent))
        let topY = curFrame.maxY
        let xAnchor: CGFloat
        if isDocked, dockEdge == .right {
            xAnchor = curFrame.maxX - frameRect.width
        } else {
            xAnchor = curFrame.minX
        }
        return NSRect(
            x: xAnchor,
            y: topY - frameRect.height,
            width: frameRect.width,
            height: frameRect.height
        )
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

    // MARK: - Dock state (badge / peek)

    private func subscribeToDockState() {
        MiniWindowDockState.shared.$edge
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateMaskedCorners() }
            }
            .store(in: &cancellables)

        MiniWindowDockState.shared.$hovered
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] hovered in
                Task { @MainActor in
                    self?.applyHoverPeek(hovered: hovered, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    private func detectInitialDockState() {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        guard AppState.shared.miniMinified else { return }
        let visible = screen.visibleFrame
        let cur = p.frame
        let tol: CGFloat = 2
        let edge: MiniWindowDockEdge
        if abs(cur.minX - visible.minX) <= tol {
            edge = .left
        } else if abs(cur.maxX - visible.maxX) <= tol {
            edge = .right
        } else {
            edge = .none
        }
        if edge != .none {
            lastDockedMinY = cur.minY
            MiniWindowDockState.shared.edge = edge
            // Snap to badge dimensions if the autosaved frame is wider than
            // the badge — otherwise leave it alone.
            if cur.width > MiniWindowMetrics.dockedRestingWidth + 2 {
                applyMode(true, animated: false)
            } else {
                updateMaskedCorners()
            }
        }
    }

    private func updateMaskedCorners() {
        guard let host = panel?.contentViewController?.view, let layer = host.layer else { return }
        let dockedBadge = MiniWindowDockState.shared.isDocked && AppState.shared.miniMinified
        if dockedBadge {
            switch MiniWindowDockState.shared.edge {
            case .left:
                layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            case .right:
                layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            case .none:
                break
            }
        } else {
            layer.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
        }
    }

    private func applyHoverPeek(hovered: Bool, animated: Bool) {
        guard let p = panel else { return }
        guard AppState.shared.miniMinified, MiniWindowDockState.shared.isDocked else { return }
        // Don't fight an in-flight mode resize.
        guard resizeAnimator == nil else { return }

        let current = p.frame
        if hovered {
            // Trust the live frame when the hover starts. A stale dock anchor
            // can otherwise pull the bottom edge upward and immediately fire
            // a false hover-exit from under the pointer.
            lastDockedMinY = current.minY
        }

        let resting = restingDockedFrame(reference: current)
        let target = hovered
            ? peekedFrame(restingFrame: resting)
            : collapseDockedFrame(restingFrame: resting, from: current)

        peekAnimator?.cancel()
        peekAnimationGeneration += 1
        let generation = peekAnimationGeneration
        if !animated || !p.isVisible {
            p.setFrame(target, display: true)
            if hovered {
                reconcileHoverAfterPeekSettles()
            }
            return
        }
        peekAnimator = WindowResizeAnimator(
            window: p,
            from: current,
            to: target,
            duration: MiniWindowMetrics.dockPeekAnimationDuration,
            curve: .easeOutQuart
        ) { [weak self] in
            guard let self, self.peekAnimationGeneration == generation else { return }
            self.peekAnimator = nil
            if hovered {
                self.reconcileHoverAfterPeekSettles()
            }
        }
        peekAnimator?.start()
    }

    private func reconcileHoverAfterPeekSettles() {
        guard let p = panel else { return }
        guard !p.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else { return }
        MiniWindowDockState.shared.hovered = false
    }

    private func collapseDockedFrame(restingFrame: NSRect, from current: NSRect) -> NSRect {
        guard restingFrame.minY < current.minY else { return restingFrame }

        var anchored = restingFrame
        anchored.origin.y = current.minY
        lastDockedMinY = anchored.minY
        return anchored
    }

    private func restingDockedFrame(reference: NSRect) -> NSRect {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return reference }
        let visible = screen.visibleFrame
        let screenFrame = screen.frame
        let w = MiniWindowMetrics.dockedRestingWidth
        let h = MiniWindowMetrics.dockedRestingHeight
        let anchorY = lastDockedMinY ?? reference.minY
        let y = max(visible.minY, min(anchorY, visible.maxY - h))
        let x: CGFloat
        switch MiniWindowDockState.shared.edge {
        case .left:  x = screenFrame.minX
        case .right: x = screenFrame.maxX - w
        case .none:  return reference
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func peekedFrame(restingFrame resting: NSRect) -> NSRect {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return resting }
        let visible = screen.visibleFrame
        let screenFrame = screen.frame
        let w = MiniWindowMetrics.dockedPeekedWidth
        let h = MiniWindowMetrics.dockedPeekedHeight
        let y = max(visible.minY, min(resting.minY, visible.maxY - h))
        let x: CGFloat
        switch MiniWindowDockState.shared.edge {
        case .left:  x = screenFrame.minX
        case .right: x = screenFrame.maxX - w
        case .none:  return resting
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Edge snapping

    /// `isMovableByWindowBackground` runs its drag tracking inside AppKit's
    /// internal event loop, so the panel never sees `mouseDown`/`mouseUp` via
    /// the responder chain. Local NSEvent monitors observe app-wide mouse
    /// events and still fire during that loop, which lets us bracket the
    /// drag and detect a frame change on release.
    private func installDragMonitors() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown]
        ) { [weak self] event in
            guard let self, let p = self.panel else { return event }
            if event.windowNumber == p.windowNumber {
                self.dragStartFrame = p.frame
            } else {
                self.dragStartFrame = nil
            }
            return event
        }

        // Clear dock state at the *first sign of an actual drag* (frame
        // deviation), so the SwiftUI shell unrounds and re-borders mid-drag
        // instead of after release.
        mouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged]
        ) { [weak self] event in
            guard let self, let p = self.panel, let start = self.dragStartFrame else { return event }
            if p.frame != start, MiniWindowDockState.shared.edge != .none {
                self.peekAnimator?.cancel()
                self.peekAnimator = nil
                self.peekAnimationGeneration += 1
                MiniWindowDockState.shared.hovered = false
                MiniWindowDockState.shared.edge = .none
            }
            return event
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            if let start = self.dragStartFrame,
               let p = self.panel,
               p.frame != start {
                Task { @MainActor in self.snapToNearestHorizontalEdge() }
            }
            self.dragStartFrame = nil
            return event
        }
    }

    private func snapToNearestHorizontalEdge() {
        guard let p = panel else { return }
        guard let screen = p.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let screenFrame = screen.frame
        let cur = p.frame

        let distLeft = cur.minX - screenFrame.minX
        let distRight = screenFrame.maxX - cur.maxX
        let threshold = MiniWindowMetrics.edgeSnapThreshold

        let snapEdge: MiniWindowDockEdge
        if distLeft <= threshold, distLeft <= distRight {
            snapEdge = .left
        } else if distRight <= threshold, distRight < distLeft {
            snapEdge = .right
        } else {
            return
        }

        let isMinified = AppState.shared.miniMinified
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        if isMinified {
            targetWidth = MiniWindowMetrics.dockedRestingWidth
            targetHeight = MiniWindowMetrics.dockedRestingHeight
        } else {
            targetWidth = cur.width
            targetHeight = cur.height
        }
        let targetX: CGFloat = (snapEdge == .left)
            ? screenFrame.minX
            : screenFrame.maxX - targetWidth
        let proposedY = cur.minY
        let clampedY = max(visible.minY, min(proposedY, visible.maxY - targetHeight))
        let target = NSRect(x: targetX, y: clampedY,
                            width: targetWidth, height: targetHeight)

        if isMinified {
            // Persist the docked bottom edge so hover peeking grows upward
            // instead of temporarily pulling the bottom edge off its line.
            lastDockedMinY = clampedY
        }

        if isMinified {
            p.contentMinSize = NSSize(width: targetWidth, height: targetHeight)
        }

        // Update dock state *before* the slide so the shell asymmetry and
        // corner mask change during the snap rather than after.
        MiniWindowDockState.shared.edge = snapEdge

        if target == cur {
            updateMaskedCorners()
            return
        }

        resizeAnimator?.cancel()
        peekAnimator?.cancel()
        peekAnimator = nil
        peekAnimationGeneration += 1
        let anim = WindowResizeAnimator(
            window: p,
            from: cur,
            to: target,
            duration: MiniWindowMetrics.edgeSnapAnimationDuration
        ) { [weak self] in
            self?.resizeAnimator = nil
            Task { @MainActor in self?.updateMaskedCorners() }
        }
        resizeAnimator = anim
        anim.start()
    }
}
