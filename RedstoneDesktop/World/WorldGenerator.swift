/// Generation 2 is the default landscape. Version 1 saves use the improved
/// landscape too; historical terrain positions are intentionally not preserved.
struct WorldGenerationSettings: Equatable, Codable, Sendable {
    var generationVersion = 2
    var seed: UInt64
}

enum WorldGenerationError: Error, Equatable {
    case unsupportedVersion(Int)
    case unrepresentableChunk
}

enum BiomeID: String, CaseIterable, Sendable {
    case plains, woodland, desert, rocky, wetland, meadow, savanna, alpine
}

struct TerrainSample: Equatable, Sendable {
    /// Fixed-point fields: 0...65535, independent of OS math libraries.
    let elevation: Int
    let moisture: Int
    let temperature: Int
    let biome: BiomeID
    /// Distance to the winding river contour, in noise units. Not water flow.
    let riverDistance: Int
    var tile: Tile
}

/// Stateless coordinate sampling. No rendering, circuit, Finder, file I/O, or cache.
struct WorldGenerator: Sendable {
    let settings: WorldGenerationSettings

    init(settings: WorldGenerationSettings) throws {
        guard (1...2).contains(settings.generationVersion) else { throw WorldGenerationError.unsupportedVersion(settings.generationVersion) }
        self.settings = settings
    }

    func tile(at coordinate: WorldCoordinate) -> Tile { sample(at: coordinate).tile }

    func sample(at coordinate: WorldCoordinate) -> TerrainSample {
        var ground = groundSample(at: coordinate)
        guard [.grass, .snow].contains(ground.tile.terrain),
              let center = TreeCanopy.center(near: coordinate, seed: settings.seed) else { return ground }
        let site = center == coordinate ? ground : groundSample(at: center)
        guard site.tile.terrain == ground.tile.terrain else { return ground }
        let groves = SeededNoise.value(seed: settings.seed, at: center, scale: 40, channel: 10)
        let roll = SeededNoise.hash(seed: settings.seed, x: center.x, y: center.y, channel: 0x7EED) % 100
        let pine = site.biome == .alpine && groves > 27000 && roll < 65
        let oak = (site.biome == .woodland && roll < (groves > 32000 ? 85 : 15))
            || (site.biome == .plains && groves > 48000 && roll < 25)
        if pine { ground.tile.decoration = center == coordinate ? .pine : .pineLeaves }
        else if oak { ground.tile.decoration = center == coordinate ? .tree : .treeLeaves }
        return ground
    }

    private func groundSample(at coordinate: WorldCoordinate) -> TerrainSample {
        let seed = settings.seed
        func noise(_ scale: Int, _ channel: UInt64) -> Int {
            SeededNoise.value(seed: seed, at: coordinate, scale: scale, channel: channel)
        }
        let elevation = (noise(128, 1) * 3 + noise(48, 2)) / 4
        let moisture = noise(224, 3)
        let temperature = noise(256, 4)
        let detail = noise(24, 9)
        let groves = noise(40, 10)
        // A continuous contour with finer bends gives rivers independent of low
        // elevation lakes. Sampling global coordinates prevents chunk seams.
        let riverDistance = abs(noise(160, 7) - 32768 + (noise(48, 8) - 32768) / 5)
        let roll = Int(SeededNoise.hash(seed: seed, x: coordinate.x, y: coordinate.y, channel: 6) & 0xFFFF)
        let biome: BiomeID
        let terrain: TerrainID
        if elevation < 20500 {
            biome = .wetland; terrain = elevation < 16500 ? .deepWater : .shallowWater
        } else if riverDistance < 1500 {
            biome = .wetland; terrain = riverDistance < 500 ? .deepWater : .shallowWater
        } else if elevation < 22300 || riverDistance < 2300 {
            biome = .wetland; terrain = temperature > 39000 && moisture < 27000 ? .sand : .gravel
        } else if temperature < 20000 || (elevation > 47500 && temperature < 36000) {
            biome = .alpine; terrain = detail > 49000 ? .stone : .snow
        } else if elevation > 47000 {
            biome = .rocky; terrain = detail < 17000 ? .gravel : .stone
        } else if moisture < 23500 && temperature > 36500 {
            biome = .desert; terrain = .sand
        } else if moisture < 29000 && temperature > 31000 {
            biome = .savanna; terrain = .dryGrass
        } else if moisture > 39500 {
            biome = .woodland; terrain = .grass
        } else if moisture > 30000 && temperature < 39000 {
            biome = .meadow; terrain = .grass
        } else {
            biome = .plains; terrain = .grass
        }
        let decoration: DecorationID?
        switch biome {
        case .woodland:
            if roll > 62000 && groves > 35000 { decoration = .mushroom }
            else if roll < 11000 && groves < 32000 { decoration = .flower }
            else { decoration = nil }
        case .meadow: decoration = roll < (detail > 28000 ? 9000 : 2000) ? .flower : nil
        case .plains:
            decoration = roll < 1600 ? .flower : nil
        case .savanna: decoration = roll < 2200 ? .shrub : nil
        case .alpine: decoration = nil
        case .rocky: decoration = terrain == .stone && roll < 4800 ? .rock : nil
        case .desert: decoration = roll < 2000 ? .rock : nil // cactus appearance on sand
        case .wetland: decoration = terrain == .shallowWater && roll < 6000 ? .reed : nil
        }
        return TerrainSample(elevation: elevation, moisture: moisture, temperature: temperature,
                             biome: biome, riverDistance: riverDistance, tile: Tile(terrain: terrain, decoration: decoration))
    }

    func chunk(at coordinate: ChunkCoordinate) throws -> TerrainChunk {
        guard let origin = coordinate.worldOrigin else { throw WorldGenerationError.unrepresentableChunk }
        var tiles: [WorldCoordinate: Tile] = [:]
        tiles.reserveCapacity(ChunkCoordinate.size * ChunkCoordinate.size)
        for y in 0..<ChunkCoordinate.size {
            for x in 0..<ChunkCoordinate.size {
                let position = WorldCoordinate(x: origin.x + x, y: origin.y + y)
                tiles[position] = tile(at: position)
            }
        }
        return TerrainChunk(coordinate: coordinate, tiles: tiles)
    }
}
