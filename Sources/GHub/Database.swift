import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBError: Error, CustomStringConvertible {
    case open(String)
    case exec(String)
    case prepare(String)
    case step(String)
    case bind(String)

    var description: String {
        switch self {
        case .open(let s): return "sqlite open: \(s)"
        case .exec(let s): return "sqlite exec: \(s)"
        case .prepare(let s): return "sqlite prepare: \(s)"
        case .step(let s): return "sqlite step: \(s)"
        case .bind(let s): return "sqlite bind: \(s)"
        }
    }
}

actor Database {
    static let shared: Database = {
        do { return try Database() } catch { fatalError("DB init: \(error)") }
    }()

    private var db: OpaquePointer?
    nonisolated let fileURL: URL

    private init() throws {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("ghub", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.fileURL = dir.appendingPathComponent("ghub.sqlite")
        var handle: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw DBError.open(String(cString: sqlite3_errmsg(handle)))
        }
        guard let handle else {
            throw DBError.open("null handle")
        }
        try Self.bootstrap(handle)
        self.db = handle
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    // MARK: - Schema

    private static func bootstrap(_ db: OpaquePointer) throws {
        try execRaw(db, "PRAGMA journal_mode=WAL;")
        try execRaw(db, "PRAGMA foreign_keys=ON;")
        try execRaw(db, "PRAGMA busy_timeout=5000;")
        try execRaw(db, """
        CREATE TABLE IF NOT EXISTS repos (
          id TEXT PRIMARY KEY,
          path TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          owner TEXT,
          repo_name TEXT,
          default_branch TEXT,
          pr_filter_query TEXT NOT NULL DEFAULT 'is:pr author:@me',
          added_at REAL NOT NULL,
          last_synced_at REAL,
          sync_enabled INTEGER NOT NULL DEFAULT 1,
          current_branch TEXT,
          is_dirty INTEGER NOT NULL DEFAULT 0,
          untracked_count INTEGER NOT NULL DEFAULT 0,
          ahead INTEGER NOT NULL DEFAULT 0,
          behind INTEGER NOT NULL DEFAULT 0,
          open_pr_count INTEGER NOT NULL DEFAULT 0,
          failing_check_count INTEGER NOT NULL DEFAULT 0,
          pending_check_count INTEGER NOT NULL DEFAULT 0
        );
        """)
        try addColumnIfMissing(
            db,
            table: "repos",
            column: "pr_filter_query",
            definition: "TEXT NOT NULL DEFAULT '\(Repo.defaultPRFilterQuery)'"
        )
        try addColumnIfMissing(
            db,
            table: "repos",
            column: "pending_check_count",
            definition: "INTEGER NOT NULL DEFAULT 0"
        )
        try execRaw(db, "UPDATE repos SET pr_filter_query = '\(Repo.defaultPRFilterQuery)' WHERE pr_filter_query = '';")
        try execRaw(db, """
        CREATE TABLE IF NOT EXISTS branches (
          repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          head_sha TEXT NOT NULL,
          upstream TEXT,
          ahead INTEGER NOT NULL DEFAULT 0,
          behind INTEGER NOT NULL DEFAULT 0,
          last_commit_at REAL,
          is_current INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (repo_id, name)
        );
        """)
        try execRaw(db, """
        CREATE TABLE IF NOT EXISTS commits (
          repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
          sha TEXT NOT NULL,
          author TEXT,
          email TEXT,
          date REAL,
          message TEXT,
          PRIMARY KEY (repo_id, sha)
        );
        """)
        try execRaw(db, "CREATE INDEX IF NOT EXISTS idx_commits_repo_date ON commits(repo_id, date DESC);")
        try execRaw(db, """
        CREATE TABLE IF NOT EXISTS pull_requests (
          repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
          number INTEGER NOT NULL,
          title TEXT NOT NULL,
          state TEXT NOT NULL,
          is_draft INTEGER NOT NULL DEFAULT 0,
          head_branch TEXT,
          base_branch TEXT,
          author TEXT,
          url TEXT,
          created_at REAL,
          updated_at REAL,
          merged_at REAL,
          PRIMARY KEY (repo_id, number)
        );
        """)
        try execRaw(db, """
        CREATE TABLE IF NOT EXISTS ci_checks (
          repo_id TEXT NOT NULL,
          pr_number INTEGER NOT NULL,
          name TEXT NOT NULL,
          status TEXT,
          conclusion TEXT,
          url TEXT,
          completed_at REAL,
          PRIMARY KEY (repo_id, pr_number, name),
          FOREIGN KEY (repo_id, pr_number) REFERENCES pull_requests(repo_id, number) ON DELETE CASCADE
        );
        """)
        try execRaw(db, """
        CREATE TABLE IF NOT EXISTS diff_file_groups (
          id TEXT PRIMARY KEY,
          repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          branch TEXT,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at REAL NOT NULL
        );
        """)
        try execRaw(db, "CREATE INDEX IF NOT EXISTS idx_diff_file_groups_repo_order ON diff_file_groups(repo_id, sort_order, created_at);")
        try execRaw(db, """
        CREATE TABLE IF NOT EXISTS diff_file_group_items (
          repo_id TEXT NOT NULL REFERENCES repos(id) ON DELETE CASCADE,
          file_key TEXT NOT NULL,
          group_id TEXT NOT NULL REFERENCES diff_file_groups(id) ON DELETE CASCADE,
          updated_at REAL NOT NULL,
          PRIMARY KEY (repo_id, file_key)
        );
        """)
    }

    private static func execRaw(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DBError.exec(msg)
        }
    }

    private static func addColumnIfMissing(_ db: OpaquePointer, table: String, column: String, definition: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var exists = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1), String(cString: name) == column {
                exists = true
                break
            }
        }
        if !exists {
            try execRaw(db, "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
        }
    }

    // MARK: - Low-level helpers

    private func execSync(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DBError.exec(msg)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DBError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        return stmt!
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: Any?) throws {
        if value == nil { sqlite3_bind_null(stmt, idx); return }
        switch value {
        case let s as String:
            sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
        case let i as Int:
            sqlite3_bind_int64(stmt, idx, Int64(i))
        case let i as Int64:
            sqlite3_bind_int64(stmt, idx, i)
        case let b as Bool:
            sqlite3_bind_int(stmt, idx, b ? 1 : 0)
        case let d as Double:
            sqlite3_bind_double(stmt, idx, d)
        case let date as Date:
            sqlite3_bind_double(stmt, idx, date.timeIntervalSince1970)
        default:
            throw DBError.bind("unsupported \(type(of: value))")
        }
    }

    @discardableResult
    private func runStmt(_ sql: String, _ params: [Any?]) throws -> Int32 {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() { try bind(stmt, Int32(i + 1), p) }
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw DBError.step(String(cString: sqlite3_errmsg(db)))
        }
        return rc
    }

    private func textCol(_ stmt: OpaquePointer, _ i: Int32) -> String? {
        guard let cs = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: cs)
    }
    private func intCol(_ stmt: OpaquePointer, _ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
    private func doubleCol(_ stmt: OpaquePointer, _ i: Int32) -> Double? {
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, i)
    }
    private func dateCol(_ stmt: OpaquePointer, _ i: Int32) -> Date? {
        guard let d = doubleCol(stmt, i) else { return nil }
        return Date(timeIntervalSince1970: d)
    }
    private func boolCol(_ stmt: OpaquePointer, _ i: Int32) -> Bool { intCol(stmt, i) != 0 }

    // MARK: - Repo CRUD

    func insertRepo(path: String, name: String) throws -> Repo {
        let id = UUID().uuidString
        let now = Date()
        try runStmt(
            "INSERT INTO repos (id, path, name, pr_filter_query, added_at, sync_enabled) VALUES (?, ?, ?, ?, ?, 1);",
            [id, path, name, Repo.defaultPRFilterQuery, now]
        )
        return Repo(
            id: id, path: path, name: name, owner: nil, repoName: nil, defaultBranch: nil,
            prFilterQuery: Repo.defaultPRFilterQuery, addedAt: now, lastSyncedAt: nil, syncEnabled: true,
            currentBranch: nil, isDirty: false, untrackedCount: 0,
            ahead: 0, behind: 0, openPRCount: 0, failingCheckCount: 0,
            pendingCheckCount: 0
        )
    }

    func deleteRepo(id: String) throws {
        try runStmt("DELETE FROM repos WHERE id = ?;", [id])
    }

    func setSyncEnabled(id: String, enabled: Bool) throws {
        try runStmt("UPDATE repos SET sync_enabled = ? WHERE id = ?;", [enabled, id])
    }

    func setPRFilterQuery(id: String, query: String) throws {
        try runStmt("UPDATE repos SET pr_filter_query = ? WHERE id = ?;", [query, id])
    }

    func allRepos() throws -> [Repo] {
        let sql = """
        SELECT id, path, name, owner, repo_name, default_branch, pr_filter_query,
               added_at, last_synced_at, sync_enabled, current_branch, is_dirty,
               untracked_count, ahead, behind, open_pr_count, failing_check_count,
               pending_check_count
        FROM repos ORDER BY name COLLATE NOCASE;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var out: [Repo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Repo(
                id: textCol(stmt, 0) ?? "",
                path: textCol(stmt, 1) ?? "",
                name: textCol(stmt, 2) ?? "",
                owner: textCol(stmt, 3),
                repoName: textCol(stmt, 4),
                defaultBranch: textCol(stmt, 5),
                prFilterQuery: textCol(stmt, 6) ?? "",
                addedAt: dateCol(stmt, 7) ?? Date(),
                lastSyncedAt: dateCol(stmt, 8),
                syncEnabled: boolCol(stmt, 9),
                currentBranch: textCol(stmt, 10),
                isDirty: boolCol(stmt, 11),
                untrackedCount: intCol(stmt, 12),
                ahead: intCol(stmt, 13),
                behind: intCol(stmt, 14),
                openPRCount: intCol(stmt, 15),
                failingCheckCount: intCol(stmt, 16),
                pendingCheckCount: intCol(stmt, 17)
            ))
        }
        return out
    }

    func updateRepoMetadata(id: String, owner: String?, repoName: String?, defaultBranch: String?) throws {
        try runStmt(
            "UPDATE repos SET owner = ?, repo_name = ?, default_branch = ? WHERE id = ?;",
            [owner, repoName, defaultBranch, id]
        )
    }

    func updateRepoStatus(
        id: String,
        currentBranch: String?,
        isDirty: Bool,
        untrackedCount: Int,
        ahead: Int,
        behind: Int,
        openPRCount: Int,
        failingCheckCount: Int,
        pendingCheckCount: Int,
        lastSyncedAt: Date
    ) throws {
        try runStmt("""
            UPDATE repos SET
              current_branch = ?, is_dirty = ?, untracked_count = ?,
              ahead = ?, behind = ?, open_pr_count = ?, failing_check_count = ?,
              pending_check_count = ?, last_synced_at = ?
            WHERE id = ?;
        """, [currentBranch, isDirty, untrackedCount, ahead, behind, openPRCount, failingCheckCount, pendingCheckCount, lastSyncedAt, id])
    }

    /// Lighter-weight update used by CI monitoring: only PR/check counts and
    /// last-synced. Leaves git status fields alone.
    func updateRepoPRCounts(
        id: String,
        openPRCount: Int,
        failingCheckCount: Int,
        pendingCheckCount: Int,
        lastSyncedAt: Date
    ) throws {
        try runStmt("""
            UPDATE repos SET
              open_pr_count = ?, failing_check_count = ?,
              pending_check_count = ?, last_synced_at = ?
            WHERE id = ?;
        """, [openPRCount, failingCheckCount, pendingCheckCount, lastSyncedAt, id])
    }

    // MARK: - Branches / Commits / PRs / Checks

    func replaceBranches(repoID: String, branches: [Branch]) throws {
        try execSync("BEGIN;")
        do {
            try runStmt("DELETE FROM branches WHERE repo_id = ?;", [repoID])
            for b in branches {
                try runStmt("""
                    INSERT INTO branches (repo_id, name, head_sha, upstream, ahead, behind, last_commit_at, is_current)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """, [b.repoID, b.name, b.headSHA, b.upstream, b.ahead, b.behind, b.lastCommitAt, b.isCurrent])
            }
            try execSync("COMMIT;")
        } catch {
            try? execSync("ROLLBACK;")
            throw error
        }
    }

    func branches(repoID: String) throws -> [Branch] {
        let stmt = try prepare("""
            SELECT name, head_sha, upstream, ahead, behind, last_commit_at, is_current
            FROM branches WHERE repo_id = ? ORDER BY is_current DESC, name COLLATE NOCASE;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, repoID)
        var out: [Branch] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Branch(
                repoID: repoID,
                name: textCol(stmt, 0) ?? "",
                headSHA: textCol(stmt, 1) ?? "",
                upstream: textCol(stmt, 2),
                ahead: intCol(stmt, 3),
                behind: intCol(stmt, 4),
                lastCommitAt: dateCol(stmt, 5),
                isCurrent: boolCol(stmt, 6)
            ))
        }
        return out
    }

    func replaceCommits(repoID: String, commits: [Commit]) throws {
        try execSync("BEGIN;")
        do {
            try runStmt("DELETE FROM commits WHERE repo_id = ?;", [repoID])
            for c in commits {
                try runStmt("""
                    INSERT INTO commits (repo_id, sha, author, email, date, message)
                    VALUES (?, ?, ?, ?, ?, ?);
                """, [c.repoID, c.sha, c.author, c.email, c.date, c.message])
            }
            try execSync("COMMIT;")
        } catch {
            try? execSync("ROLLBACK;")
            throw error
        }
    }

    func commits(repoID: String, limit: Int = 20) throws -> [Commit] {
        let stmt = try prepare("""
            SELECT sha, author, email, date, message
            FROM commits WHERE repo_id = ? ORDER BY date DESC LIMIT ?;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, repoID)
        try bind(stmt, 2, limit)
        var out: [Commit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Commit(
                repoID: repoID,
                sha: textCol(stmt, 0) ?? "",
                author: textCol(stmt, 1) ?? "",
                email: textCol(stmt, 2) ?? "",
                date: dateCol(stmt, 3),
                message: textCol(stmt, 4) ?? ""
            ))
        }
        return out
    }

    func replacePRs(repoID: String, prs: [PullRequest], checks: [CICheck]) throws {
        try execSync("BEGIN;")
        do {
            try runStmt("DELETE FROM ci_checks WHERE repo_id = ?;", [repoID])
            try runStmt("DELETE FROM pull_requests WHERE repo_id = ?;", [repoID])
            for pr in prs {
                try runStmt("""
                    INSERT INTO pull_requests
                    (repo_id, number, title, state, is_draft, head_branch, base_branch, author, url, created_at, updated_at, merged_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, [pr.repoID, pr.number, pr.title, pr.state, pr.isDraft, pr.headBranch, pr.baseBranch, pr.author, pr.url, pr.createdAt, pr.updatedAt, pr.mergedAt])
            }
            for c in checks {
                try runStmt("""
                    INSERT OR REPLACE INTO ci_checks
                    (repo_id, pr_number, name, status, conclusion, url, completed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?);
                """, [c.repoID, c.prNumber, c.name, c.status, c.conclusion, c.url, c.completedAt])
            }
            try execSync("COMMIT;")
        } catch {
            try? execSync("ROLLBACK;")
            throw error
        }
    }

    func replaceChecks(repoID: String, prNumber: Int, checks: [CICheck]) throws {
        try execSync("BEGIN;")
        do {
            try runStmt("DELETE FROM ci_checks WHERE repo_id = ? AND pr_number = ?;", [repoID, prNumber])
            for c in checks {
                try runStmt("""
                    INSERT OR REPLACE INTO ci_checks
                    (repo_id, pr_number, name, status, conclusion, url, completed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?);
                """, [c.repoID, c.prNumber, c.name, c.status, c.conclusion, c.url, c.completedAt])
            }
            try execSync("COMMIT;")
        } catch {
            try? execSync("ROLLBACK;")
            throw error
        }
    }

    func pullRequests(repoID: String) throws -> [PullRequest] {
        let stmt = try prepare("""
            SELECT number, title, state, is_draft, head_branch, base_branch, author, url, created_at, updated_at, merged_at
            FROM pull_requests WHERE repo_id = ? ORDER BY number DESC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, repoID)
        var out: [PullRequest] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(PullRequest(
                repoID: repoID,
                number: intCol(stmt, 0),
                title: textCol(stmt, 1) ?? "",
                state: textCol(stmt, 2) ?? "OPEN",
                isDraft: boolCol(stmt, 3),
                headBranch: textCol(stmt, 4) ?? "",
                baseBranch: textCol(stmt, 5) ?? "",
                author: textCol(stmt, 6) ?? "",
                url: textCol(stmt, 7) ?? "",
                createdAt: dateCol(stmt, 8),
                updatedAt: dateCol(stmt, 9),
                mergedAt: dateCol(stmt, 10)
            ))
        }
        return out
    }

    func checks(repoID: String, prNumber: Int) throws -> [CICheck] {
        let stmt = try prepare("""
            SELECT name, status, conclusion, url, completed_at
            FROM ci_checks WHERE repo_id = ? AND pr_number = ? ORDER BY name COLLATE NOCASE;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, repoID)
        try bind(stmt, 2, prNumber)
        var out: [CICheck] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(CICheck(
                repoID: repoID,
                prNumber: prNumber,
                name: textCol(stmt, 0) ?? "",
                status: textCol(stmt, 1) ?? "",
                conclusion: textCol(stmt, 2),
                url: textCol(stmt, 3),
                completedAt: dateCol(stmt, 4)
            ))
        }
        return out
    }

    // MARK: - Diff file groups

    func diffFileGroups(repoID: String) throws -> [DiffFileGroupRecord] {
        let stmt = try prepare("""
            SELECT id, repo_id, name, branch, sort_order, created_at
            FROM diff_file_groups WHERE repo_id = ? ORDER BY sort_order ASC, created_at ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, repoID)
        var out: [DiffFileGroupRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(DiffFileGroupRecord(
                id: textCol(stmt, 0) ?? "",
                repoID: textCol(stmt, 1) ?? "",
                name: textCol(stmt, 2) ?? "",
                branch: textCol(stmt, 3),
                sortOrder: intCol(stmt, 4),
                createdAt: dateCol(stmt, 5) ?? Date()
            ))
        }
        return out
    }

    func createDiffFileGroup(repoID: String, name: String, branch: String? = nil) throws -> DiffFileGroupRecord {
        let id = UUID().uuidString
        let now = Date()
        let nextOrder = try nextDiffFileGroupSortOrder(repoID: repoID)
        try runStmt("""
            INSERT INTO diff_file_groups (id, repo_id, name, branch, sort_order, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
        """, [id, repoID, name, branch?.nilIfEmpty, nextOrder, now])
        return DiffFileGroupRecord(id: id, repoID: repoID, name: name, branch: branch, sortOrder: nextOrder, createdAt: now)
    }

    func updateDiffFileGroupBranch(id: String, branch: String?) throws {
        try runStmt("UPDATE diff_file_groups SET branch = ? WHERE id = ?;", [branch?.nilIfEmpty, id])
    }

    func diffFileGroupAssignments(repoID: String) throws -> [String: String] {
        let stmt = try prepare("SELECT file_key, group_id FROM diff_file_group_items WHERE repo_id = ?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, repoID)
        var out: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let key = textCol(stmt, 0), let groupID = textCol(stmt, 1) else { continue }
            out[key] = groupID
        }
        return out
    }

    func assignDiffFile(repoID: String, fileKey: String, to groupID: String?) throws {
        if let groupID {
            try runStmt("""
                INSERT OR REPLACE INTO diff_file_group_items (repo_id, file_key, group_id, updated_at)
                VALUES (?, ?, ?, ?);
            """, [repoID, fileKey, groupID, Date()])
        } else {
            try runStmt("DELETE FROM diff_file_group_items WHERE repo_id = ? AND file_key = ?;", [repoID, fileKey])
        }
    }

    private func nextDiffFileGroupSortOrder(repoID: String) throws -> Int {
        let stmt = try prepare("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM diff_file_groups WHERE repo_id = ?;")
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, repoID)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return intCol(stmt, 0)
        }
        return 0
    }
}

struct DiffFileGroupRecord: Identifiable, Hashable, Sendable {
    let id: String
    let repoID: String
    var name: String
    var branch: String?
    var sortOrder: Int
    var createdAt: Date
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
