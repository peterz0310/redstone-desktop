import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class WorldParticleTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "particles", frame: CGRect(x: -200, y: -100, width: 640, height: 640), backingScale: 2)
    private func p(_ x: Int, _ y: Int) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    @MainActor func testEvenWeakPoweredDustUsesVisibleSizeOpacityAndBirthRate() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let renderer = WorldParticleRenderer(), layer = SKNode()
        var world = World()
        world.circuit.components[p(2,2)] = CircuitComponent(kind: .dust)
        renderer.render(world: world, lava: [], power: [p(2,2): PowerLevel(1)], mapper: mapper, screen: screen, into: layer, reducedMotion: false)
        let dust = try XCTUnwrap(layer.children.first as? SKEmitterNode)
        XCTAssertGreaterThanOrEqual(dust.particleAlpha, 0.9)
        XCTAssertGreaterThanOrEqual(dust.particleSize.width, 7)
        XCTAssertGreaterThanOrEqual(dust.particleBirthRate, 0.8)
        renderer.render(world: world, lava: [], power: [p(2,2): .full], mapper: mapper, screen: screen, into: layer, reducedMotion: false)
        XCTAssertGreaterThan(dust.particleBirthRate, 2)
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, reducedMotion: false)
        XCTAssertTrue(layer.children.isEmpty)
    }
    @MainActor func testOnlyLitTorchesPoweredDustAndVisibleLavaEmitAndReuseNodes() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 32))
        let renderer = WorldParticleRenderer(), layer = SKNode()
        var world = World()
        let normal = p(2,2), redstone = p(3,3), dust = p(4,4), lamp = p(5,5)
        for (tile, kind) in [(normal, CircuitComponentKind.lightTorch), (redstone, .torch), (dust, .dust), (lamp, .lamp)] { world.circuit.components[tile] = CircuitComponent(kind: kind) }
        let lava: Set<WorldCoordinate> = [p(8,8), p(1000,1000)]
        renderer.render(world: world, lava: lava, power: [dust: PowerLevel(7), lamp: .full], mapper: mapper, screen: screen, into: layer, reducedMotion: false)
        XCTAssertEqual(renderer.emitterCount, 4, "Always-lit flame/smoke, one powered dust and one visible lava")
        let flame = try XCTUnwrap(layer.childNode(withName: "particle:particleFlame:2,2"))
        let torchRect = mapper.sceneRect(forTile: normal, on: screen)
        XCTAssertEqual(flame.position.y, torchRect.midY + torchRect.height * 0.30, accuracy: 0.01, "Flame starts at the torch head rather than inside the stem")
        let first = layer.children
        let builds = renderer.emitterBuilds
        for _ in 0..<100 { renderer.render(world: world, lava: lava, power: [dust: PowerLevel(7)], mapper: mapper, screen: screen, into: layer, reducedMotion: false) }
        XCTAssertEqual(renderer.emitterBuilds, builds)
        XCTAssertTrue(first.allSatisfy { $0.parent === layer })
        renderer.render(world: world, lava: lava, power: [redstone: .full], mapper: mapper, screen: screen, into: layer, reducedMotion: false)
        XCTAssertEqual(renderer.emitterCount, 4, "Dust stops; lit redstone torch adds red sparks")
        XCTAssertNil(layer.childNode(withName: "particle:particleDust:4,4"))
        XCTAssertNotNil(layer.childNode(withName: "particle:particleDust:3,3"))
        renderer.render(world: World(), lava: [], power: [:], mapper: mapper, screen: screen, into: layer, reducedMotion: false)
        XCTAssertTrue(layer.children.isEmpty)
    }
    @MainActor func testEmittersAreBoundedReducedMotionPausesAndViewportRemapsSources() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 16))
        let renderer = WorldParticleRenderer(), layer = SKNode()
        var world = World()
        for y in 0..<40 { for x in 0..<40 { world.circuit.components[p(x,y)] = CircuitComponent(kind: .lightTorch) } }
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, reducedMotion: false)
        XCTAssertEqual(renderer.emitterCount, WorldParticleRenderer.maximumEmitters)
        renderer.advance(into: layer, reducedMotion: true)
        XCTAssertTrue(layer.isHidden); XCTAssertTrue(layer.isPaused)
        renderer.advance(into: layer, reducedMotion: false)
        XCTAssertFalse(layer.isHidden); XCTAssertFalse(layer.isPaused)
        let moved = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0.5, y: 0), pointsPerTile: 16))
        renderer.render(world: world, lava: [], power: [:], mapper: moved, screen: screen, into: layer, reducedMotion: false)
        let emitter = try XCTUnwrap(layer.children.first as? SKEmitterNode)
        let rect = moved.sceneRect(forTile: p(0,0), on: screen)
        XCTAssertEqual(emitter.position.x, rect.midX, accuracy: 0.01)
        XCTAssertLessThanOrEqual(layer.children.count, 64)
    }
    @MainActor func testNativeEmitterProducesVisibleParticlesOverOriginalSceneArtwork() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 32))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        var world = World()
        for y in 0..<20 { for x in 0..<20 { world.tiles[p(x,y)] = Tile(terrain: y > 12 && x < 10 ? .lava : .grass) } }
        for x in 2..<18 { world.circuit.components[p(x,6)] = CircuitComponent(kind: .lightTorch) }
        scene.updateWorld(world)
        let layer = try XCTUnwrap(scene.childNode(withName: "world-particles"))
        layer.isPaused = false; layer.isHidden = false
        let view = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        func rendered() throws -> NSBitmapImageRep {
            NSBitmapImageRep(cgImage: try XCTUnwrap(view.texture(from: scene, crop: CGRect(origin: .zero, size: screen.frame.size))).cgImage())
        }
        let before = try XCTUnwrap(rendered().representation(using: .png, properties: [:]))
        for emitter in layer.children.compactMap({ $0 as? SKEmitterNode }) { emitter.advanceSimulationTime(4) }
        let after = try XCTUnwrap(rendered().representation(using: .png, properties: [:]))
        XCTAssertNotEqual(before, after, "The native SpriteKit emitter must actually draw its particles")
        try after.write(to: URL(fileURLWithPath: "/tmp/redstone-scene-effects.png"))
    }

    @MainActor func testSceneKeepsParticleLayerThroughResizeAndTexturesFallBack() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 32))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        var world = World(); world.circuit.components[p(2,2)] = CircuitComponent(kind: .lightTorch)
        scene.updateWorld(world)
        XCTAssertEqual(scene.particleEmitterCount, 2)
        scene.updateViewport(screen: screen, mapper: mapper)
        let layer = try XCTUnwrap(scene.childNode(withName: "world-particles"))
        XCTAssertEqual(layer.children.count, 2)
        XCTAssertGreaterThan(layer.zPosition, try XCTUnwrap(scene.childNode(withName: "world-lighting")).zPosition, "Glowing particles remain visible above night shading")
        XCTAssertLessThan(layer.zPosition, try XCTUnwrap(scene.childNode(withName: "cursor-highlight")).zPosition)
        let builtIn = BuiltInAssetProvider()
        for id in [TextureAssetID.particleFlame, .particleSmoke, .particleLava, .particleDust] {
            XCTAssertEqual(builtIn.texture(for: id)?.filteringMode, .nearest)
        }
    }
    @MainActor func testNightShadesParticlesFromEverySourceWhenLocalLightsAreDisabled() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let view = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        let source = p(4,4), rect = mapper.sceneRect(forTile: source, on: screen)
        let white = SKTexture(cgImage: try XCTUnwrap(RasterAsset(width: 1, height: 1, pixels: [255,255,255,255]).cgImage))
        for kind in [CircuitComponentKind.lightTorch, .torch, .dust, .empty] {
            let scene = DesktopScene(screen: screen, mapper: mapper)
            scene.isPaused = true
            var world = World(lighting: WorldLightingSettings(mode: .night))
            world.tiles[source] = Tile(terrain: kind == .empty ? .lava : .grass)
            if kind != .empty { world.circuit.components[source] = CircuitComponent(kind: kind) }
            let power: [WorldCoordinate: PowerLevel] = [.torch, .dust].contains(kind) ? [source: .full] : [:]
            scene.updateWorld(world, powerLevels: power)
            // Component labels stay above shading for readability; isolate particle pixels.
            try XCTUnwrap(scene.childNode(withName: "circuit")).isHidden = true
            let layer = try XCTUnwrap(scene.childNode(withName: "world-particles"))
            let emitters = layer.children.compactMap { $0 as? SKEmitterNode }
            XCTAssertFalse(emitters.isEmpty, "Expected particles from \(kind)")
            // Keep a visible stationary particle for deterministic native pixel comparison.
            for emitter in emitters {
                emitter.resetSimulation(); emitter.particleTexture = white
                emitter.particleColorBlendFactor = 0
                emitter.particleAlpha = 1; emitter.particleAlphaSpeed = 0
                emitter.particleLifetime = 10; emitter.particleLifetimeRange = 0
                emitter.particleSpeed = 0; emitter.particleSpeedRange = 0; emitter.yAcceleration = 0
                emitter.particlePositionRange = .zero; emitter.particleSize = CGSize(width: 12, height: 12)
                emitter.particleBirthRate = 2
            }
            func brightestPixel() throws -> CGFloat {
                layer.isHidden = false; layer.isPaused = false // Independent of the test Mac's Reduce Motion preference.
                for emitter in emitters { emitter.resetSimulation(); emitter.advanceSimulationTime(1.5) }
                let texture = try XCTUnwrap(view.texture(from: scene, crop: rect))
                let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
                var maximum: CGFloat = 0
                for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                    maximum = max(maximum, bitmap.colorAt(x: x, y: y)?.redComponent ?? 0)
                } }
                return maximum
            }
            XCTAssertGreaterThan(try brightestPixel(), 0.85, "Enabled particles glow at night: \(kind)")
            world.lighting?.localLights = false; scene.updateWorld(world, powerLevels: power)
            XCTAssertLessThan(try brightestPixel(), 0.4, "Disabled local light must also shade particles: \(kind)")
            XCTAssertTrue(emitters.allSatisfy { $0.parent === layer }, "Lighting changes must reuse emitters/trails")
            world.lighting?.mode = .day; scene.updateWorld(world, powerLevels: power)
            XCTAssertGreaterThan(try brightestPixel(), 0.85, "Daylight particles retain their brightness: \(kind)")
            world.lighting?.mode = .night; world.lighting?.localLights = true
            scene.updateWorld(world, powerLevels: power)
            XCTAssertGreaterThan(try brightestPixel(), 0.85, "Re-enabling light restores the glow: \(kind)")
        }
    }

    @MainActor func testParticleShadingFollowsClockWithoutRebuildingTrailsOrLightingMasks() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 32))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        scene.lightingTimeProviding = { 0 }
        var world = World(lighting: WorldLightingSettings(mode: .cycle, cycleMinutes: 2, startPhase: 0.25, localLights: false))
        world.circuit.components[p(2,2)] = CircuitComponent(kind: .lightTorch)
        scene.updateWorld(world)
        let layer = try XCTUnwrap(scene.childNode(withName: "world-particles"))
        let lighting = try XCTUnwrap(scene.childNode(withName: "world-lighting"))
        XCTAssertLessThan(layer.zPosition, lighting.zPosition)
        let emitters = layer.children, maskBuilds = scene.lightingTextureBuilds
        for time in 1...120 { scene.lightingTimeProviding = { Double(time) }; scene.update(Double(time)) }
        XCTAssertEqual(scene.lightingTextureBuilds, maskBuilds)
        XCTAssertTrue(emitters.allSatisfy { $0.parent === layer })
        scene.updateViewport(screen: screen, mapper: mapper)
        XCTAssertLessThan(layer.zPosition, lighting.zPosition)
        XCTAssertTrue(emitters.allSatisfy { $0.parent === layer })
    }

}
