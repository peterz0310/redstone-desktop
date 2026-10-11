import Foundation

struct LibraryImport {
    static func read(from url: URL) throws -> WorldLibraryDocument {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= WorldLibraryStore.maximumBytes {
            let chunk = try handle.read(upToCount: min(64 * 1024, WorldLibraryStore.maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return try decode(data)
    }
    static func decode(_ data: Data) throws -> WorldLibraryDocument {
        guard data.count <= WorldLibraryStore.maximumBytes else { throw WorldStoreError.invalidDocument("This library is too large to import (2 MB maximum).") }
        let document = try JSONDecoder().decode(WorldLibraryDocument.self, from: data)
        return try document.upgradingTerrain()
    }
    /// Imports are independent copies. Current builds, desktop assignment and permissions stay owned by this app.
    static func adding(_ incoming: WorldLibraryDocument, to existing: WorldLibraryDocument) throws -> WorldLibraryDocument {
        try incoming.validate(); try existing.validate()
        var next = existing
        var ids: [UUID: UUID] = [:]
        for var world in incoming.worlds {
            let original = world.id
            world.id = UUID(); ids[original] = world.id
            next.worlds.append(world)
        }
        for area in incoming.areas {
            next.areas.append(SavedArea(name: area.name, worldID: ids[area.worldID]!, camera: area.camera))
        }
        try next.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard try encoder.encode(next).count <= WorldLibraryStore.maximumBytes else {
            throw WorldStoreError.invalidDocument("Adding these worlds would exceed the 2 MB library limit.")
        }
        return next
    }
}
