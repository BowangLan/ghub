import SwiftUI

/// Reusable icon button. Square by default; widens when a badge count is shown.
/// `inFlight` swaps the icon for a small spinner.
struct IconButton: View {
    enum Size { case sm, md, lg }
    enum Variant { case ghost, outline, primary }

    let systemName: String
    let help: String
    var size: Size = .md
    var variant: Variant = .ghost
    var badge: Int = 0
    var inFlight: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: spec.gap) {
                ZStack {
                    if inFlight {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(spec.spinnerScale)
                    } else {
                        Image(systemName: systemName)
                            .font(.system(size: spec.iconSize, weight: .semibold))
                    }
                }
                .frame(width: spec.iconSize, height: spec.iconSize)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: spec.badgeSize, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, spec.hPad)
            .frame(minWidth: spec.height, minHeight: spec.height)
            .frame(height: spec.height)
            .background(
                RoundedRectangle(cornerRadius: spec.radius)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: spec.radius)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
            .foregroundStyle(foregroundStyle)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .pointingHand()
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(help)
    }

    // MARK: - Sizing

    private struct SizeSpec {
        let height: CGFloat
        let iconSize: CGFloat
        let hPad: CGFloat
        let radius: CGFloat
        let badgeSize: CGFloat
        let gap: CGFloat
        let spinnerScale: CGFloat
    }

    private var spec: SizeSpec {
        switch size {
        case .sm:
            return SizeSpec(height: 26, iconSize: 11,  hPad: 3,  radius: 4,
                            badgeSize: 9,  gap: 3, spinnerScale: 0.5)
        case .md:
            return SizeSpec(height: 32, iconSize: 12, hPad: 8,  radius: DT.Radius.sm,
                            badgeSize: 12, gap: 5, spinnerScale: 0.85)
        case .lg:
            return SizeSpec(height: 48, iconSize: 16, hPad: 12, radius: DT.Radius.md,
                            badgeSize: 16, gap: 6, spinnerScale: 1.0)
        }
    }

    // MARK: - Variant styling

    private var fillColor: Color {
        switch variant {
        case .ghost, .outline:
            return hovered && isEnabled ? DT.Color.surfaceHover : Color.clear
        case .primary:
            return isEnabled ? Color.accentColor : Color.accentColor.opacity(0.35)
        }
    }

    private var strokeColor: Color {
        switch variant {
        case .ghost:
            return hovered && isEnabled ? DT.Color.border : Color.clear
        case .outline:
            return DT.Color.border
        case .primary:
            return Color.clear
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        switch variant {
        case .ghost, .outline:
            if !isEnabled { return AnyShapeStyle(.tertiary) }
            return AnyShapeStyle(hovered ? .primary : .secondary)
        case .primary:
            return AnyShapeStyle(.white)
        }
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
