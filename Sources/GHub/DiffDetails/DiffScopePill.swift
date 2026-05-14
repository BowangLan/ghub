import SwiftUI

struct DiffScopePill: View {
    let scope: GitClient.DiffScope

    var body: some View {
        Text(scope.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch scope {
        case .staged: return DT.Color.emerald
        case .unstaged: return DT.Color.amber
        case .untracked: return DT.Color.sky
        }
    }
}
