import Foundation

enum TerrainProfile: String, Codable, Sendable { case procedural, legacyFixtureV1 }

/// A map owns its components. Camera bookmarks belong to SavedArea, not the map.
struct WorldDocument: Codable, Equatable, Sendable, Identifiable {
    static let currentFormatVersion = 3
    var formatVersion = currentFormatVersion
    var id = UUID()
    var name: String
    let generation: WorldGenerationSettings
    let terrainProfile: TerrainProfile
    var circuit = CircuitWorld()
    var activeLevers: Set<WorldCoordinate> = []

    init(name: String = "New World", generation: WorldGenerationSettings = WorldGenerationSettings(seed: 2026), terrainProfile: TerrainProfile = .procedural) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.generation = generation
        self.terrainProfile = terrainProfile
    }

    init(legacy: LegacyWorldDocument) throws {
        _ = try legacy.restoredWorld()
        self.init(name: legacy.name, generation: legacy.generation, terrainProfile: .legacyFixtureV1)
        id = legacy.id
        name = legacy.name // Preserve the earlier saved label exactly during migration.
        circuit = legacy.circuit
        activeLevers = legacy.activeLevers
    }

    func restoredWorld() throws -> World {
        guard formatVersion == Self.currentFormatVersion else { throw WorldStoreError.unsupportedVersion(formatVersion) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorldStoreError.invalidDocument("World name cannot be empty.") }
        _ = try WorldGenerator(settings: generation)
        var world = terrainProfile == .legacyFixtureV1 ? EditorConstructionArea.makeWorld() : World()
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
