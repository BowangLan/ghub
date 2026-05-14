import SwiftUI

struct DiffFileRow: View {
    let file: GitClient.FileDiff
    var isHidden: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(statusCode)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if !file.folder.isEmpty {
                    Text(file.folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Text(file.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                    Text(file.scope.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if isHidden {
                        Text("stashed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(isHidden ? 0.62 : 1)
    }

    private var statusCode: String {
        switch file.status {
        case "Added", "Untracked": return "A"
        case "Deleted": return "D"
        case "Renamed": return "R"
        case "Copied": return "C"
        case "Type changed": return "T"
        case "Unmerged": return "U"
        default: return "M"
        }
    }

    private var statusColor: Color {
        switch file.status {
        case "Added", "Untracked": return DT.Color.emerald
        case "Deleted": return DT.Color.red
        case "Renamed", "Copied": return DT.Color.sky
        default: return DT.Color.amber
        }
    }
}
