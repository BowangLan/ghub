import SwiftUI

enum PillSize { case small, regular }

struct PillStyle: ViewModifier {
    var tint: Color
    var size: PillSize = .regular
    var bordered: Bool = true

    func body(content: Content) -> some View {
        let (hPad, vPad, bgOp, strokeOp): (CGFloat, CGFloat, Double, Double) = {
            switch size {
            case .small:   return (6, 2, 0.12, 0.25)
            case .regular: return (8, 3, 0.10, 0.30)
            }
        }()
        return content
            .foregroundStyle(tint)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(tint.opacity(bgOp), in: Capsule())
            .overlay(bordered ? Capsule().stroke(tint.opacity(strokeOp), lineWidth: 0.5) : nil)
    }
}

extension View {
    func pill(_ tint: Color, size: PillSize = .regular, bordered: Bool = true) -> some View {
        modifier(PillStyle(tint: tint, size: size, bordered: bordered))
    }
}
