import XCTest
@testable import RedstoneDesktop

final class TreeCanopyTests: XCTestCase {
    private func neighbors(_ center: WorldCoordinate) -> [WorldCoordinate] {
        [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)].map { WorldCoordinate(x: center.x + $0.0, y: center.y + $0.1) }
    }

    private func footprint(_ center: WorldCoordinate, seed: UInt64) -> [WorldCoordinate] {
        (-2...2).flatMap { dy in (-2...2).map { WorldCoordinate(x: center.x + $0, y: center.y + dy) } }
            .filter { TreeCanopy.contains($0, center: center, seed: seed) }
    }

    func testJitteredSitesKeepRequiredCrossAndVariableCorners() throws {
        var shapes: Set<Int> = [], seedDifferences = 0, offsets: Set<WorldCoordinate> = []
        for cell in -128..<128 {
            let center = try XCTUnwrap(TreeCanopy.plantingCenter(cellX: cell, cellY: cell, seed: 42))
            let points = footprint(center, seed: 42)
            XCTAssertTrue((5...10).contains(points.count))
            XCTAssertTrue(Set(neighbors(center)).isSubset(of: Set(points)))
            XCTAssertEqual(TreeCanopy.centers(near: center, seed: 42).first, center, "Trunks take priority over leaves")
            for point in points { XCTAssertTrue(TreeCanopy.centers(near: point, seed: 42).contains(center)) }
            let mask = points.filter { abs($0.x - center.x) == 1 && abs($0.y - center.y) == 1 }
                .reduce(0) { $0 | (1 << (($1.x < center.x ? 0 : 1) + ($1.y < center.y ? 0 : 2))) }
            shapes.insert(mask)
            offsets.insert(WorldCoordinate(x: center.x - cell * 6, y: center.y - cell * 6))
            if TreeCanopy.plantingCenter(cellX: cell, cellY: cell, seed: 2026) != center { seedDifferences += 1 }
        }
        XCTAssertEqual(shapes.count, 16)
        XCTAssertEqual(offsets.count, 36, "Sites can occupy the entire cell, rather than its middle")
        XCTAssertGreaterThan(seedDifferences, 200)
        for x in [Int.min, Int.max] { _ = TreeCanopy.centers(near: WorldCoordinate(x: x, y: x), seed: .max) }
    }

    func testOccasionalExtensionsRemainConnectedInAllDirections() throws {
        var extended = 0, directions: Set<WorldCoordinate> = []
        for cell in -256..<256 {
            let center = try XCTUnwrap(TreeCanopy.plantingCenter(cellX: cell, cellY: cell, seed: 42))
            let points = footprint(center, seed: 42)
            let extensions = points.filter { abs($0.x - center.x) == 2 || abs($0.y - center.y) == 2 }
            XCTAssertLessThanOrEqual(extensions.count, 1)
            for point in extensions {
                extended += 1
                let dx = point.x - center.x, dy = point.y - center.y
                directions.insert(WorldCoordinate(x: dx, y: dy))
                XCTAssertTrue(points.contains(WorldCoordinate(x: center.x + dx / 2, y: center.y + dy / 2)))
            }
        }
        XCTAssertEqual(directions.count, 4)
        XCTAssertGreaterThan(extended, 64); XCTAssertLessThan(extended, 192)
    }

    func testGeneratedTreesHaveCloseClustersClearingsAndStableSampling() throws {
        let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: 7))
        var centers: Set<WorldCoordinate> = [], woodlandTiles = 0, woodlandLeaves = 0
        for y in -160..<160 { for x in -160..<160 {
            let point = WorldCoordinate(x: x, y: y), sample = generator.sample(at: point)
            if sample.biome == .woodland {
                woodlandTiles += 1
                if [.tree, .treeLeaves].contains(sample.tile.decoration) { woodlandLeaves += 1 }
            }
            if [.tree, .pine].contains(sample.tile.decoration) { centers.insert(point) }
        } }
        let close = centers.filter { center in
            (-2...2).contains { dy in (-2...2).contains { dx in
                (dx != 0 || dy != 0) && centers.contains(WorldCoordinate(x: center.x + dx, y: center.y + dy))
            } }
        }
        XCTAssertGreaterThan(close.count, 30, "Actual trunks should form nearby groups")
        XCTAssertGreaterThan(woodlandLeaves, woodlandTiles / 12)
        XCTAssertLessThan(woodlandLeaves, woodlandTiles / 2, "Forests still need clearings")
        for center in centers.prefix(100) {
            for point in footprint(center, seed: 7).reversed() {
                let chunk = try generator.chunk(at: ChunkCoordinate.containing(point))
                XCTAssertEqual(chunk.tiles[point], generator.tile(at: point))
            }
        }
    }

    func testExtendedLeafBlocksBuildingAndCanBeClearedAndRestored() throws {
        let document = WorldDocument(generation: WorldGenerationSettings(seed: 7))
        let generator = try WorldGenerator(settings: document.generation)
        for y in -128..<128 { for x in -128..<128 {
            let point = WorldCoordinate(x: x, y: y)
            guard let center = TreeCanopy.centers(near: point, seed: 7).first,
                  abs(point.x - center.x) == 2 || abs(point.y - center.y) == 2,
                  let decoration = generator.tile(at: point).decoration,
                  [.treeLeaves, .pineLeaves].contains(decoration) else { continue }
            let before = try document.restoredWorld()
            XCTAssertFalse(PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: point, in: before).isAllowed)
            let cleared = try TerrainEditing.plan(document: document, brush: .clearDecorations, tiles: [point])
            XCTAssertNil(cleared.world.tile(at: point)?.decoration)
            XCTAssertTrue(PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: point, in: cleared.world).isAllowed)
            var edited = document; edited.terrainOverrides = cleared.overrides
            let restored = try TerrainEditing.plan(document: edited, brush: .restore, tiles: [point])
            XCTAssertEqual(restored.world.tile(at: point), before.tile(at: point))
            return
        } }
        XCTFail("Expected an extended tree in the seed-7 sample")
    }

    func testGeneratedOakAndPineHaveCentralLogsSurroundingLeavesAndCrossChunkSeams() throws {
        let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: 7))
        var found: Set<DecorationID> = [], crossedSeam = false
        for y in -160..<160 { for x in -160..<160 {
            let center = WorldCoordinate(x: x, y: y)
            guard let decoration = generator.tile(at: center).decoration, [.tree, .pine].contains(decoration) else { continue }
            let footprint = (-2...2).flatMap { dy in (-2...2).map { WorldCoordinate(x: center.x + $0, y: center.y + dy) } }
                .filter { TreeCanopy.centers(near: $0, seed: 7).contains(center) }
            let leaf: DecorationID = decoration == .pine ? .pineLeaves : .treeLeaves
            guard footprint.filter({ $0 != center }).allSatisfy({ generator.tile(at: $0).decoration == leaf }) else { continue }
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
