import Foundation

let defaultDiffGroupID = "__default__"

struct HiddenDiffGroup {
    let group: GitClient.FileCommitGroup
    let stash: GitClient.GroupStash
}

func friendlyDiffDetailsError(_ error: Error) -> String {
    String(describing: error).replacingOccurrences(of: "ShellError.", with: "")
}

func diffFileKey(_ file: GitClient.FileDiff) -> String {
    "\(file.scope.rawValue):\(file.path)"
}

func buildFileCommitGroups(
    files: [GitClient.FileDiff],
    records: [DiffFileGroupRecord],
    assignments: [String: String],
    hiddenGroups: [String: HiddenDiffGroup]
) -> [GitClient.FileCommitGroup] {
    let visibleGroupIDs = Set(records.map(\.id))
    var filesByGroup: [String: [GitClient.FileDiff]] = [:]
    for file in files {
        let assigned = assignments[diffFileKey(file)]
        let groupID = assigned.flatMap { visibleGroupIDs.contains($0) ? $0 : nil } ?? defaultDiffGroupID
        filesByGroup[groupID, default: []].append(file)
    }

    var groups: [GitClient.FileCommitGroup] = [
        GitClient.FileCommitGroup(
            id: defaultDiffGroupID,
            name: "Ungrouped",
            files: (filesByGroup[defaultDiffGroupID] ?? []).sortedByDisplayPath(),
            branch: nil,
            isDefault: true
        )
    ]

    for record in records {
        groups.append(GitClient.FileCommitGroup(
            id: record.id,
            name: record.name,
            files: (filesByGroup[record.id] ?? []).sortedByDisplayPath(),
            branch: record.branch,
            isDefault: false
        ))
    }

    for hidden in hiddenGroups.values where !groups.contains(where: { $0.id == hidden.group.id }) {
        groups.append(hidden.group)
    }
    return groups
}

extension Array where Element == GitClient.FileDiff {
    func sortedByDisplayPath() -> [GitClient.FileDiff] {
        sorted {
            if $0.path == $1.path {
                return $0.scope.rawValue < $1.scope.rawValue
            }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }
}
