import SwiftUI

struct RepoSelectorView: View {
    enum Style {
        case expanded
        case compact
    }

    @EnvironmentObject var state: AppState

    let repo: Repo?
    let style: Style

    var body: some View {
        Group {
            switch style {
            case .expanded:
                expandedLabel
            case .compact:
                compactLabel
            }
        }
        .disabled(state.repos.isEmpty)
        .pointingHand()
        .help(state.repos.isEmpty ? "No repos tracked" : "Switch repository")
    }

    private func selectorMenu<Label: View>(
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        Menu {
            Picker("Repository", selection: selection) {
                if state.repos.isEmpty {
                    Text("No repos tracked").tag(nil as String?)
                } else if state.selectedRepoID == nil {
                    Text("Select repo").tag(nil as String?)
                }
                ForEach(state.repos) { repo in
                    Text(repo.name).tag(Optional(repo.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    private var selection: Binding<String?> {
        Binding(
            get: { state.selectedRepoID },
            set: { state.selectedRepoID = $0 }
        )
    }

    private var expandedLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            selectorMenu {
                titleRow(font: .system(size: 17, weight: .medium), chevronSize: 9)
            }
            if let repo {
                Text((repo.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .repoSelectorGlass(cornerRadius: 12)
        .contentShape(Rectangle())
    }

    private var compactLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            selectorMenu {
                titleRow(font: .system(size: 13, weight: .medium), chevronSize: 8)
            }
            BranchReferenceView(
                name: repo?.currentBranch ?? "—",
                style: .compact,
                muted: true
            )
            .layoutPriority(1)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .repoSelectorGlass(cornerRadius: 10)
        .contentShape(Rectangle())
    }

    private func titleRow(font: Font, chevronSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(repo?.name ?? "Select repo")
                .font(font)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

private extension View {
    @ViewBuilder
    func repoSelectorGlass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(DT.Color.surface.opacity(0.70), in: shape)
                .overlay(shape.stroke(DT.Color.border, lineWidth: 0.5))
        }
    }
}
