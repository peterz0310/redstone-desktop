import Foundation

/// Executes only project-owned Finder queries through the public system tool, without a shell.
/// Process ownership stays on MainActor; independent pipe readers and metadata parsing do not.
@MainActor
final class FinderScriptProcess {
    private let process = Process()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var output: Task<Data, any Error>?
    private var errors: Task<Data, any Error>?
    private var deadline: Task<Void, Never>?
    private var cancelled = false
    private var timedOut = false

    static func execute(source: String, timeout: Duration = .seconds(15), outputLimit: Int = 4 * 1024 * 1024) async throws -> Data {
        let operation = FinderScriptProcess()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let data = try await operation.start(source: source, timeout: timeout, outputLimit: outputLimit)
            try Task.checkCancellation()
            return data
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }

    private func start(source: String, timeout: Duration, outputLimit: Int) async throws -> Data {
        let stdout = Pipe(), stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Source is a fixed app query/harmless test fixture, never a filename or pack-provided code.
        process.arguments = ["-l", "AppleScript", "-s", "s", "-e", source]
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in await self?.finished() }
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                guard !cancelled else { throw CancellationError() }
                try process.run()
                let outHandle = stdout.fileHandleForReading, errHandle = stderr.fileHandleForReading
                output = Task.detached(priority: .utility) { try Self.read(outHandle, limit: outputLimit) }
                errors = Task.detached(priority: .utility) { try Self.read(errHandle, limit: 64 * 1024) }
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.continuation != nil, self.process.isRunning else { return }
                    self.timedOut = true
                    self.process.terminate()
                }
            } catch {
                self.continuation = nil
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func cancel() {
        cancelled = true
        if process.isRunning { process.terminate() }
    }

    private func finished() async {
        deadline?.cancel(); deadline = nil
        guard let continuation else { return }
        self.continuation = nil
        defer { process.terminationHandler = nil; output = nil; errors = nil }
        do {
            let data = try await output?.value ?? Data()
            let stderr = try await errors?.value ?? Data()
            if cancelled { throw CancellationError() }
            if timedOut { throw FinderReadError.scriptFailure(code: -1712, message: "Finder query timed out.") }
            guard process.terminationStatus == 0 else { throw Self.failure(stderr) }
            continuation.resume(returning: data)
        } catch {
            continuation.resume(throwing: cancelled ? CancellationError() : error)
        }
    }

    nonisolated private static func read(_ handle: FileHandle, limit: Int) throws -> Data {
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 16 * 1024), !chunk.isEmpty {
            guard chunk.count <= limit - data.count else {
                throw FinderReadError.malformedResponse("Finder query exceeded its output limit.")
            }
            data.append(chunk)
        }
        return data
    }

    nonisolated static func failure(_ data: Data) -> FinderReadError {
        let text = String(decoding: data.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let code = text.range(of: #"\(-?\d+\)\s*$"#, options: .regularExpression)
            .flatMap { Int(text[$0].trimmingCharacters(in: CharacterSet(charactersIn: "() \n\r\t"))) }
        if code == -1743 { return .permissionDenied }
        return .scriptFailure(code: code, message: text.isEmpty ? "Finder query process failed." : text)
    }
}
