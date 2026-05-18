import Foundation

enum ShellError: Error, CustomStringConvertible {
    case nonZeroExit(status: Int32, stderr: String)
    case notFound(String)
    case timedOut
    case outputLimitExceeded(limitBytes: Int)

    var description: String {
        switch self {
        case .nonZeroExit(let s, let err): return "exit \(s): \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .notFound(let name): return "executable not found: \(name)"
        case .timedOut: return "process timed out"
        case .outputLimitExceeded(let limit): return "process output exceeded \(limit) bytes"
        }
    }
}

struct ShellOutput: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum Shell {
    private static let defaultTimeout: TimeInterval = 45
    private static let defaultOutputLimitBytes = 16 * 1024 * 1024

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
        extraEnv: [String: String] = [:],
        timeout: TimeInterval = defaultTimeout,
        outputLimitBytes: Int = defaultOutputLimitBytes
    ) async throws -> ShellOutput {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ShellOutput, Error>) in
            let p = Process()
            let state = ShellRunState(continuation: cont)
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
            let outBuf = LockedBuffer(limitBytes: outputLimitBytes)
            let errBuf = LockedBuffer(limitBytes: outputLimitBytes)
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                } else if !outBuf.append(d) {
                    state.fail(ShellError.outputLimitExceeded(limitBytes: outputLimitBytes), process: p)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                } else if !errBuf.append(d) {
                    state.fail(ShellError.outputLimitExceeded(limitBytes: outputLimitBytes), process: p)
                }
            }

            p.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Drain anything left.
                let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !restOut.isEmpty, !outBuf.append(restOut) {
                    state.setFailure(ShellError.outputLimitExceeded(limitBytes: outputLimitBytes))
                }
                if !restErr.isEmpty, !errBuf.append(restErr) {
                    state.setFailure(ShellError.outputLimitExceeded(limitBytes: outputLimitBytes))
                }
                if let failure = state.failure {
                    state.resume(throwing: failure)
                    return
                }
                let stdout = String(data: outBuf.data(), encoding: .utf8) ?? ""
                let stderr = String(data: errBuf.data(), encoding: .utf8) ?? ""
                state.resume(returning: ShellOutput(status: proc.terminationStatus, stdout: stdout, stderr: stderr))
            }

            do {
                try p.run()
                if timeout > 0 {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                        state.fail(ShellError.timedOut, process: p)
                    }
                }
            } catch {
                state.resume(throwing: error)
            }
        }
    }

    @discardableResult
    static func runChecked(
        _ exe: String,
        _ args: [String],
        cwd: String? = nil,
        timeout: TimeInterval = defaultTimeout,
        outputLimitBytes: Int = defaultOutputLimitBytes
    ) async throws -> String {
        let out = try await run(exe, args, cwd: cwd, timeout: timeout, outputLimitBytes: outputLimitBytes)
        if out.status != 0 {
            throw ShellError.nonZeroExit(status: out.status, stderr: out.stderr.isEmpty ? out.stdout : out.stderr)
        }
        return out.stdout
    }
}

private final class LockedBuffer: @unchecked Sendable {
    private let limitBytes: Int
    private var buf = Data()
    private let lock = NSLock()

    init(limitBytes: Int) {
        self.limitBytes = max(1, limitBytes)
    }

    @discardableResult
    func append(_ d: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard buf.count + d.count <= limitBytes else { return false }
        buf.append(d)
        return true
    }

    func data() -> Data { lock.lock(); defer { lock.unlock() }; return buf }
}

private final class ShellRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ShellOutput, Error>?
    private var storedFailure: Error?

    init(continuation: CheckedContinuation<ShellOutput, Error>) {
        self.continuation = continuation
    }

    var failure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedFailure
    }

    func setFailure(_ error: Error) {
        lock.lock()
        if storedFailure == nil {
            storedFailure = error
        }
        lock.unlock()
    }

    func fail(_ error: Error, process: Process) {
        setFailure(error)
        if process.isRunning {
            process.terminate()
        }
    }

    func resume(returning output: ShellOutput) {
        let cont = takeContinuation()
        cont?.resume(returning: output)
    }

    func resume(throwing error: Error) {
        let cont = takeContinuation()
        cont?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<ShellOutput, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let cont = continuation
        continuation = nil
        return cont
    }
}
