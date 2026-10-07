import Foundation

/// Durable configuration only: no Finder paths, power snapshots, or pending actions.
struct LegacyWorldDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = 2
    var formatVersion = currentFormatVersion
    var generation = WorldGenerationSettings(seed: 2026)
    var fixtureVersion = 1
    var id = UUID()
    var name = "My Desktop"
    var camera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    var circuit = EditorConstructionArea.makeWorld().circuit
    var activeLevers: Set<WorldCoordinate> = []

    private enum CodingKeys: String, CodingKey { case formatVersion, fixtureVersion, generation, id, name, camera, circuit, activeLevers }

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .formatVersion)
        guard version == 1 || version == Self.currentFormatVersion else { throw WorldStoreError.unsupportedVersion(version) }
        formatVersion = Self.currentFormatVersion
        fixtureVersion = try values.decode(Int.self, forKey: .fixtureVersion)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        camera = try values.decode(CameraState.self, forKey: .camera)
        circuit = try values.decode(CircuitWorld.self, forKey: .circuit)
        activeLevers = try values.decode(Set<WorldCoordinate>.self, forKey: .activeLevers)
        // Version 1 stored the fixed fixture only. Keep those overrides and add surroundings.
        generation = version == 1 ? WorldGenerationSettings(seed: 2026) : try values.decode(WorldGenerationSettings.self, forKey: .generation)
    }

    func restoredWorld() throws -> World {
        guard formatVersion == Self.currentFormatVersion else { throw WorldStoreError.unsupportedVersion(formatVersion) }
        guard fixtureVersion == 1 else { throw WorldStoreError.invalidDocument("Unsupported terrain fixture version.") }
        guard camera.worldOrigin.x.isFinite, camera.worldOrigin.y.isFinite,
              camera.pointsPerTile.isFinite, (16...128).contains(camera.pointsPerTile),
              camera.worldOrigin.x > Double(Int.min), camera.worldOrigin.x < Double(Int.max),
              camera.worldOrigin.y > Double(Int.min), camera.worldOrigin.y < Double(Int.max) else {
            throw WorldStoreError.invalidDocument("Invalid desktop camera.")
        }
        _ = try WorldGenerator(settings: generation)
        var world = EditorConstructionArea.makeWorld()
        world.generation = generation
        world.circuit = CircuitWorld()
        for (coordinate, component) in circuit.components {
            guard PlacementRules().canPlace(component: component, at: coordinate, in: world).isAllowed else {
                throw WorldStoreError.invalidDocument("Circuit component is on an invalid tile.")
            }
            world.circuit.components[coordinate] = component
        }
        guard activeLevers.allSatisfy({ circuit.components[$0]?.kind == .lever }) else {
            throw WorldStoreError.invalidDocument("Saved lever position is not a lever.")
        }
        return world
    }
}
