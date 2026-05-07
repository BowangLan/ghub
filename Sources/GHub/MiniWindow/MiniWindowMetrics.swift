import Foundation

/// Single source of truth for any value that has to stay in sync between
/// `MiniRepoView` (SwiftUI side), `MiniWindowController` (AppKit/NSPanel side),
/// and the mode-toggle animation. Keep MiniWindow-specific layout/timing
/// constants here rather than scattering them across files.
enum MiniWindowMetrics {
    /// Width floor for the panel across both modes.
    static let minWidth: CGFloat = 360

    /// Content (window-minus-titlebar) height of the fully collapsed compact card.
    static let compactContentHeight: CGFloat = 76

    /// Default expanded content size used the first time the panel is shown
    /// (autosaved frame supersedes it on subsequent launches) and as the
    /// fallback when no persisted expanded size exists.
    static let expandedDefaultSize = CGSize(width: 380, height: 480)

    /// Minimum content height the user can manually shrink to, per mode.
    static let compactContentMinHeight: CGFloat = 150
    static let expandedContentMinHeight: CGFloat = 400

    /// Validity floor for restoring a persisted expanded size — values below
    /// this are treated as missing and we fall back to `expandedDefaultSize`.
    static let persistedExpandedMinWidth: CGFloat = 360
    static let persistedExpandedMinHeight: CGFloat = 200

    /// Mode-toggle animation duration. Both the SwiftUI element animation
    /// (`MiniRepoView.toggleMode()`) and the display-link-driven NSPanel
    /// resize (`WindowResizeAnimator`) reference this so they stay in lockstep.
    static let modeAnimationDuration: TimeInterval = 0.28

    /// Rounded outer-shell radius shared by both modes.
    static let shellCornerRadius: CGFloat = 14
}
