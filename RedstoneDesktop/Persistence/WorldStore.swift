import Foundation

protocol WorldStoring {
    func load() throws -> WorldDocument?
    func save(_ document: WorldDocument) throws
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

/// Foundation file adapter. Atomic replacement never writes JSON in place.
struct WorldStore: WorldStoring {
    let fileURL: URL
    static func applicationDefault() -> WorldStore {
        WorldStore(fileURL: URL.applicationSupportDirectory
            .appendingPathComponent("RedstoneDesktop", isDirectory: true)
            .appendingPathComponent("world.json"))
    }

    func load() throws -> WorldDocument? {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        guard data.count <= 2_000_000 else { throw WorldStoreError.invalidDocument("World document is too large.") }
        let document = try JSONDecoder().decode(WorldDocument.self, from: data)
        _ = try document.restoredWorld()
        return document
    }

    func save(_ document: WorldDocument) throws {
        _ = try document.restoredWorld()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 2_000_000 else { throw WorldStoreError.invalidDocument("World document is too large.") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
