import XCTest
@testable import RedstoneDesktop

final class WorldGeneratorTests: XCTestCase {
    private func generator(_ seed: UInt64 = 42) throws -> WorldGenerator {
        try WorldGenerator(settings: WorldGenerationSettings(seed: seed))
    }
    private func coordinate(_ x: Int, _ y: Int) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    private func fingerprint(_ generator: WorldGenerator) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for y in -64..<64 {
            for x in -64..<64 {
                let sample = generator.sample(at: coordinate(x, y))
                // Semantic text rather than process-randomized Swift hashValue/dictionary order.
                let text = "\(sample.elevation),\(sample.moisture),\(sample.temperature),\(sample.biome.rawValue),\(sample.tile.terrain.rawValue),\(sample.tile.decoration?.rawValue ?? "none");"
                for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            }
        }
        return hash
    }

    func testChunkFloorDivisionIncludesNegativeBoundaries() {
        for (value, chunk) in [(-65, -3), (-64, -2), (-33, -2), (-32, -1), (-31, -1), (-1, -1), (0, 0), (31, 0), (32, 1)] {
            XCTAssertEqual(ChunkCoordinate.containing(coordinate(value, value)), ChunkCoordinate(x: chunk, y: chunk))
            let division = SeededNoise.floorDivision(value, by: 32)
            XCTAssertEqual(division.quotient * 32 + division.remainder, value)
            XCTAssertTrue((0..<32).contains(division.remainder))
        }
    }

    func testExtremeCoordinatesAndChunksDoNotOverflowOrLosePrecision() throws {
        let generator = try generator(.max)
        for coordinate in [coordinate(.min, .min), coordinate(.max, .max), coordinate(.min, .max)] {
            let chunk = try generator.chunk(at: ChunkCoordinate.containing(coordinate))
            XCTAssertEqual(chunk.tiles.count, 1024)
            XCTAssertEqual(chunk.tiles[coordinate], generator.tile(at: coordinate))
        }
        XCTAssertThrowsError(try generator.chunk(at: ChunkCoordinate(x: .max, y: 0)))
        XCTAssertThrowsError(try generator.chunk(at: ChunkCoordinate(x: .min, y: 0)))
        XCTAssertEqual(generator.sample(at: coordinate(.max, 0)), generator.sample(at: coordinate(.max, 0)))
    }

    func testNoiseRangesAndLatticeContinuityAcrossNegativeAndPositiveBoundaries() {
        for scale in [2, 32, 64, 128] {
            for x in -260...260 {
                let value = SeededNoise.value(seed: 42, at: coordinate(x, -31), scale: scale, channel: 3)
                XCTAssertTrue((0...65535).contains(value))
                if scale >= 32 {
                    let next = SeededNoise.value(seed: 42, at: coordinate(x + 1, -31), scale: scale, channel: 3)
                    XCTAssertLessThan(abs(value - next), 3100)
                }
            }
            let lattice = SeededNoise.value(seed: 42, at: coordinate(-scale, scale), scale: scale, channel: 3)
            XCTAssertEqual(lattice, Int(SeededNoise.hash(seed: 42, x: -1, y: 1, channel: 3) & 0xFFFF))
        }
    }

    func testGlobalSamplesAreIndependentOfRequestOrderAndChunkBoundaries() throws {
        let generator = try generator()
        let chunks = [ChunkCoordinate(x: -1, y: -1), ChunkCoordinate(x: 0, y: -1),
                      ChunkCoordinate(x: -1, y: 0), ChunkCoordinate(x: 0, y: 0)]
        var merged: [WorldCoordinate: Tile] = [:]
        for coordinate in chunks.reversed() {
            let chunk = try generator.chunk(at: coordinate)
            for (position, tile) in chunk.tiles {
                XCTAssertNil(merged[position])
                XCTAssertEqual(tile, generator.tile(at: position))
                merged[position] = tile
            }
        }
        XCTAssertEqual(merged.count, 4096)
        for y in -32..<32 {
            for x in -32..<32 { XCTAssertEqual(merged[coordinate(x, y)], try self.generator().tile(at: coordinate(x, y))) }
        }
    }

    func testNeighborChunksShareGlobalNoiseWithoutBoundaryJumps() throws {
        let generator = try generator()
        for boundary in [-64, -32, 0, 32, 64] {
            for other in -64..<64 {
                let left = generator.sample(at: coordinate(boundary - 1, other))
                let right = generator.sample(at: coordinate(boundary, other))
                let below = generator.sample(at: coordinate(other, boundary - 1))
                let above = generator.sample(at: coordinate(other, boundary))
                XCTAssertLessThan(abs(left.elevation - right.elevation), 3100)
                XCTAssertLessThan(abs(below.elevation - above.elevation), 3100)
                XCTAssertLessThan(abs(left.moisture - right.moisture), 800)
            }
        }
    }

    func testVersionOneGoldenFingerprintsFreezeFieldsTerrainAndDecorations() throws {
        XCTAssertEqual(fingerprint(try generator(42)), 17498966041026583072)
        XCTAssertEqual(fingerprint(try generator(2026)), 5051880354807136252)
    }

    func testDifferentSeedsChangeTerrainAndCoverAllSemanticTypes() throws {
        let a = try generator(42), b = try generator(2026)
        var terrain: Set<TerrainID> = [], decorations: Set<DecorationID> = [], biomes: Set<BiomeID> = []
        var differences = 0
        for y in -128..<128 {
            for x in -128..<128 {
                let coordinate = coordinate(x, y), sample = a.sample(at: coordinate)
                terrain.insert(sample.tile.terrain); biomes.insert(sample.biome)
                if let decoration = sample.tile.decoration { decorations.insert(decoration) }
                if sample.tile.terrain != b.tile(at: coordinate).terrain { differences += 1 }
                if sample.tile.terrain == .deepWater { XCTAssertNil(sample.tile.decoration) }
                if sample.tile.decoration == .reed { XCTAssertEqual(sample.tile.terrain, .shallowWater) }
                if sample.tile.decoration == .tree { XCTAssertEqual(sample.biome, .woodland) }
            }
        }
        XCTAssertEqual(terrain, Set(TerrainID.allCases))
        XCTAssertEqual(decorations, Set(DecorationID.allCases))
        XCTAssertEqual(biomes, Set(BiomeID.allCases))
        XCTAssertGreaterThan(differences, 65536 / 3)
    }

    func testSettingsRoundTripFullSeedAndRejectUnsupportedGenerationVersion() throws {
        let settings = WorldGenerationSettings(seed: .max)
        XCTAssertEqual(try JSONDecoder().decode(WorldGenerationSettings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertThrowsError(try WorldGenerator(settings: WorldGenerationSettings(generationVersion: 0, seed: 1)))
        XCTAssertThrowsError(try WorldGenerator(settings: WorldGenerationSettings(generationVersion: 2, seed: 1)))
    }

    func testGeneratedWorldUsesExistingPlacementCapabilitiesWithoutChangingCircuit() throws {
        let chunk = try generator().chunk(at: ChunkCoordinate(x: 0, y: 0))
        let world = World(tiles: chunk.tiles)
        XCTAssertTrue(world.circuit.components.isEmpty)
        for (coordinate, tile) in chunk.tiles {
            let result = PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: coordinate, in: world)
            XCTAssertEqual(result.isAllowed, !tile.terrain.definition.isLiquid && tile.decoration == nil)
        }
        XCTAssertEqual(EditorConstructionArea.makeWorld().circuit, DemoCircuit.makeWorld().circuit)
    }
}
