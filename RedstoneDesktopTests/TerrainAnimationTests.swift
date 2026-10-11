import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class TerrainAnimationTests: XCTestCase {
    func testJavaSequenceTimingInterpolationAndLoop() throws {
        let data = Data(#"{"animation":{"frametime":2,"interpolate":true,"frames":[2,{"index":0,"time":4},1]}}"#.utf8)
        let spec = try TextureAnimationSpec.java(metadata: data, frameCount: 3)
        XCTAssertEqual(spec.frames, [2, 0, 1]); XCTAssertEqual(spec.durations, [0.1, 0.2, 0.1])
        XCTAssertEqual(spec.phase(at: 0.05).frame, 2); XCTAssertEqual(spec.phase(at: 0.05).next, 0)
        XCTAssertEqual(spec.phase(at: 0.05).blend, 0.5, accuracy: 0.001)
        XCTAssertEqual(spec.phase(at: 0.45).frame, 2)
        XCTAssertEqual(try TextureAnimationSpec.java(metadata: nil, frameCount: 3).durations, [0.05, 0.05, 0.05])
    }

    func testMetadataRejectsUnboundedMalformedAndBooleanNumbers() {
        for json in [#"{"animation":{"frametime":true}}"#, #"{"animation":{"frametime":0}}"#,
                     #"{"animation":{"frames":[9]}}"#, #"{"animation":{"frames":[]}}"#,
                     #"{"animation":{"frames":[{"index":true}]}}"#, #"{"animation":{"frametime":201}}"#,
                     #"{"animation":{"frames":[{"index":0,"time":1.5}]}}"#] {
            XCTAssertThrowsError(try TextureAnimationSpec.java(metadata: Data(json.utf8), frameCount: 2))
        }
        XCTAssertThrowsError(try TextureAnimationSpec.java(metadata: nil, frameCount: 65))
        XCTAssertThrowsError(try TextureAnimationSpec.java(metadata: Data(repeating: 32, count: 65537), frameCount: 2))
        XCTAssertThrowsError(try TextureAnimationSpec(frames: Array(repeating: 0, count: 257), durations: Array(repeating: 1, count: 257)).validate(frameCount: 1))
        XCTAssertThrowsError(try TextureAnimationSpec(frames: [0], durations: [.nan]).validate(frameCount: 1))
    }

    func testPackAnimationValidationAndPartialFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidPack-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let animation = OriginalLiquidAnimation.make(.lava)
        try animation.strip.pngData().write(to: root.appendingPathComponent("lava.png"))
        func load(_ manifest: PackManifest) throws -> LoadedPack {
            try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("pack.json"))
            return try ResourcePackLoader.load(root)
        }
        var manifest = PackManifest(name: "Animated", assets: ["lavaStill": "lava.png"], animations: ["lavaStill": animation.spec])
        let pack = try load(manifest)
        XCTAssertEqual(pack.animations[.lavaStill]?.spec, animation.spec)
        XCTAssertEqual(pack.textures[.lavaStill]?.height, 16)
        manifest.animations = ["terrainGrass": animation.spec]
        XCTAssertThrowsError(try load(manifest))
        manifest.animations = ["lavaStill": TextureAnimationSpec(frames: [99], durations: [1])]
        let fallback = try load(manifest)
        XCTAssertNil(fallback.textures[.lavaStill]); XCTAssertEqual(fallback.warnings.count, 1)
        manifest.animations = nil
        XCTAssertTrue(try load(manifest).animations.isEmpty) // Existing static packs remain valid.
        XCTAssertThrowsError(try AnimatedRaster(strip: RasterAsset(width: 16, height: 32, pixels: []), spec: animation.spec))
        XCTAssertThrowsError(try TextureAnimationSpec.java(metadata: nil, frameCount: .max))
    }

    @MainActor func testShallowWaterIsDarkerForCachedPacksAndKeepsTimingAlphaAndDeepWater() throws {
        let raster = RasterAsset(width: 1, height: 1, pixels: [80, 180, 220, 255])
        let animated = try AnimatedRaster(strip: raster, spec: TextureAnimationSpec(frames: [0], durations: [0.2]))
        let assets = AssetLibrary()
        assets.apply(LoadedPack(manifest: PackManifest(name: "Old cached pack", assets: [:]), textures: [.waterShallow: raster, .waterDeep: raster], sounds: [:], warnings: [], animations: [.waterShallow: animated]))
        XCTAssertEqual(assets.liquidAnimation(for: .shallowWater).strip.pixels, [56, 126, 193, 255])
        XCTAssertEqual(assets.liquidAnimation(for: .shallowWater).spec, animated.spec)
        XCTAssertEqual(assets.liquidAnimation(for: .deepWater).strip.pixels, raster.pixels)
        let pixel = assets.pixel(Tile(terrain: .shallowWater), x: 0, y: 0)
        XCTAssertEqual([pixel.0, pixel.1, pixel.2, pixel.3], [56, 126, 193, 255])
        let shallow = OriginalTerrainPixels.pixel(Tile(terrain: .shallowWater), x: 1, y: 0)
        let deep = OriginalTerrainPixels.pixel(Tile(terrain: .deepWater), x: 1, y: 0)
        XCTAssertGreaterThan(shallow.1, deep.1)
        XCTAssertLessThan(Int(shallow.1) - Int(deep.1), 40)
    }

    func testOriginalArtworkChangesAndFramesRemainOpaque() {
        for terrain in [TerrainID.shallowWater, .deepWater, .lava] {
            let animation = OriginalLiquidAnimation.make(terrain)
            XCTAssertEqual(animation.frameCount, 8)
            XCTAssertNotEqual(animation.frame(0).pixels, animation.frame(3).pixels)
            XCTAssertTrue(stride(from: 3, to: animation.strip.pixels.count, by: 4).allSatisfy { animation.strip.pixels[$0] == 255 })
        }
    }

    @MainActor
    func testGPUShaderUsesImportedFramesAndReduceMotionFreezesAtFirstFrame() throws {
        let red: [UInt8] = Array(repeating: [255, 0, 0, 255], count: 256).flatMap { $0 }
        let green: [UInt8] = Array(repeating: [0, 255, 0, 255], count: 256).flatMap { $0 }
        let animation = try AnimatedRaster(strip: RasterAsset(width: 16, height: 32, pixels: red + green), spec: TextureAnimationSpec(frames: [0, 1], durations: [0.1, 0.1]))
        let assets = AssetLibrary()
        assets.apply(LoadedPack(manifest: PackManifest(name: "Original test", assets: [:]), textures: [:], sounds: [:], warnings: [], animations: [.waterShallow: animation]))
        let ambience = TerrainAmbience(assets: assets)
        let mask = SKTexture(cgImage: try XCTUnwrap(RasterAsset(width: 1, height: 1, pixels: [85,0,0,255]).cgImage))
        let node = SKSpriteNode(color: .white, size: CGSize(width: 64, height: 64))
        node.anchorPoint = .zero; node.shader = ambience.shader(mask: mask)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        func color() throws -> NSColor {
            let texture = try XCTUnwrap(view.texture(from: node, crop: CGRect(x: 0, y: 0, width: 64, height: 64)))
            return try XCTUnwrap(NSBitmapImageRep(cgImage: texture.cgImage()).colorAt(x: 32, y: 32)?.usingColorSpace(.deviceRGB))
        }
        ambience.advance(at: 0, reducedMotion: false)
        let first = try color()
        XCTAssertGreaterThan(first.redComponent, 0.65); XCTAssertLessThan(first.greenComponent, 0.1)
        ambience.advance(at: 0.15, reducedMotion: false)
        let second = try color()
        XCTAssertGreaterThan(second.greenComponent, 0.65); XCTAssertLessThan(second.redComponent, 0.1)
        ambience.advance(at: 0.15, reducedMotion: true)
        XCTAssertGreaterThan(try color().redComponent, 0.65)
        ambience.advance(at: 99, reducedMotion: true)
        XCTAssertGreaterThan(try color().redComponent, 0.65)
    }

    @MainActor
    func testAmbiencePreservesNearestNeighborPixelsForStaticTerrain() throws {
        var pixels: [UInt8] = []
        for y in 0..<16 { for x in 0..<16 { pixels += (x + y) % 2 == 0 ? [255, 0, 0, 255] : [0, 0, 255, 255] } }
        let texture = SKTexture(cgImage: try XCTUnwrap(RasterAsset(width: 16, height: 16, pixels: pixels).cgImage))
        texture.filteringMode = .nearest; texture.usesMipmaps = false
        let node = SKSpriteNode(texture: texture); node.anchorPoint = .zero; node.size = CGSize(width: 160, height: 160)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        func mixedPixels() throws -> Int {
            let rendered = try XCTUnwrap(view.texture(from: node, crop: CGRect(x: 0, y: 0, width: 160, height: 160)))
            let bitmap = NSBitmapImageRep(cgImage: rendered.cgImage())
            var mixed = 0
            for y in 5..<155 { for x in 5..<155 {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent > 0.02 && color.blueComponent > 0.02 { mixed += 1 }
            } }
            return mixed
        }
        let baseline = try mixedPixels()
        XCTAssertEqual(baseline, 0)
        let mask = SKTexture(cgImage: try XCTUnwrap(RasterAsset(width: 1, height: 1, pixels: [0,0,0,255]).cgImage))
        let ambience = TerrainAmbience(assets: BuiltInAssetProvider())
        node.shader = ambience.shader(mask: mask, textureSize: texture.size())
        XCTAssertEqual(try mixedPixels(), baseline, "Static terrain must remain as crisp as a nearest-filtered sprite.")
        node.alpha = 0.5
        let rendered = try XCTUnwrap(view.texture(from: node, crop: CGRect(x: 0, y: 0, width: 160, height: 160)))
        let bitmap = NSBitmapImageRep(cgImage: rendered.cgImage())
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 5, y: 5)).alphaComponent, 0.5, accuracy: 0.02)
    }

    @MainActor
    func testAnimationDoesNotRebuildTerrainOrAddTileNodes() throws {
        let screen = ScreenDescriptor(id: "animation", frame: CGRect(x: 0, y: 0, width: 320, height: 320), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 40))
        var world = World(tiles: [WorldCoordinate(x: 0, y: 0): Tile(terrain: .lava), WorldCoordinate(x: 1, y: 0): Tile(terrain: .grass, decoration: .flower)])
        world.generation = WorldGenerationSettings(seed: 42)
        let renderer = TerrainChunkRenderer(), layer = SKNode()
        renderer.render(world, mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), into: layer)
        let baseline = renderer.metrics, identities = layer.children.map(ObjectIdentifier.init)
        let node = try XCTUnwrap(layer.childNode(withName: "chunk:0,0") as? SKSpriteNode)
        XCTAssertNotNil(node.shader)
        for step in 0..<1000 { renderer.advanceAnimation(at: Double(step) / 20, reducedMotion: step > 500) }
        XCTAssertEqual(renderer.metrics, baseline); XCTAssertEqual(layer.children.map(ObjectIdentifier.init), identities)
        XCTAssertTrue(layer.children.allSatisfy { $0.children.isEmpty })
        let mask = try XCTUnwrap(node.shader?.uniformNamed("u_liquidMap")?.textureValue)
        let bitmap = NSBitmapImageRep(cgImage: mask.cgImage())
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 4, y: 251)).redComponent, 0.9)
        XCTAssertEqual(bitmap.pixelsWide, 256)
    }
}
