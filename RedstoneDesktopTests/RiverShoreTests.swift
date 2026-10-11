import XCTest
@testable import RedstoneDesktop

final class RiverShoreTests: XCTestCase {
    func testWideRiverHasOnlyOneOrTwoShallowTilesOnEitherBank() {
        for width in [1, 2] {
            let water: (WorldCoordinate) -> Bool = { (0..<20).contains($0.x) }
            let shallow = (0..<20).filter { RiverShore.isShallow(at: WorldCoordinate(x: $0, y: -32), width: width, isWater: water) }
            XCTAssertEqual(shallow, Array(0..<width) + Array((20 - width)..<20))
            XCTAssertGreaterThan(20 - shallow.count, shallow.count)
        }
    }
    func testCurvesAndChunkEdgesUseNeighboringWaterAndHandleIntegerLimits() {
        XCTAssertTrue(RiverShore.isShallow(at: WorldCoordinate(x: 31, y: -1), width: 2) { $0 != WorldCoordinate(x: 33, y: 0) })
        XCTAssertFalse(RiverShore.isShallow(at: WorldCoordinate(x: 31, y: -1), width: 1) { $0 != WorldCoordinate(x: 33, y: 0) })
        XCTAssertFalse(RiverShore.isShallow(at: WorldCoordinate(x: .max, y: .min), width: 2) { _ in true })
    }
    func testGeneratedRiversHaveDeepMajorityAndShallowsWithinTwoTilesOfDryBanks() throws {
        let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: 42))
        var deep = 0, shallow = 0
        for y in -128..<128 { for x in -128..<128 {
            let coordinate = WorldCoordinate(x: x, y: y), sample = generator.sample(at: coordinate)
            guard sample.elevation >= 20500, sample.riverDistance < 1500 else { continue }
            if sample.tile.terrain == .deepWater { deep += 1 }
            else {
                XCTAssertEqual(sample.tile.terrain, .shallowWater); shallow += 1
                XCTAssertTrue(RiverShore.isShallow(at: coordinate, width: 2) { generator.tile(at: $0).terrain.definition.isLiquid })
            }
        } }
        XCTAssertGreaterThan(shallow, 0); XCTAssertGreaterThan(deep, shallow)
        // Water extent is unchanged, preserving the land available to saved circuits.
        for y in stride(from: -128, to: 128, by: 3) { for x in stride(from: -128, to: 128, by: 3) {
            let sample = generator.sample(at: WorldCoordinate(x: x, y: y))
            XCTAssertEqual([TerrainID.shallowWater, .deepWater].contains(sample.tile.terrain), sample.elevation < 20500 || sample.riverDistance < 1500)
        } }
    }
}
