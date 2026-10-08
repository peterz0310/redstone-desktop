import Foundation
import CryptoKit

struct ScriptTarget: Equatable, Sendable {
    let url: URL
    let interpreter: URL
    let fingerprint: String
    var authorizationKey: String { url.path + "\n" + fingerprint }
    var arguments: [String] { interpreter.lastPathComponent == "zsh" ? ["-f", "--", url.path] : ["--", url.path] }

    static func resolve(_ item: DesktopItem) throws -> ScriptTarget {
        guard item.url.isFileURL, item.kind == .file else { throw ScriptError.invalidTarget("Choose a local script file, not a folder, app or alias.") }
        let url = item.url.standardizedFileURL.resolvingSymlinksInPath()
        let ext = url.pathExtension.lowercased()
        guard ["sh", "command", "zsh"].contains(ext) else { throw ScriptError.invalidTarget("Supported scripts: .sh, .command and .zsh.") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .fileResourceIdentifierKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 1024 * 1024,
              FileManager.default.isReadableFile(atPath: url.path) else { throw ScriptError.invalidTarget("Script must be a readable regular file of at most 1 MiB.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard data.count == size else { throw ScriptError.invalidTarget("Script changed while it was being read; try again.") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fingerprint = "\(String(describing: values.fileResourceIdentifier)):\(digest)"
        return ScriptTarget(url: url, interpreter: URL(fileURLWithPath: ext == "zsh" ? "/bin/zsh" : "/bin/sh"), fingerprint: fingerprint)
    }
}

enum ScriptError: LocalizedError {
    case invalidTarget(String), timeout
    var errorDescription: String? {
        switch self {
        case let .invalidTarget(message): return message
        case .timeout: return "Script exceeded the execution timeout."
        }
    }
}

struct ScriptExecutionResult: Equatable, Sendable {
    let path: String
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let duration: Double
    let truncated: Bool
}

@MainActor
protocol ScriptExecuting {
    func execute(_ target: ScriptTarget) async throws -> ScriptExecutionResult
}
