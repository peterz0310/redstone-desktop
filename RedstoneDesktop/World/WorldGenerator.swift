/// Version fixes all terrain scales/thresholds. Seed UI/settings expansion is later.
struct WorldGenerationSettings: Equatable, Codable, Sendable {
    var generationVersion = 1
    var seed: UInt64
}

enum WorldGenerationError: Error, Equatable {
    case unsupportedVersion(Int)
    case unrepresentableChunk
}

enum BiomeID: String, CaseIterable, Sendable {
    case plains, woodland, desert, rocky, wetland
}

struct TerrainSample: Equatable, Sendable {
    /// Fixed-point fields: 0...65535, independent of OS math libraries.
    let elevation: Int
    let moisture: Int
    let temperature: Int
    let biome: BiomeID
    let tile: Tile
}

/// Stateless coordinate sampling. No rendering, circuit, Finder, file I/O, or cache.
struct WorldGenerator: Sendable {
    let settings: WorldGenerationSettings

    init(settings: WorldGenerationSettings) throws {
        guard settings.generationVersion == 1 else { throw WorldGenerationError.unsupportedVersion(settings.generationVersion) }
        self.settings = settings
    }

    func tile(at coordinate: WorldCoordinate) -> Tile { sample(at: coordinate).tile }

    func sample(at coordinate: WorldCoordinate) -> TerrainSample {
        let seed = settings.seed
        let elevation = (SeededNoise.value(seed: seed, at: coordinate, scale: 64, channel: 1) * 3
                         + SeededNoise.value(seed: seed, at: coordinate, scale: 32, channel: 2)) / 4
        let moisture = SeededNoise.value(seed: seed, at: coordinate, scale: 128, channel: 3)
        let temperature = SeededNoise.value(seed: seed, at: coordinate, scale: 128, channel: 4)
        let variant = SeededNoise.hash(seed: seed, x: coordinate.x, y: coordinate.y, channel: 5) & 0xFFFF
        let decorationRoll = SeededNoise.hash(seed: seed, x: coordinate.x, y: coordinate.y, channel: 6) & 0xFFFF
        let biome: BiomeID
        let terrain: TerrainID
        if elevation < 28000 {
            biome = .wetland
            terrain = elevation < 24000 ? .deepWater : .shallowWater
        } else if elevation < 31000 {
            biome = .wetland; terrain = .sand
        } else if elevation > 45000 || (temperature < 22000 && elevation > 38000) {
            biome = .rocky; terrain = .stone
        } else if moisture < 22000 && temperature > 30000 {
            biome = .desert; terrain = .sand
        } else {
            biome = moisture > 38000 ? .woodland : .plains
            terrain = variant < 5000 ? .dirt : .grass
        }
        let decoration: DecorationID?
        switch terrain {
        case .grass, .dirt:
            if biome == .woodland && decorationRoll < 6000 { decoration = .tree }
            else if decorationRoll < 1500 { decoration = .flower }
            else { decoration = nil }
        case .stone: decoration = decorationRoll < 5500 ? .rock : nil
        case .sand: decoration = decorationRoll < 1500 ? .rock : nil
        case .shallowWater: decoration = elevation > 26000 && decorationRoll < 10000 ? .reed : nil
        case .deepWater: decoration = nil
        }
        return TerrainSample(elevation: elevation, moisture: moisture, temperature: temperature,
                             biome: biome, tile: Tile(terrain: terrain, decoration: decoration))
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
