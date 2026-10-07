import Foundation

struct WorldLibraryDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    var formatVersion = currentFormatVersion
    var worlds: [WorldDocument]
    var areas: [SavedArea]
    var activeAreaID: UUID

    init(world: WorldDocument = WorldDocument(), camera: CameraState = SavedArea.homeCamera, areaName: String = "Home") {
        let area = SavedArea(name: areaName, worldID: world.id, camera: camera)
        worlds = [world]; areas = [area]; activeAreaID = area.id
    }

    init(legacy: LegacyWorldDocument) throws {
        self.init(world: try WorldDocument(legacy: legacy), camera: legacy.camera, areaName: "Desktop")
        try validate()
    }

    var activeArea: SavedArea? { areas.first { $0.id == activeAreaID } }
    func world(id: UUID) -> WorldDocument? { worlds.first { $0.id == id } }

    func deletionRestriction(worldID: UUID) -> String? {
        guard worlds.contains(where: { $0.id == worldID }) else { return "World no longer exists." }
        guard worlds.count > 1 else { return "Keep at least one world." }
        guard activeArea?.worldID != worldID else { return "Activate an area in another world before deleting this desktop world." }
        return nil
    }

    func deletionRestriction(areaID: UUID) -> String? {
        guard let area = areas.first(where: { $0.id == areaID }) else { return "Area no longer exists." }
        guard areaID != activeAreaID else { return "Activate another area before deleting this desktop area." }
        guard areas.filter({ $0.worldID == area.worldID }).count > 1 else { return "Keep at least one area in each world." }
        return nil
    }

    func deletingWorld(_ id: UUID) throws -> Self {
        if let reason = deletionRestriction(worldID: id) { throw WorldStoreError.invalidDocument(reason) }
        var next = self
        next.worlds.removeAll { $0.id == id }
        next.areas.removeAll { $0.worldID == id }
        try next.validate()
        return next
    }

    func deletingArea(_ id: UUID) throws -> Self {
        if let reason = deletionRestriction(areaID: id) { throw WorldStoreError.invalidDocument(reason) }
        var next = self
        next.areas.removeAll { $0.id == id }
        try next.validate()
        return next
    }

    func validate() throws {
        guard formatVersion == Self.currentFormatVersion else { throw WorldStoreError.unsupportedVersion(formatVersion) }
        let worldIDs = Set(worlds.map(\.id))
        guard !worlds.isEmpty, worldIDs.count == worlds.count,
              Set(areas.map(\.id)).count == areas.count,
              activeArea != nil,
              areas.allSatisfy({ worldIDs.contains($0.worldID) }),
              worlds.allSatisfy({ world in areas.contains { $0.worldID == world.id } }) else {
            throw WorldStoreError.invalidDocument("Library has duplicate IDs or missing world/area references.")
        }
        for world in worlds { _ = try world.restoredWorld() }
        for area in areas { try area.validate() }
    }
}
