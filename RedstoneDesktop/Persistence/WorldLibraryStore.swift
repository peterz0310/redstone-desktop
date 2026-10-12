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
        do { data = try BoundedFileReader.read(fileURL, maximumBytes: Self.maximumBytes) }
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

    /// One encoding contract for edits, disk saves, exports and imports. Callers validate structure separately.
    static func encodedData(_ document: WorldLibraryDocument, maximumBytes limit: Int = maximumBytes) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= limit else {
            throw WorldStoreError.invalidDocument("This change would exceed the 2 MB library limit. Remove unused worlds or restore painted terrain to make room.")
        }
        return data
    }

    func save(_ document: WorldLibraryDocument) throws {
        try document.validate()
        let data = try Self.encodedData(document)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
