import Foundation

protocol WorldStoring {
    func load() throws -> LegacyWorldDocument?
    func save(_ document: LegacyWorldDocument) throws
}

enum WorldStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidDocument(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Unsupported world format version \(version)."
        case .invalidDocument(let reason): return reason
        }
    }
}

/// Legacy format-1/2 adapter used only for migration and fixture tests. Atomic replacement never writes JSON in place.
struct WorldStore: WorldStoring {
    let fileURL: URL
    static func applicationDefault() -> WorldStore {
        WorldStore(fileURL: URL.applicationSupportDirectory
            .appendingPathComponent("RedstoneDesktop", isDirectory: true)
            .appendingPathComponent("world.json"))
    }

    func load() throws -> LegacyWorldDocument? {
        let data: Data
        do { data = try BoundedFileReader.read(fileURL, maximumBytes: 2_000_000) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        guard data.count <= 2_000_000 else { throw WorldStoreError.invalidDocument("World document is too large.") }
        let document = try JSONDecoder().decode(LegacyWorldDocument.self, from: data)
        _ = try document.restoredWorld()
        return document
    }

    func save(_ document: LegacyWorldDocument) throws {
        _ = try document.restoredWorld()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 2_000_000 else { throw WorldStoreError.invalidDocument("World document is too large.") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
