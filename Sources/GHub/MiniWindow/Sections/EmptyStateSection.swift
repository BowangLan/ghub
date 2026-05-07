import SwiftUI

struct EmptyStateSection: View {
    let reposIsEmpty: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.dashed")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No repository selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(reposIsEmpty ? "Add one from the menu bar." : "Pick one above.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
