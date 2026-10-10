import XCTest
@testable import RedstoneDesktop

final class LavaPoolTests: XCTestCase {
    func testPoolsAreRareDryBiomeFeaturesWithoutDecorationsAndMatchChunks() throws {
        let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: 42))
        var lava: [WorldCoordinate] = [], total = 0
        for y in stride(from: -512, to: 512, by: 4) { for x in stride(from: -512, to: 512, by: 4) {
            let coordinate = WorldCoordinate(x: x, y: y), sample = generator.sample(at: coordinate)
            total += 1
            if sample.tile.terrain == .lava {
                lava.append(coordinate)
                XCTAssertTrue([BiomeID.desert, .rocky, .savanna].contains(sample.biome))
                XCTAssertNil(sample.tile.decoration)
                XCTAssertTrue(LavaPool.contains(coordinate, seed: 42))
            }
        } }
        XCTAssertGreaterThan(lava.count, 0)
        XCTAssertLessThan(Double(lava.count) / Double(total), 0.005)
        let found = try XCTUnwrap(lava.first)
        let chunk = try generator.chunk(at: ChunkCoordinate.containing(found))
        XCTAssertEqual(chunk.tiles[found], generator.tile(at: found))
        let neighbors = try TerrainEditing.footprint(center: found, size: 3)
        XCTAssertGreaterThan(neighbors.filter { generator.tile(at: $0).terrain == .lava }.count, 1)
        for point in [WorldCoordinate(x: Int.min, y: Int.max), WorldCoordinate(x: -1, y: -1)] {
            XCTAssertEqual(LavaPool.contains(point, seed: .max), LavaPool.contains(point, seed: .max))
            XCTAssertEqual(generator.tile(at: point), generator.tile(at: point))
        }
    }

    func testLavaBrushPersistsProtectsCircuitsAndRestoresOriginalTerrain() throws {
        var document = WorldDocument(name: "Lava test", terrainProfile: .legacyFixtureV1)
        let protected = WorldCoordinate(x: 16, y: 9), painted = WorldCoordinate(x: 17, y: 9)
        document.circuit.components[protected] = CircuitComponent(kind: .lever)
        let plan = try TerrainEditing.plan(document: document, brush: .lava, tiles: [protected, painted])
        XCTAssertEqual(plan.protected, [protected]); XCTAssertEqual(plan.changed, [painted])
        XCTAssertEqual(plan.world.tile(at: painted), Tile(terrain: .lava))
        document.terrainOverrides = plan.overrides
        let restored = try JSONDecoder().decode(WorldDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(try restored.restoredWorld().tile(at: painted)?.terrain, .lava)
        XCTAssertFalse(PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: painted, in: plan.world).isAllowed)
        XCTAssertEqual(try TerrainEditing.plan(document: restored, brush: .restore, tiles: [painted]).world.tile(at: painted), document.unmodifiedWorld().tile(at: painted))
    }
}
