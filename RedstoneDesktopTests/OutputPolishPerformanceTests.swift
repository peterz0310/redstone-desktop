import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class CountingTerrainAssets: AssetProvider {
    let library = AssetLibrary()
    var pixelCalls = 0
    var revision: UUID { library.revision }
    var terrainResolution: Int { library.terrainResolution }
    func texture(for id: TextureAssetID) -> SKTexture? { library.texture(for: id) }
    func pixel(_ tile: Tile, x: Int, y: Int, appearance: DecorationAppearance?) -> (UInt8, UInt8, UInt8, UInt8) {
        pixelCalls += 1
        return library.pixel(tile, x: x, y: y, appearance: appearance)
    }
}

final class OutputPolishPerformanceTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "perf", frame: CGRect(x: 0, y: 0, width: 640, height: 640), backingScale: 2)
    @MainActor
    func testTilePaintingCostDependsOnFiniteStylesRatherThanExploredChunks() throws {
        let assets = CountingTerrainAssets(), renderer = TerrainChunkRenderer(), layer = SKNode()
        assets.library.apply(LoadedPack(manifest: PackManifest(name: "fixture", assets: [:]), textures: [.terrainGrass: RasterAsset(width: 1, height: 1, pixels: [80, 140, 60, 255])], sounds: [:], warnings: []))
        renderer.assets = assets
        let world = World(generation: WorldGenerationSettings(seed: 42))
        for step in 0..<8 {
            let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: Double(step * 32), y: 0), pointsPerTile: 40))
            renderer.render(world, mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), into: layer)
            XCTAssertLessThanOrEqual(assets.pixelCalls, 66 * 16 * 16, "Painting repeated tiles must not repeat provider sampling")
            XCTAssertLessThanOrEqual(layer.children.count, 16)
        }
        XCTAssertEqual(assets.pixelCalls, renderer.metrics.tileRasterBuilds * 16 * 16)
        XCTAssertGreaterThan(renderer.metrics.textureBuilds, renderer.metrics.chunkNodes)
        let calls = assets.pixelCalls
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 224.1, y: 0), pointsPerTile: 40))
        renderer.render(world, mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), into: layer)
        XCTAssertEqual(assets.pixelCalls, calls)
    }

    @MainActor
    func testPackRevisionAndResolutionReplaceCachedTilePixels() throws {
        let assets = CountingTerrainAssets(), renderer = TerrainChunkRenderer(), layer = SKNode()
        renderer.assets = assets
        let tile = WorldCoordinate(x: 2, y: 2)
        let world = World(tiles: [tile: Tile(terrain: .grass)], generation: WorldGenerationSettings(seed: 42))
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 40))
        for rgba: [UInt8] in [[170, 30, 210, 255], [20, 220, 40, 255]] {
            assets.library.apply(LoadedPack(manifest: PackManifest(name: "fixture", assets: [:]), textures: [.terrainGrass: RasterAsset(width: 1, height: 1, pixels: rgba)], sounds: [:], warnings: []))
            XCTAssertEqual(assets.terrainResolution, 16)
            renderer.render(world, mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), into: layer)
            let sprite = try XCTUnwrap(layer.childNode(withName: "chunk:0,0") as? SKSpriteNode)
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(sprite.texture).cgImage())
            let color = try XCTUnwrap(bitmap.colorAt(x: 2 * 16 + 8, y: 511 - (2 * 16 + 8))?.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, CGFloat(rgba[0]) / 255, accuracy: 0.01)
            XCTAssertEqual(color.greenComponent, CGFloat(rgba[1]) / 255, accuracy: 0.01)
        }
        assets.library.useBuiltIn()
        XCTAssertEqual(assets.terrainResolution, 8)
        renderer.render(world, mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), into: layer)
        let sprite = try XCTUnwrap(layer.childNode(withName: "chunk:0,0") as? SKSpriteNode)
        XCTAssertEqual(sprite.texture?.size(), CGSize(width: 256, height: 256))
    }

    @MainActor
    func testPanZoomAndResizeKeepNativeSceneAndSavedState() throws {
        let app = AppState(), editor = EditorSession(), renderer = EditorCanvasRenderer()
        defer { app.shutdown() }
        let size = CGSize(width: 640, height: 640)
        let first = try XCTUnwrap(renderer.update(appState: app, editor: editor, size: size))
        let desktop = app.desktopCamera, library = app.library
        for _ in 0..<20 {
            editor.pan(by: CGSize(width: -4, height: 3), size: size)
            editor.zoom(by: 1.01, size: size)
            let next = try XCTUnwrap(renderer.update(appState: app, editor: editor, size: size))
            XCTAssertTrue(next === first)
            XCTAssertEqual(next.mapper.camera, editor.camera)
        }
        let resized = try XCTUnwrap(renderer.update(appState: app, editor: editor, size: CGSize(width: 800, height: 600)))
        XCTAssertTrue(resized === first)
        XCTAssertEqual(resized.screen.frame.size, resized.size)
        XCTAssertEqual(app.desktopCamera, desktop)
        XCTAssertEqual(app.library, library)
    }
}
