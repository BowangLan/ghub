import Combine
import Foundation

/// Which screen edge the MiniWindow is currently snapped against, or `.none`
/// when the window is floating freely.
enum MiniWindowDockEdge: Equatable {
    case none
    case left
    case right

    var isHorizontal: Bool { self == .left || self == .right }
}

/// Shared state describing the MiniWindow's edge-dock + hover-peek behavior.
/// `MiniWindowController` writes `edge` after a snap (and clears it on drag);
/// `MiniRepoView` writes `hovered` from `.onHover`. The controller observes
/// `hovered` to drive the peek-out frame animation, and the view observes
/// `edge`/`hovered` to swap between the resting badge layout and the peeked
/// content layout.
@MainActor
final class MiniWindowDockState: ObservableObject {
    static let shared = MiniWindowDockState()

    @Published var edge: MiniWindowDockEdge = .none
    @Published var hovered: Bool = false

    var isDocked: Bool { edge != .none }

    private init() {}
}
