import SwiftUI

struct HeaderSection: View {
    @EnvironmentObject var state: AppState

    let selected: Repo?
    let currentPR: PullRequest?
    let isSyncing: Bool
    let namespace: Namespace.ID
    let onToggleMode: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RepoSelectorView(repo: selected, style: .expanded)
            Spacer(minLength: 6)
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }

            // State pill
            // Group {
            //     if let pr = currentPR {
            //         StatePill(kind: .pr(pr))
            //     } else if selected != nil {
            //         StatePill(kind: .noPR)
            //     }
            // }
            // .matchedGeometryEffect(id: "miniWindow.statePill", in: namespace)


            HStack(alignment: .center, spacing: 2) {
                SyncedLabel(date: state.lastSyncedAt)
                    .padding(.trailing, 6)
                if selected != nil {
                    ToggleModeButton(minified: false, action: onToggleMode)
                }
                CloseMiniButton()
            }
        }
        .padding(.vertical, DT.Spacing.windowPaddingVertical)
        .padding(.horizontal, DT.Spacing.windowPaddingHorizontal)
    }
}
