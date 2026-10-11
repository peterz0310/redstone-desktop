import Foundation

enum TerrainProfile: String, Codable, Sendable { case procedural, legacyFixtureV1 }

/// A map owns its components. Camera bookmarks belong to SavedArea, not the map.
struct WorldDocument: Codable, Equatable, Sendable, Identifiable {
    static let currentFormatVersion = 5
    var formatVersion = currentFormatVersion
    var id = UUID()
    var name: String
    var generation: WorldGenerationSettings
    let terrainProfile: TerrainProfile
    var circuit = CircuitWorld()
    var terrainOverrides: [WorldCoordinate: Tile] = [:]
    var lighting = WorldLightingSettings()
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

    private enum CodingKeys: String, CodingKey { case formatVersion, id, name, generation, terrainProfile, circuit, activeLevers, terrainOverrides, lighting }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .formatVersion)
        guard (3...Self.currentFormatVersion).contains(version) else { throw WorldStoreError.unsupportedVersion(version) }
        formatVersion = Self.currentFormatVersion
        id = try values.decode(UUID.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        generation = try values.decode(WorldGenerationSettings.self, forKey: .generation)
        terrainProfile = try values.decode(TerrainProfile.self, forKey: .terrainProfile)
        circuit = try values.decode(CircuitWorld.self, forKey: .circuit)
        activeLevers = try values.decode(Set<WorldCoordinate>.self, forKey: .activeLevers)
        lighting = version < 5 ? try values.decodeIfPresent(WorldLightingSettings.self, forKey: .lighting) ?? WorldLightingSettings() : try values.decode(WorldLightingSettings.self, forKey: .lighting)
        terrainOverrides = try values.decodeIfPresent([WorldCoordinate: Tile].self, forKey: .terrainOverrides) ?? [:]
    }
    func unmodifiedWorld() -> World {
        var world = terrainProfile == .legacyFixtureV1 ? EditorConstructionArea.makeWorld() : World()
        world.lighting = lighting
        world.generation = generation; world.circuit = CircuitWorld()
        return world
    }

    func restoredWorld() throws -> World {
        guard formatVersion == Self.currentFormatVersion else { throw WorldStoreError.unsupportedVersion(formatVersion) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorldStoreError.invalidDocument("World name cannot be empty.") }
        try lighting.validate()
        _ = try WorldGenerator(settings: generation)
        guard terrainOverrides.count <= TerrainEditing.maximumSavedTiles else { throw WorldStoreError.invalidDocument("Too many edited terrain tiles.") }
        var world = unmodifiedWorld()
        for (coordinate, tile) in terrainOverrides { world.tiles[coordinate] = tile; world.unspecifiedTiles.remove(coordinate) }
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
