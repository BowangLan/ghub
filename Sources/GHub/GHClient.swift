import Foundation

enum GHClient {
    static let bin: String? = Shell.resolve("gh")

    static var isAvailable: Bool { bin != nil }

    struct SquashMergeMessage: Sendable, Equatable {
        var subject: String
        var body: String
    }

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

    /// Fetch CI checks for one PR using `gh pr checks`.
    static func fetchChecks(slug: String, repoID: String, prNumber: Int) async throws -> [CICheck] {
        guard let bin else { throw ShellError.notFound("gh") }
        let fields = [
            "bucket", "completedAt", "link", "name", "state", "workflow"
        ].joined(separator: ",")
        let out = try await Shell.run(bin, [
            "pr", "checks", "\(prNumber)",
            "--repo", slug,
            "--json", fields
        ])
        if out.status != 0 && out.status != 8 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        guard let data = out.stdout.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: []),
              let arr = any as? [[String: Any]]
        else {
            return []
        }
        return arr.compactMap { item in
            let name = item["name"] as? String ?? ""
            if name.isEmpty { return nil }
            let bucket = (item["bucket"] as? String ?? "").lowercased()
            let state = item["state"] as? String ?? ""
            let conclusion: String?
            switch bucket {
            case "pass":
                conclusion = "SUCCESS"
            case "fail":
                conclusion = "FAILURE"
            case "cancel":
                conclusion = "CANCELLED"
            case "skipping":
                conclusion = "SKIPPED"
            case "pending":
                conclusion = nil
            default:
                conclusion = state.isEmpty ? nil : state.uppercased()
            }
            let status = bucket == "pending" ? state.uppercased() : "COMPLETED"
            return CICheck(
                repoID: repoID,
                prNumber: prNumber,
                name: name,
                status: status,
                conclusion: conclusion,
                url: item["link"] as? String,
                completedAt: (item["completedAt"] as? String).flatMap(ISODate.parse)
            )
        }
    }

    /// Build the same default squash message GitHub presents for its default
    /// squash-merge setting: one commit uses that commit's message; multiple
    /// commits use the PR title/number plus a commit list.
    static func defaultSquashMergeMessage(slug: String, prNumber: Int) async throws -> SquashMergeMessage {
        guard let bin else { throw ShellError.notFound("gh") }
        let out = try await Shell.run(bin, [
            "pr", "view", "\(prNumber)",
            "--repo", slug,
            "--json", "title,commits"
        ])
        if out.status != 0 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        let decoder = JSONDecoder()
        guard let data = out.stdout.data(using: .utf8),
              let payload = try? decoder.decode(PRMergeMessagePayload.self, from: data)
        else {
            return SquashMergeMessage(subject: "Merge pull request #\(prNumber)", body: "")
        }

        if payload.commits.count == 1, let commit = payload.commits.first {
            return SquashMergeMessage(
                subject: commit.messageHeadline.nilIfEmpty ?? payload.title,
                body: commit.messageBody
            )
        }

        let subject = "\(payload.title) (#\(prNumber))"
        let body = payload.commits
            .map(\.messageHeadline)
            .filter { !$0.isEmpty }
            .map { "* \($0)" }
            .joined(separator: "\n")
        return SquashMergeMessage(subject: subject, body: body)
    }

    static func squashMerge(slug: String, prNumber: Int, subject: String, body: String) async throws {
        guard let bin else { throw ShellError.notFound("gh") }
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghub-squash-body-\(UUID().uuidString).txt")
        try body.write(to: bodyURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let out = try await Shell.run(bin, [
            "pr", "merge", "\(prNumber)",
            "--repo", slug,
            "--squash",
            "--subject", subject,
            "--body-file", bodyURL.path
        ])
        if out.status != 0 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
    }
}

private struct PRMergeMessagePayload: Decodable {
    let title: String
    let commits: [PRCommitMessage]
}

private struct PRCommitMessage: Decodable {
    let messageHeadline: String
    let messageBody: String

    private enum CodingKeys: String, CodingKey {
        case messageHeadline
        case messageBody
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageHeadline = try c.decodeIfPresent(String.self, forKey: .messageHeadline) ?? ""
        messageBody = try c.decodeIfPresent(String.self, forKey: .messageBody) ?? ""
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
