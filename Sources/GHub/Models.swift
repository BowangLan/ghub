import Foundation

struct Repo: Identifiable, Hashable, Sendable {
    static let defaultPRFilterQuery = "is:pr author:@me"

    let id: String
    var path: String
    var name: String
    var owner: String?
    var repoName: String?
    var defaultBranch: String?
    var prFilterQuery: String
    var addedAt: Date
    var lastSyncedAt: Date?
    var syncEnabled: Bool
    var currentBranch: String?
    var isDirty: Bool
    var untrackedCount: Int
    var ahead: Int
    var behind: Int
    var openPRCount: Int
    var failingCheckCount: Int
    var pendingCheckCount: Int

    var slug: String? {
        if let owner, let repoName { return "\(owner)/\(repoName)" }
        return nil
    }
}

struct Branch: Identifiable, Hashable, Sendable {
    var id: String { "\(repoID):\(name)" }
    let repoID: String
    let name: String
    let headSHA: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let lastCommitAt: Date?
    let isCurrent: Bool

    var shortHeadSHA: String { String(headSHA.prefix(7)) }
}

struct Commit: Identifiable, Hashable, Sendable {
    var id: String { "\(repoID):\(sha)" }
    let repoID: String
    let sha: String
    let author: String
    let email: String
    let date: Date?
    let message: String

    var shortSHA: String { String(sha.prefix(7)) }
}

struct PullRequest: Identifiable, Hashable, Sendable {
    var id: String { "\(repoID):\(number)" }
    let repoID: String
    let number: Int
    let title: String
    let state: String       // OPEN, CLOSED, MERGED
    let isDraft: Bool
    let headBranch: String
    let baseBranch: String
    let author: String
    let url: String
    let createdAt: Date?
    let updatedAt: Date?
    let mergedAt: Date?
}

struct CICheck: Identifiable, Hashable, Sendable {
    var id: String { "\(repoID):\(prNumber):\(name)" }
    let repoID: String
    let prNumber: Int
    let name: String
    let status: String       // QUEUED, IN_PROGRESS, COMPLETED (CheckRun) or empty
    let conclusion: String?  // SUCCESS, FAILURE, CANCELLED, NEUTRAL, SKIPPED, TIMED_OUT, ACTION_REQUIRED, STALE
    let url: String?
    let completedAt: Date?

    var isFailing: Bool {
        guard let c = conclusion?.uppercased() else { return false }
        return c == "FAILURE" || c == "TIMED_OUT" || c == "ACTION_REQUIRED" || c == "STARTUP_FAILURE"
    }
    var isPending: Bool {
        if conclusion == nil || conclusion?.isEmpty == true { return true }
        let s = status.uppercased()
        return s == "QUEUED" || s == "IN_PROGRESS" || s == "PENDING"
    }
    var isSuccess: Bool {
        (conclusion?.uppercased() == "SUCCESS") || (conclusion?.uppercased() == "NEUTRAL") || (conclusion?.uppercased() == "SKIPPED")
    }
}

struct CIWatchTarget: Identifiable, Hashable, Sendable {
    var id: String { "\(repoID)#\(prNumber)" }
    let repoID: String
    let slug: String
    let prNumber: Int
}
