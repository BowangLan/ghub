import SwiftUI

struct ChipStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DT.Color.surface, in: Capsule())
    }
}

extension View {
    func chip() -> some View { modifier(ChipStyle()) }
}
