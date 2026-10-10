import XCTest
@testable import RedstoneDesktop

final class TreeCanopyTests: XCTestCase {
    private func neighbors(_ center: WorldCoordinate) -> [WorldCoordinate] {
        [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)].map { WorldCoordinate(x: center.x + $0.0, y: center.y + $0.1) }
    }

    func testPlantingCellsKeepRequiredCrossWithinVariableThreeByThreeCanopies() {
        for origin in [-192, -6, 0, 30, 192] {
            let coordinates = (origin..<origin + 6).flatMap { y in (origin..<origin + 6).map { WorldCoordinate(x: $0, y: y) } }
            let sites = coordinates.compactMap { TreeCanopy.center(near: $0, seed: 42) }
            XCTAssertTrue((5...9).contains(sites.count))
            XCTAssertEqual(Set(sites).count, 1)
            let center = sites[0]
            let footprint = Set(coordinates.filter { TreeCanopy.center(near: $0, seed: 42) != nil })
            XCTAssertTrue(Set(neighbors(center)).isSubset(of: footprint))
            XCTAssertTrue(footprint.allSatisfy { abs($0.x - center.x) <= 1 && abs($0.y - center.y) <= 1 })
        }
        for x in [Int.min, Int.max] {
            _ = TreeCanopy.center(near: WorldCoordinate(x: x, y: x), seed: .max)
        }
    }

    func testCornerShapesVaryByTreeAndSeedButNeverBySamplingOrder() {
        var shapes: Set<Int> = []
        var seedDifferences = 0
        for origin in stride(from: -384, through: 384, by: 6) {
            let coordinates = (origin..<origin + 6).flatMap { y in (origin..<origin + 6).map { WorldCoordinate(x: $0, y: y) } }
            let footprint = coordinates.filter { TreeCanopy.center(near: $0, seed: 42) != nil }
            XCTAssertEqual(Set(footprint), Set(coordinates.reversed().filter { TreeCanopy.center(near: $0, seed: 42) != nil }))
            let center = TreeCanopy.center(near: footprint[0], seed: 42)!
            let corners = footprint.filter { abs($0.x - center.x) == 1 && abs($0.y - center.y) == 1 }
            let mask = corners.reduce(0) { $0 | (1 << (($1.x < center.x ? 0 : 1) + ($1.y < center.y ? 0 : 2))) }
            shapes.insert(mask)
            if footprint != coordinates.filter({ TreeCanopy.center(near: $0, seed: 2026) != nil }) { seedDifferences += 1 }
        }
        XCTAssertEqual(shapes.count, 16, "All combinations of missing corners should occur")
        XCTAssertTrue(shapes.contains(0)); XCTAssertTrue(shapes.contains(15))
        XCTAssertGreaterThan(seedDifferences, 80)
    }

    func testGeneratedOakAndPineHaveCentralLogsSurroundingLeavesAndCrossChunkSeams() throws {
        let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: 7))
        var found: Set<DecorationID> = [], crossedSeam = false
        for y in -160..<160 { for x in -160..<160 {
            let center = WorldCoordinate(x: x, y: y)
            guard let decoration = generator.tile(at: center).decoration, [.tree, .pine].contains(decoration) else { continue }
            let footprint = neighbors(center)
            let leaf: DecorationID = decoration == .pine ? .pineLeaves : .treeLeaves
            guard footprint.dropFirst().allSatisfy({ generator.tile(at: $0).decoration == leaf }) else { continue }
            found.insert(decoration)
            for point in footprint {
                let chunk = try generator.chunk(at: ChunkCoordinate.containing(point))
                XCTAssertEqual(chunk.tiles[point], generator.tile(at: point))
                let world = World(tiles: [point: generator.tile(at: point)])
                XCTAssertFalse(PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: point, in: world).isAllowed)
            }
            if Set(footprint.map(ChunkCoordinate.containing)).count > 1 { crossedSeam = true }
            if found == [.tree, .pine] && crossedSeam { return }
        } }
        XCTAssertEqual(found, [.tree, .pine])
        XCTAssertTrue(crossedSeam)
    }

    @MainActor func testLeafTransparencyRevealsLogOnlyUnderCanopyCenter() {
        let assets = AssetLibrary()
        let transparent = RasterAsset(width: 1, height: 1, pixels: [0, 0, 0, 0])
        let wood = RasterAsset(width: 1, height: 1, pixels: [170, 110, 50, 255])
        let ground = RasterAsset(width: 1, height: 1, pixels: [20, 80, 30, 255])
        assets.apply(LoadedPack(manifest: PackManifest(name: "Tree test", assets: [:]), textures: [.terrainGrass: ground, .decorationTree: transparent, .decorationPine: transparent, .decorationOakLog: wood, .decorationSpruceLog: wood], sounds: [:], warnings: []))
        for (center, leaves) in [(DecorationID.tree, DecorationID.treeLeaves), (.pine, .pineLeaves)] {
            XCTAssertEqual(assets.pixel(Tile(terrain: .grass, decoration: center), x: 0, y: 0).0, 170)
            XCTAssertEqual(assets.pixel(Tile(terrain: .grass, decoration: leaves), x: 0, y: 0).0, 20)
        }
        let translucent = RasterAsset(width: 1, height: 1, pixels: [0, 100, 0, 128])
        assets.apply(LoadedPack(manifest: PackManifest(name: "Partial leaves", assets: [:]), textures: [.decorationTree: translucent, .decorationOakLog: wood], sounds: [:], warnings: []))
        let blended = assets.pixel(Tile(terrain: .grass, decoration: .tree), x: 0, y: 0)
        XCTAssertEqual(blended.0, 84); XCTAssertEqual(blended.1, 154); XCTAssertEqual(blended.3, 255)
    }

    @MainActor func testMissingLogUsesOriginalWoodAndBuiltinTreesHaveVisibleLeafHoles() {
        let assets = AssetLibrary(), transparent = RasterAsset(width: 1, height: 1, pixels: [0, 0, 0, 0])
        assets.apply(LoadedPack(manifest: PackManifest(name: "Older import", assets: [:]), textures: [.decorationTree: transparent], sounds: [:], warnings: []))
        let result = assets.pixel(Tile(terrain: .grass, decoration: .tree), x: 0, y: 0)
        XCTAssertEqual(result.0, OriginalTerrainPixels.logPixel(x: 0, y: 0, pine: false).0)
        for (center, leaves) in [(DecorationID.tree, DecorationID.treeLeaves), (.pine, .pineLeaves)] {
            let a = OriginalTerrainPixels.pixel(Tile(terrain: .grass, decoration: center), x: 0, y: 0)
            let b = OriginalTerrainPixels.pixel(Tile(terrain: .grass, decoration: leaves), x: 0, y: 0)
            XCTAssertNotEqual(a.0, b.0)
        }
    }
}
