import Foundation

enum GHClient {
    static let bin: String? = Shell.resolve("gh")

    static var isAvailable: Bool { bin != nil }

    static func authStatus() async -> Bool {
        guard let bin else { return false }
        let out = try? await Shell.run(bin, ["auth", "status"])
        return (out?.status ?? 1) == 0
    }

    /// Fetch open PRs and their CI checks in a single `gh pr list` call.
    static func fetchPRsAndChecks(slug: String, repoID: String, searchQuery: String? = nil) async throws -> ([PullRequest], [CICheck]) {
        guard let bin else { throw ShellError.notFound("gh") }
        let fields = [
            "number", "title", "state", "isDraft",
            "headRefName", "baseRefName", "author", "url",
            "createdAt", "updatedAt", "mergedAt", "statusCheckRollup"
        ].joined(separator: ",")
        var args = [
            "pr", "list", "--repo", slug,
            "--state", "open", "--limit", "50",
            "--json", fields
        ]
        if let searchQuery = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !searchQuery.isEmpty {
            args.append(contentsOf: ["--search", searchQuery])
        }
        let out = try await Shell.run(bin, args)
        if out.status != 0 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        guard let data = out.stdout.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: []),
              let arr = any as? [[String: Any]]
        else {
            return ([], [])
        }
        var prs: [PullRequest] = []
        var checks: [CICheck] = []
        for item in arr {
            let number = item["number"] as? Int ?? 0
            if number == 0 { continue }
            let title = item["title"] as? String ?? ""
            let state = item["state"] as? String ?? "OPEN"
            let isDraft = item["isDraft"] as? Bool ?? false
            let head = item["headRefName"] as? String ?? ""
            let base = item["baseRefName"] as? String ?? ""
            let url = item["url"] as? String ?? ""
            let author = (item["author"] as? [String: Any])?["login"] as? String
                      ?? (item["author"] as? [String: Any])?["name"] as? String
                      ?? ""
            let created = (item["createdAt"] as? String).flatMap(ISODate.parse)
            let updated = (item["updatedAt"] as? String).flatMap(ISODate.parse)
            let merged  = (item["mergedAt"] as? String).flatMap(ISODate.parse)
            prs.append(PullRequest(
                repoID: repoID, number: number, title: title, state: state, isDraft: isDraft,
                headBranch: head, baseBranch: base, author: author, url: url,
                createdAt: created, updatedAt: updated, mergedAt: merged
            ))

            if let rollup = item["statusCheckRollup"] as? [[String: Any]] {
                var seen = Set<String>()
                for c in rollup {
                    let typename = c["__typename"] as? String ?? ""
                    let name: String
                    let status: String
                    let conclusion: String?
                    let detailsURL: String?
                    let completedAt: Date?
                    if typename == "StatusContext" {
                        name = c["context"] as? String ?? ""
                        status = ""
                        conclusion = c["state"] as? String
                        detailsURL = c["targetUrl"] as? String
                        completedAt = (c["createdAt"] as? String).flatMap(ISODate.parse)
                    } else {
                        // CheckRun and any future variants
                        name = (c["name"] as? String) ?? (c["context"] as? String) ?? ""
                        status = (c["status"] as? String) ?? ""
                        conclusion = c["conclusion"] as? String
                        detailsURL = (c["detailsUrl"] as? String) ?? (c["targetUrl"] as? String)
                        completedAt = (c["completedAt"] as? String).flatMap(ISODate.parse)
                    }
                    if name.isEmpty { continue }
                    // De-dup re-runs of same check name; keep latest by completedAt.
                    if seen.contains(name) { continue }
                    seen.insert(name)
                    checks.append(CICheck(
                        repoID: repoID, prNumber: number, name: name,
                        status: status, conclusion: conclusion,
                        url: detailsURL, completedAt: completedAt
                    ))
                }
            }
        }
        return (prs, checks)
    }
}
