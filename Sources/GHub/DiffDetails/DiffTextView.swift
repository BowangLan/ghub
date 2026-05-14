import SwiftUI

struct DiffTextView: View {
    let diff: String

    private var lines: [String] {
        let text = diff.isEmpty ? "No textual diff available." : diff
        return text.components(separatedBy: .newlines)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(color(for: line))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return .secondary
        }
        if line.hasPrefix("+") {
            return DT.Color.emerald
        }
        if line.hasPrefix("-") {
            return DT.Color.red
        }
        if line.hasPrefix("@@") {
            return DT.Color.sky
        }
        if line.hasPrefix("diff --git") {
            return .secondary
        }
        return .primary
    }
}
