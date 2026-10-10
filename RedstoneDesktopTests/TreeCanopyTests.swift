import XCTest
@testable import RedstoneDesktop

final class TreeCanopyTests: XCTestCase {
    private func neighbors(_ center: WorldCoordinate) -> [WorldCoordinate] {
        [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)].map { WorldCoordinate(x: center.x + $0.0, y: center.y + $0.1) }
    }

    func testPlantingCellsKeepRequiredCrossWithinVariableCanopies() {
        for origin in [-192, -6, 0, 30, 192] {
            let coordinates = (origin..<origin + 6).flatMap { y in (origin..<origin + 6).map { WorldCoordinate(x: $0, y: y) } }
            let sites = coordinates.compactMap { TreeCanopy.center(near: $0, seed: 42) }
            XCTAssertTrue((5...10).contains(sites.count))
            XCTAssertEqual(Set(sites).count, 1)
            let center = sites[0]
            let footprint = Set(coordinates.filter { TreeCanopy.center(near: $0, seed: 42) != nil })
            XCTAssertTrue(Set(neighbors(center)).isSubset(of: footprint))
            XCTAssertTrue(footprint.allSatisfy {
                let dx = abs($0.x - center.x), dy = abs($0.y - center.y)
                return (dx <= 1 && dy <= 1) || (dx + dy == 2 && (dx == 0 || dy == 0))
            })
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

    func testOccasionalExtensionsAreSingleConnectedLeavesInAllFourDirections() {
        var extended = 0, directions: Set<WorldCoordinate> = []
        let origins = Array(stride(from: -768, through: 768, by: 6))
        for origin in origins {
            let coordinates = (origin..<origin + 6).flatMap { y in (origin..<origin + 6).map { WorldCoordinate(x: $0, y: y) } }
            let footprint = coordinates.filter { TreeCanopy.center(near: $0, seed: 42) != nil }
            let center = TreeCanopy.center(near: footprint[0], seed: 42)!
            let extensions = footprint.filter { abs($0.x - center.x) == 2 || abs($0.y - center.y) == 2 }
            XCTAssertLessThanOrEqual(extensions.count, 1)
            for point in extensions {
                extended += 1
                let dx = point.x - center.x, dy = point.y - center.y
                directions.insert(WorldCoordinate(x: dx, y: dy))
                let neighbor = WorldCoordinate(x: center.x + dx / 2, y: center.y + dy / 2)
                XCTAssertTrue(footprint.contains(neighbor), "Extensions must touch a required arm")
                XCTAssertEqual(TreeCanopy.center(near: point, seed: 42), center)
            }
        }
        XCTAssertEqual(directions, Set([WorldCoordinate(x: -2, y: 0), WorldCoordinate(x: 2, y: 0), WorldCoordinate(x: 0, y: -2), WorldCoordinate(x: 0, y: 2)]))
        XCTAssertGreaterThan(extended, origins.count / 8)
        XCTAssertLessThan(extended, origins.count * 3 / 8)
    }

    func testExtendedLeafBlocksBuildingAndCanBeClearedAndRestored() throws {
        let document = WorldDocument(generation: WorldGenerationSettings(seed: 7))
        let generator = try WorldGenerator(settings: document.generation)
        for y in -128..<128 { for x in -128..<128 {
            let point = WorldCoordinate(x: x, y: y)
            guard let center = TreeCanopy.center(near: point, seed: 7),
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
                .filter { TreeCanopy.center(near: $0, seed: 7) == center }
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
