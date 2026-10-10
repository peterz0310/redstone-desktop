import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class ChunkRendererTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "test", frame: CGRect(x: -640, y: -320, width: 640, height: 640), backingScale: 2)
    private func mapper(_ origin: WorldPoint = WorldPoint(x: 0, y: 0), scale: Double = 40) throws -> CoordinateMapper {
        try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: origin, pointsPerTile: scale))
    }
    private func world() -> World {
        var world = EditorConstructionArea.makeWorld()
        world.generation = WorldGenerationSettings(seed: 2026)
        return world
    }

    func testVisibleChunksUseMapperNegativeCoordinatesMarginsAndBounds() throws {
        let mapper = try mapper(WorldPoint(x: -32, y: -32), scale: 20)
        let viewport = CGRect(origin: .zero, size: screen.frame.size)
        XCTAssertEqual(mapper.visibleChunks(on: screen, viewport: viewport, margin: 0), [ChunkCoordinate(x: -1, y: -1)])
        let withMargin = mapper.visibleChunks(on: screen, viewport: viewport)
        XCTAssertEqual(withMargin.count, 9)
        XCTAssertTrue(withMargin.contains(ChunkCoordinate(x: -2, y: -2)))
        XCTAssertTrue(withMargin.contains(ChunkCoordinate(x: 0, y: 0)))
        XCTAssertEqual(mapper.sceneRect(forChunk: ChunkCoordinate(x: -1, y: -1), on: screen), CGRect(x: 0, y: 0, width: 640, height: 640))
        XCTAssertTrue(try self.mapper(scale: 0.001).visibleChunks(on: screen, viewport: viewport).isEmpty)
        XCTAssertTrue(mapper.visibleChunks(on: screen, viewport: .zero).isEmpty)
    }

    func testCacheRetainsOnlyRequestedChunksAndRegeneratesOnlyMissingOrNewSeed() throws {
        var cache = ChunkCache()
        let settings = WorldGenerationSettings(seed: 42)
        let first: Set<ChunkCoordinate> = [ChunkCoordinate(x: -1, y: 0), ChunkCoordinate(x: 0, y: 0)]
        try cache.update(first, settings: settings)
        XCTAssertEqual(cache.generatedCount, 2)
        let tile = cache.chunks[ChunkCoordinate(x: 0, y: 0)]
        try cache.update(first, settings: settings)
        XCTAssertEqual(cache.generatedCount, 2)
        XCTAssertEqual(cache.chunks[ChunkCoordinate(x: 0, y: 0)], tile)
        try cache.update([ChunkCoordinate(x: 0, y: 0), ChunkCoordinate(x: 1, y: 0)], settings: settings)
        XCTAssertEqual(cache.chunks.count, 2)
        XCTAssertEqual(cache.generatedCount, 3)
        XCTAssertNil(cache.chunks[ChunkCoordinate(x: -1, y: 0)])
        try cache.update([ChunkCoordinate(x: 0, y: 0)], settings: WorldGenerationSettings(seed: 2026))
        XCTAssertEqual(cache.generatedCount, 4)
        XCTAssertNotEqual(cache.chunks[ChunkCoordinate(x: 0, y: 0)], tile)
    }

    @MainActor
    func testRendererUsesOneNearestSpritePerChunkAndIdlePowerDoNotGenerate() throws {
        let renderer = TerrainChunkRenderer(), layer = SKNode(), mapper = try mapper()
        let world = world(), viewport = CGRect(origin: .zero, size: screen.frame.size)
        renderer.render(world, mapper: mapper, screen: screen, viewport: viewport, into: layer)
        let baseline = renderer.metrics
        XCTAssertEqual(baseline.chunkNodes, baseline.retainedChunks)
        XCTAssertEqual(layer.children.count, baseline.chunkNodes)
        for node in layer.children {
            let sprite = try XCTUnwrap(node as? SKSpriteNode)
            XCTAssertEqual(sprite.texture?.filteringMode, .nearest)
            XCTAssertEqual(sprite.texture?.size(), CGSize(width: 256, height: 256))
            XCTAssertEqual(sprite.size, CGSize(width: 1280, height: 1280))
        }
        for _ in 0..<20 { renderer.render(world, mapper: mapper, screen: screen, viewport: viewport, into: layer) }
        XCTAssertEqual(renderer.metrics, baseline)
        let scene = DesktopScene(screen: screen, mapper: mapper, terrainRenderer: renderer)
        scene.updateWorld(world)
        let counts = scene.terrainMetrics
        scene.updateWorld(world, poweredTiles: [DemoCircuit.button, DemoCircuit.output])
        scene.updateOccupancy(.unavailable("Test"))
        XCTAssertEqual(scene.terrainMetrics, counts)
    }

    @MainActor
    func testLongPanKeepsOnlyCurrentNodesAndCameraChangesReuseTextures() throws {
        let renderer = TerrainChunkRenderer(), layer = SKNode(), world = world()
        let viewport = CGRect(origin: .zero, size: screen.frame.size)
        for step in 0..<25 {
            let mapper = try mapper(WorldPoint(x: Double(step * 64 - 128), y: -32))
            renderer.render(world, mapper: mapper, screen: screen, viewport: viewport, into: layer)
            XCTAssertLessThanOrEqual(layer.children.count, 16)
            XCTAssertEqual(renderer.metrics.chunkNodes, layer.children.count)
            XCTAssertEqual(renderer.metrics.retainedChunks, layer.children.count)
        }
        let before = renderer.metrics
        let mapper = try mapper(WorldPoint(x: Double(24 * 64 - 128) + 0.1, y: -32))
        renderer.render(world, mapper: mapper, screen: screen, viewport: viewport, into: layer)
        XCTAssertEqual(renderer.metrics.generatedChunks, before.generatedChunks)
        XCTAssertEqual(renderer.metrics.textureBuilds, before.textureBuilds)
    }

    @MainActor
    func testExplicitTerrainAndUnspecifiedOverridesMatchPlacementAndTexture() throws {
        let renderer = TerrainChunkRenderer(), layer = SKNode(), world = world(), mapper = try mapper()
        renderer.render(world, mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), into: layer)
        XCTAssertEqual(world.tile(at: DemoCircuit.button)?.terrain, .grass)
        XCTAssertNil(world.tile(at: WorldCoordinate(x: 14, y: 5)))
        XCTAssertFalse(PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: WorldCoordinate(x: 14, y: 5), in: world).isAllowed)
        let sprite = try XCTUnwrap(layer.childNode(withName: "chunk:0,0") as? SKSpriteNode)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(sprite.texture).cgImage())
        // Bitmap rows are top-down, tile coordinates are upward.
        let hole = try XCTUnwrap(bitmap.colorAt(x: 14 * 8 + 4, y: 255 - (5 * 8 + 4)))
        XCTAssertEqual(hole.alphaComponent, 0, accuracy: 0.01)
        let buttonTile = try XCTUnwrap(bitmap.colorAt(x: 2 * 8 + 4, y: 255 - (3 * 8 + 4)))
        XCTAssertEqual(buttonTile.greenComponent, 128.0 / 255, accuracy: 0.02)
        for coordinate in [WorldCoordinate(x: 32, y: 32), WorldCoordinate(x: -32, y: -32)] {
            XCTAssertEqual(world.tile(at: coordinate), try WorldGenerator(settings: XCTUnwrap(world.generation)).tile(at: coordinate))
        }
    }

    @MainActor
    func testEditorReusesSceneAndTerrainCacheWithoutChangingDesktopCamera() throws {
        let state = AppState(libraryStore: RendererMemoryStore())
        defer { state.shutdown() }
        let editor = EditorSession(), renderer = EditorCanvasRenderer(), size = CGSize(width: 640, height: 640)
        let first = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: size))
        let metrics = first.terrainMetrics, desktop = state.desktopCamera
        editor.pan(by: CGSize(width: -1, height: -1), size: size)
        let next = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: size))
        XCTAssertTrue(first === next)
        XCTAssertEqual(next.terrainMetrics.generatedChunks, metrics.generatedChunks)
        XCTAssertEqual(next.terrainMetrics.textureBuilds, metrics.textureBuilds)
        XCTAssertEqual(state.desktopCamera, desktop)
    }

    func testOriginalPlaceholderPixelsDistinguishTerrainAndDecorations() {
        let terrainColors = TerrainID.allCases.map { OriginalTerrainPixels.pixel(Tile(terrain: $0), x: 0, y: 0) }
        XCTAssertEqual(Set(terrainColors.map { "\($0.0),\($0.1),\($0.2)" }).count, TerrainID.allCases.count)
        for decoration in DecorationID.allCases {
            var differs = false
            for y in 0..<8 {
                for x in 0..<8 {
                    let a = OriginalTerrainPixels.pixel(Tile(terrain: .grass, decoration: decoration), x: x, y: y)
                    let b = OriginalTerrainPixels.pixel(Tile(terrain: .grass), x: x, y: y)
                    if a != b { differs = true }
                }
            }
            XCTAssertTrue(differs)
        }
    }
}

private struct RendererMemoryStore: WorldLibraryStoring {
    func load() throws -> WorldLibraryDocument? { try WorldLibraryDocument(legacy: LegacyWorldDocument()) }
    func save(_ document: WorldLibraryDocument) throws {}
}
