import Foundation
import Darwin

/// App preference only. Changing routing never changes a world, power state or approval.
struct ScriptOutputSettings: Codable, Equatable, Sendable {
    var runScriptsOpenOtherItems = false

    func action(configured: OutputActionMode, occupancy: DesktopOccupancyState) -> OutputActionMode {
        guard configured == .openOccupant, runScriptsOpenOtherItems,
              case let .occupied(item) = occupancy, item.kind == .file, item.url.isFileURL,
              ["sh", "command", "zsh"].contains(item.url.pathExtension.lowercased()) else { return configured }
        return .executeOccupant
    }
}

protocol DesktopScriptAccessChecking: Sendable {
    func checkAccess() async throws
}

/// An intentional read-only access attempt uses the public macOS Files & Folders consent flow.
/// This does not enumerate Finder positions or grant permission to execute any script.
struct DesktopScriptAccess: DesktopScriptAccessChecking {
    let directory: URL
    static func applicationDefault() -> DesktopScriptAccess {
        DesktopScriptAccess(directory: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true))
    }
    func checkAccess() async throws {
        try Task.checkCancellation()
        let directory = directory
        try await Task.detached(priority: .userInitiated) {
            // Inspect only a directory entry, then discard it; never read file contents or mutate files.
            // opendir triggers real folder access without constructing an unbounded list of Desktop names.
            try Self.readDirectory(directory)
        }.value
        try Task.checkCancellation()
    }
    private static func readDirectory(_ directory: URL) throws {
        guard directory.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard let stream = directory.withUnsafeFileSystemRepresentation({ path in path.flatMap { opendir($0) } }) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { closedir(stream) }
        errno = 0
        _ = readdir(stream)
        guard errno == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
