import Foundation

protocol WorldLibraryStoring {
    /// Returns a validated library, migrating the legacy save first when necessary.
    func load() throws -> WorldLibraryDocument?
    func save(_ document: WorldLibraryDocument) throws
}

/// One atomic transaction includes every world, its areas, and active assignment.
struct WorldLibraryStore: WorldLibraryStoring {
    let fileURL: URL
    let legacyFileURL: URL
    static let maximumBytes = 2_000_000

    static func applicationDefault() -> WorldLibraryStore {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("RedstoneDesktop", isDirectory: true)
        return WorldLibraryStore(fileURL: directory.appendingPathComponent("library.json"), legacyFileURL: directory.appendingPathComponent("world.json"))
    }

    func load() throws -> WorldLibraryDocument? {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            guard let legacy = try WorldStore(fileURL: legacyFileURL).load() else { return nil }
            let library = try WorldLibraryDocument(legacy: legacy)
            try save(library)
            return library
        }
        guard data.count <= Self.maximumBytes else { throw WorldStoreError.invalidDocument("Library document is too large.") }
        let decoded = try JSONDecoder().decode(WorldLibraryDocument.self, from: data)
        let library = try decoded.upgradingTerrain()
        if library != decoded {
            // Exact source bytes are retained before an atomic, validated replacement.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard try encoder.encode(library).count <= Self.maximumBytes else { throw WorldStoreError.invalidDocument("Upgraded library exceeds the 2 MB limit.") }
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("library-before-terrain-upgrade-\(UUID().uuidString).json")
            try data.write(to: backup, options: .atomic)
            try save(library)
        }
        return library
    }

    func save(_ document: WorldLibraryDocument) throws {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumBytes else { throw WorldStoreError.invalidDocument("Library exceeds the 2 MB limit.") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
