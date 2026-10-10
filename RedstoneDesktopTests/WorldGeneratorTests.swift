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
                XCTAssertLessThan(abs(left.riverDistance - right.riverDistance), 1600)
                XCTAssertLessThan(abs(below.riverDistance - above.riverDistance), 1600)
            }
        }
    }

    func testDefaultGenerationGoldenFingerprintsFreezeFieldsTerrainAndDecorations() throws {
        XCTAssertEqual(fingerprint(try generator(42)), 15783121938156588682)
        XCTAssertEqual(fingerprint(try generator(2026)), 3694949341545218925)
    }

    func testDifferentSeedsChangeTerrainAndCoverAllSemanticTypes() throws {
        let a = try generator(42), b = try generator(2026)
        var terrain: Set<TerrainID> = [], decorations: Set<DecorationID> = [], biomes: Set<BiomeID> = []
        var differences = 0
        for y in stride(from: -768, to: 768, by: 5) {
            for x in stride(from: -768, to: 768, by: 5) {
                let coordinate = coordinate(x, y), sample = a.sample(at: coordinate)
                terrain.insert(sample.tile.terrain); biomes.insert(sample.biome)
                if let decoration = sample.tile.decoration { decorations.insert(decoration) }
                if sample.tile.terrain != b.tile(at: coordinate).terrain { differences += 1 }
                if sample.tile.terrain == .deepWater { XCTAssertNil(sample.tile.decoration) }
                if sample.tile.decoration == .reed { XCTAssertEqual(sample.tile.terrain, .shallowWater) }
                if sample.tile.decoration == .tree { XCTAssertTrue([.woodland, .plains].contains(sample.biome)) }
                if sample.tile.decoration == .pine { XCTAssertEqual(sample.tile.terrain, .snow) }
                if sample.tile.decoration == .mushroom { XCTAssertEqual(sample.biome, .woodland) }
                if sample.tile.decoration == .shrub { XCTAssertEqual(sample.biome, .savanna) }
            }
        }
        XCTAssertEqual(terrain, Set(TerrainID.allCases.filter { $0 != .dirt }))
        XCTAssertEqual(decorations, Set(DecorationID.allCases))
        XCTAssertEqual(biomes, Set(BiomeID.allCases))
        XCTAssertGreaterThan(differences, 65536 / 3)
    }

    func testSettingsRoundTripFullSeedAndRejectUnsupportedGenerationVersion() throws {
        let settings = WorldGenerationSettings(seed: .max)
        XCTAssertEqual(try JSONDecoder().decode(WorldGenerationSettings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertThrowsError(try WorldGenerator(settings: WorldGenerationSettings(generationVersion: 0, seed: 1)))
        XCTAssertThrowsError(try WorldGenerator(settings: WorldGenerationSettings(generationVersion: 3, seed: 1)))
    }

    func testRiversCrossHighGroundWithBanksAndLeaveMostLandBuildable() throws {
        let generator = try generator()
        var rivers = 0, banks = 0, dry = 0, total = 0, biomeChanges = 0
        for y in stride(from: -768, to: 768, by: 6) {
            for x in stride(from: -768, to: 768, by: 6) {
                let sample = generator.sample(at: coordinate(x, y))
                total += 1
                if !sample.tile.terrain.definition.isLiquid { dry += 1 }
                if sample.elevation >= 22300 && sample.riverDistance < 1500 {
                    rivers += 1
                    XCTAssertEqual(sample.biome, .wetland)
                    XCTAssertTrue(sample.tile.terrain.definition.isLiquid)
                }
                if sample.elevation >= 22300 && (1500..<2300).contains(sample.riverDistance) {
                    banks += 1
                    XCTAssertTrue([.gravel, .sand].contains(sample.tile.terrain))
                    XCTAssertNil(sample.tile.decoration)
                }
                if sample.biome != generator.sample(at: coordinate(x + 1, y)).biome { biomeChanges += 1 }
            }
        }
        XCTAssertGreaterThan(rivers, total / 30, "Rivers must exist independently of low-elevation lakes")
        XCTAssertGreaterThan(banks, total / 60)
        XCTAssertGreaterThan(dry, total * 2 / 3)
        XCTAssertLessThan(biomeChanges, total / 25, "Regions should not flicker between biomes every few tiles")
    }

    func testPreviousGenerationSettingsUseCurrentLandscapeWithoutHistoricalPromise() throws {
        let previous = try WorldGenerator(settings: WorldGenerationSettings(generationVersion: 1, seed: 42))
        XCTAssertEqual(WorldGenerationSettings(seed: 42).generationVersion, 2)
        XCTAssertEqual(try previous.chunk(at: ChunkCoordinate(x: -2, y: 3)), try generator().chunk(at: ChunkCoordinate(x: -2, y: 3)))
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
