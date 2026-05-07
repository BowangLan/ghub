import SwiftUI

struct SCMIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(height: DT.Size.footerBtnHeight)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .fill(hovering && isEnabled ? DT.Color.surfaceHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.sm)
                    .stroke(DT.Color.border, lineWidth: 0.5)
            )
            .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct SCMIconButtonLabel: View {
    let icon: String
    let badge: Int
    let inFlight: Bool

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                if inFlight {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 14, height: 14)
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }
}
