import SwiftUI

struct PulseIfRunning: ViewModifier {
    let active: Bool
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        Group {
            if active {
                content
                    .opacity(phase ? 0.55 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: phase)
                    .onAppear { phase = true }
            } else {
                content
            }
        }
    }
}

extension View {
    func pulseIfRunning(_ active: Bool) -> some View {
        modifier(PulseIfRunning(active: active))
    }
}
