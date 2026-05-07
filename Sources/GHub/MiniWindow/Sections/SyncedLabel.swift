import SwiftUI
import AppKit

struct SyncedLabel: View {
    let repo: Repo

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        Group {
            if let last = repo.lastSyncedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Synced \(Self.formatter.localizedString(for: last, relativeTo: context.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                Text("Never synced")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
