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
            VStack(alignment: .leading, spacing: 2) {
                RepoMenu()
                if let repo = selected {
                    Text((repo.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
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

struct RepoMenu: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Menu {
            if state.repos.isEmpty {
                Text("No repos tracked").foregroundStyle(.secondary)
            } else {
                ForEach(state.repos) { r in
                    Button {
                        state.selectedRepoID = r.id
                    } label: {
                        if r.id == state.selectedRepoID {
                            Label(r.name, systemImage: "checkmark")
                        } else {
                            Text(r.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(state.selectedRepo?.name ?? "Select repo")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
