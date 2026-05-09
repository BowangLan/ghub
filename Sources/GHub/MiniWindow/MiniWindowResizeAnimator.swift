import AppKit
import QuartzCore

/// Drives `NSWindow.setFrame` directly per-frame via a display link, so origin
/// and size update atomically each tick.
@MainActor
enum WindowAnimationCurve {
    case easeInOut
    case easeOutQuart

    func value(at t: Double) -> Double {
        switch self {
        case .easeInOut:
            if t < 0.5 { return 4 * t * t * t }
            let u = -2 * t + 2
            return 1 - (u * u * u) / 2
        case .easeOutQuart:
            let u = 1 - t
            return 1 - u * u * u * u
        }
    }
}

@MainActor
final class WindowResizeAnimator: NSObject {
    private weak var window: NSWindow?
    private let fromFrame: NSRect
    private let toFrame: NSRect
    private let duration: CFTimeInterval
    private let curve: WindowAnimationCurve
    private let onComplete: () -> Void

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var isCancelled = false
    private var didComplete = false

    init(
        window: NSWindow,
        from: NSRect,
        to: NSRect,
        duration: CFTimeInterval,
        curve: WindowAnimationCurve = .easeInOut,
        onComplete: @escaping () -> Void
    ) {
        self.window = window
        self.fromFrame = from
        self.toFrame = to
        self.duration = duration
        self.curve = curve
        self.onComplete = onComplete
    }

    func start() {
        guard !isCancelled else { return }
        guard let win = window else {
            onComplete()
            return
        }
        startTime = CACurrentMediaTime()
        let screen = win.screen ?? NSScreen.main
        guard let link = screen?.displayLink(target: self, selector: #selector(tick(_:))) else {
            win.setFrame(toFrame, display: true)
            complete()
            return
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func cancel() {
        isCancelled = true
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !isCancelled else {
            link.invalidate()
            displayLink = nil
            return
        }
        guard let win = window else {
            link.invalidate()
            displayLink = nil
            return
        }

        let now = CACurrentMediaTime()
        let raw = duration > 0 ? (now - startTime) / duration : 1
        let t = min(max(raw, 0), 1)
        let eased = curve.value(at: t)
        let current = NSRect(
            x: fromFrame.minX + (toFrame.minX - fromFrame.minX) * eased,
            y: fromFrame.minY + (toFrame.minY - fromFrame.minY) * eased,
            width: fromFrame.width + (toFrame.width - fromFrame.width) * eased,
            height: fromFrame.height + (toFrame.height - fromFrame.height) * eased
        )

        win.setFrame(current, display: true)
        guard !isCancelled else { return }

        if t >= 1 {
            link.invalidate()
            displayLink = nil
            complete()
        }
    }

    private func complete() {
        guard !didComplete, !isCancelled else { return }
        didComplete = true
        onComplete()
    }
}
