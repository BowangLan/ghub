import SwiftUI

/// Background fill, clip, and border for the MiniWindow's outer shell. When
/// `dockEdge` is `.left` or `.right`, the dock-side corners go flat and the
/// dock-side border line is omitted so the panel reads as a tab/badge that's
/// edge-anchored.
struct MiniWindowShell: ViewModifier {
    let dockEdge: MiniWindowDockEdge
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(borderOverlay)
            .clipShape(shape)
            .animation(
                .easeInOut(duration: MiniWindowMetrics.dockPeekAnimationDuration),
                value: dockEdge
            )
    }

    private var shape: UnevenRoundedRectangle {
        let radius = cornerRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: dockEdge == .left ? 0 : radius,
            bottomLeadingRadius: dockEdge == .left ? 0 : radius,
            bottomTrailingRadius: dockEdge == .right ? 0 : radius,
            topTrailingRadius: dockEdge == .right ? 0 : radius,
            style: .continuous
        )
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch dockEdge {
        case .none:
            shape.stroke(DT.Color.border, lineWidth: 1)
        case .left, .right:
            DockSideOpenBorder(dockEdge: dockEdge, cornerRadius: cornerRadius)
                .stroke(DT.Color.border, lineWidth: 1)
        }
    }
}

/// Three-sided border path for the docked badge shell, leaving the screen-edge
/// side open.
private struct DockSideOpenBorder: Shape {
    let dockEdge: MiniWindowDockEdge
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = cornerRadius

        switch dockEdge {
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX, y: rect.minY + radius),
                radius: radius
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX + radius, y: rect.maxY),
                radius: radius
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .none:
            break
        }

        return path
    }
}
