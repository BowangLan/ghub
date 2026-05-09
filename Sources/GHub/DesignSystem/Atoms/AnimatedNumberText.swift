import SwiftUI

enum AnimatedNumberDirection {
    case automatic
    case up
    case down
}

struct AnimatedNumberText: View {
    let value: Int
    let prefix: String
    let color: Color
    let flashColor: Color
    let direction: AnimatedNumberDirection

    @State private var previousValue: Int
    @State private var isPopping = false

    init(
        _ value: Int,
        prefix: String = "",
        color: Color = .primary,
        flashColor: Color = .primary,
        direction: AnimatedNumberDirection = .automatic
    ) {
        self.value = value
        self.prefix = prefix
        self.color = color
        self.flashColor = flashColor
        self.direction = direction
        self._previousValue = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !prefix.isEmpty {
                Text(prefix)
            }

            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                RollingDigit(value: digit, direction: resolvedDirection)
            }
        }
        .foregroundStyle(isPopping ? flashColor : color)
        .shadow(color: flashColor.opacity(isPopping ? 0.55 : 0), radius: isPopping ? 7 : 0)
        .scaleEffect(isPopping ? 1.08 : 1, anchor: .leading)
        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isPopping)
        .onChange(of: value) { oldValue, newValue in
            guard oldValue != newValue else { return }
            previousValue = oldValue
            isPopping = true

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                isPopping = false
            }
        }
    }

    private var digits: [Int] {
        String(abs(value)).compactMap { $0.wholeNumberValue }
    }

    private var resolvedDirection: RollingDigit.Direction {
        switch direction {
        case .automatic:
            value >= previousValue ? .up : .down
        case .up:
            .up
        case .down:
            .down
        }
    }
}

private struct RollingDigit: View {
    enum Direction {
        case up
        case down
    }

    let value: Int
    let direction: Direction

    @State private var previousValue: Int
    @State private var displayedValue: Int
    @State private var isRolling = true

    init(value: Int, direction: Direction) {
        self.value = value
        self.direction = direction
        self._previousValue = State(initialValue: value)
        self._displayedValue = State(initialValue: value)
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack {
                Text("\(previousValue)")
                    .offset(y: isRolling ? outgoingOffset(height) : 0)
                    .opacity(isRolling ? 0 : 1)

                Text("\(displayedValue)")
                    .offset(y: isRolling ? 0 : incomingOffset(height))
                    .opacity(isRolling ? 1 : 0)
            }
            .clipped()
        }
        .frame(width: digitWidth, height: digitHeight)
        .onChange(of: value) { _, newValue in
            guard newValue != displayedValue else { return }
            previousValue = displayedValue
            displayedValue = newValue
            isRolling = false

            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                isRolling = true
            }
        }
    }

    private var digitWidth: CGFloat { 13 }
    private var digitHeight: CGFloat { 27 }

    private func incomingOffset(_ height: CGFloat) -> CGFloat {
        direction == .up ? height : -height
    }

    private func outgoingOffset(_ height: CGFloat) -> CGFloat {
        direction == .up ? -height : height
    }
}
