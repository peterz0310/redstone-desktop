import Foundation
import Darwin

/// The action adapter launches a fixed interpreter with a path argument, never a shell command string.
@MainActor
final class ScriptProcess: ScriptExecuting {
    private let timeout: Duration
    private let captureLimit: Int
    init(timeout: Duration = .seconds(30), captureLimit: Int = 1024 * 1024) {
        self.timeout = timeout
        self.captureLimit = captureLimit
    }
    func execute(_ target: ScriptTarget) async throws -> ScriptExecutionResult {
        let operation = Operation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result = try await operation.start(target, timeout: timeout, limit: captureLimit)
            try Task.checkCancellation()
            return result
        } onCancel: { Task { @MainActor in operation.stop() } }
    }

    @MainActor
    private final class Operation {
        let process = Process()
        var continuation: CheckedContinuation<ScriptExecutionResult, any Error>?
        var stdout: Task<Capture, any Error>?
        var stderr: Task<Capture, any Error>?
        var deadline: Task<Void, Never>?
        var escalation: Task<Void, Never>?
        var cancelled = false
        var timedOut = false
        let clock = ContinuousClock()
        var started = ContinuousClock.now
        var path = ""

        func start(_ target: ScriptTarget, timeout: Duration, limit: Int) async throws -> ScriptExecutionResult {
            let out = Pipe(), err = Pipe()
            path = target.url.path
            process.executableURL = target.interpreter
            process.arguments = target.arguments
            process.currentDirectoryURL = target.url.deletingLastPathComponent()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { [weak self] _ in Task { @MainActor [weak self] in await self?.finished() } }
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                do {
                    guard !cancelled else { throw CancellationError() }
                    started = clock.now
                    try process.run()
                    let outHandle = out.fileHandleForReading, errHandle = err.fileHandleForReading
                    stdout = Task.detached(priority: .utility) { try await Self.capture(outHandle, limit: limit) }
                    stderr = Task.detached(priority: .utility) { try await Self.capture(errHandle, limit: limit) }
                    deadline = Task { @MainActor [weak self] in
                        do { try await Task.sleep(for: timeout) } catch { return }
                        guard let self, self.process.isRunning else { return }
                        self.timedOut = true
                        self.terminate()
                    }
                } catch {
                    self.continuation = nil
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
        func stop() { cancelled = true; terminate() }
        func terminate() {
            guard process.isRunning else { return }
            process.terminate()
            guard escalation == nil else { return }
            escalation = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, self.process.isRunning else { return }
                // Public POSIX kill, directed only to our still-running child, without privilege elevation.
                Darwin.kill(self.process.processIdentifier, SIGKILL)
            }
        }
        func finished() async {
            guard let continuation else { return }
            self.continuation = nil
            deadline?.cancel(); escalation?.cancel()
            stdout?.cancel(); stderr?.cancel()
            defer { process.terminationHandler = nil; stdout = nil; stderr = nil; deadline = nil; escalation = nil }
            do {
                let out = try await stdout?.value ?? Capture(data: Data(), truncated: false)
                let err = try await stderr?.value ?? Capture(data: Data(), truncated: false)
                if cancelled { throw CancellationError() }
                if timedOut { throw ScriptError.timeout }
                let duration = started.duration(to: clock.now).components
                continuation.resume(returning: ScriptExecutionResult(path: path,
                    stdout: String(decoding: out.data, as: UTF8.self), stderr: String(decoding: err.data, as: UTF8.self),
                    exitCode: process.terminationStatus,
                    duration: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
                    truncated: out.truncated || err.truncated))
            } catch { continuation.resume(throwing: cancelled ? CancellationError() : error) }
        }
        struct Capture: Sendable { let data: Data; let truncated: Bool }
        nonisolated static func capture(_ handle: FileHandle, limit: Int) async throws -> Capture {
            defer { try? handle.close() }
            let fd = handle.fileDescriptor
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else { throw POSIXError(.EIO) }
            var data = Data(), truncated = false
            var drainedAfterCancellation = 0
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count > 0 {
                    if Task.isCancelled {
                        drainedAfterCancellation += count
                        if drainedAfterCancellation > 1024 * 1024 { truncated = true; break }
                    }
                    let retained = min(count, max(0, limit - data.count))
                    data.append(contentsOf: buffer.prefix(retained))
                    if retained < count { truncated = true }
                    continue
                }
                if count == 0 { break }
                if errno == EINTR { continue }
                guard errno == EAGAIN || errno == EWOULDBLOCK else { throw POSIXError(.EIO) }
                // Drain available data at termination, then stop: descendants cannot keep our pipe wait alive.
                if Task.isCancelled { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return Capture(data: data, truncated: truncated)
        }
    }
}
