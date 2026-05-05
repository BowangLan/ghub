import Foundation

enum ShellError: Error, CustomStringConvertible {
    case nonZeroExit(status: Int32, stderr: String)
    case notFound(String)
    case timedOut

    var description: String {
        switch self {
        case .nonZeroExit(let s, let err): return "exit \(s): \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .notFound(let name): return "executable not found: \(name)"
        case .timedOut: return "process timed out"
        }
    }
}

struct ShellOutput: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum Shell {
    /// Resolve an executable by basename, checking common Mac install dirs.
    static func resolve(_ name: String) -> String? {
        let candidates = ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        for d in candidates {
            let p = "\(d)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func run(
        _ exe: String,
        _ args: [String],
        cwd: String? = nil,
        extraEnv: [String: String] = [:]
    ) async throws -> ShellOutput {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ShellOutput, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
            var env = ProcessInfo.processInfo.environment
            // Avoid interactive pagers / colors that pollute parsing.
            env["GH_PAGER"] = ""
            env["PAGER"] = "cat"
            env["GIT_TERMINAL_PROMPT"] = "0"
            env["NO_COLOR"] = "1"
            for (k, v) in extraEnv { env[k] = v }
            p.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe

            // Drain pipes off the main thread to avoid filling the kernel buffer.
            let outBuf = LockedBuffer()
            let errBuf = LockedBuffer()
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { outBuf.append(d) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { errBuf.append(d) }
            }

            p.terminationHandler = { proc in
                // Drain anything left.
                let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !restOut.isEmpty { outBuf.append(restOut) }
                if !restErr.isEmpty { errBuf.append(restErr) }
                let stdout = String(data: outBuf.data(), encoding: .utf8) ?? ""
                let stderr = String(data: errBuf.data(), encoding: .utf8) ?? ""
                cont.resume(returning: ShellOutput(status: proc.terminationStatus, stdout: stdout, stderr: stderr))
            }

            do {
                try p.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    @discardableResult
    static func runChecked(
        _ exe: String,
        _ args: [String],
        cwd: String? = nil
    ) async throws -> String {
        let out = try await run(exe, args, cwd: cwd)
        if out.status != 0 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        return out.stdout
    }
}

private final class LockedBuffer: @unchecked Sendable {
    private var buf = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); defer { lock.unlock() }; buf.append(d) }
    func data() -> Data { lock.lock(); defer { lock.unlock() }; return buf }
}
