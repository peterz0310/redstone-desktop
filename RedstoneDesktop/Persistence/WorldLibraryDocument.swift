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
