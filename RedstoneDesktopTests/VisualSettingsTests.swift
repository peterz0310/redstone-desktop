import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class VisualBuildSpy: DesktopBuildPresenting {
    var settings: VisualSettings?
    func setVisualSettings(_ settings: VisualSettings) { self.settings = settings }
    func show() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {}
    func close() {}
}

final class VisualSettingsTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "visuals", frame: CGRect(x: 0, y: 0, width: 320, height: 320), backingScale: 1)

    @MainActor func testPersistenceDefaultsAndCorruptPreferenceFallbackWithoutWorldChanges() throws {
        let suite = "RedstoneDesktopTests.visuals.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = AppState(preferences: defaults)
        defer { app.shutdown() }
        XCTAssertEqual(app.visualSettings, VisualSettings())
        let before = app.library
        let settings = VisualSettings(liquidAnimations: false, sceneryAnimations: true, particles: false)
        app.setVisualSettings(settings)
        let restored = AppState(preferences: defaults)
        defer { restored.shutdown() }
        XCTAssertEqual(restored.visualSettings, settings)
        XCTAssertEqual(app.library, before)
        defaults.set(Data("invalid".utf8), forKey: "visualSettings")
        let fallback = AppState(preferences: defaults)
        defer { fallback.shutdown() }
        XCTAssertEqual(fallback.visualSettings, VisualSettings())
    }

    @MainActor func testLiveSceneControlsAreIndependentAndRetainTerrainAndEmitters() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame,
            camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 40))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        var world = World(tiles: [WorldCoordinate(x: 0, y: 0): Tile(terrain: .lava)])
        world.generation = WorldGenerationSettings(seed: 42)
        world.circuit.components[WorldCoordinate(x: 2, y: 2)] = CircuitComponent(kind: .lightTorch)
        scene.updateWorld(world)
        let chunk = try XCTUnwrap(scene.childNode(withName: "world-tiles/chunk:0,0") as? SKSpriteNode)
        let shader = try XCTUnwrap(chunk.shader)
        let particles = try XCTUnwrap(scene.childNode(withName: "world-particles"))
        let builds = scene.terrainMetrics.textureBuilds
        let emitters = particles.children.map(ObjectIdentifier.init)
        scene.setVisualSettings(VisualSettings(liquidAnimations: false, sceneryAnimations: false, particles: false))
        scene.update(1.25)
        XCTAssertTrue(particles.isHidden); XCTAssertTrue(particles.isPaused)
        XCTAssertEqual(shader.uniformNamed("u_motion")?.floatValue, 0)
        XCTAssertEqual(shader.uniformNamed("u_lavaPhase")?.vectorFloat3Value,
                       SIMD3<Float>(0, 1, 0))
        scene.setVisualSettings(VisualSettings(liquidAnimations: true, sceneryAnimations: false, particles: false))
        scene.update(2.35)
        // Reduce Motion can still override enabled preferences; disabled effects always stay disabled.
        XCTAssertEqual(shader.uniformNamed("u_motion")?.floatValue, 0)
        XCTAssertTrue(particles.isHidden)
        scene.setVisualSettings(VisualSettings(liquidAnimations: false, sceneryAnimations: true, particles: true))
        scene.update(3.25)
        XCTAssertEqual(shader.uniformNamed("u_lavaPhase")?.vectorFloat3Value, SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(scene.terrainMetrics.textureBuilds, builds)
        XCTAssertEqual(particles.children.map(ObjectIdentifier.init), emitters)
        scene.updateViewport(screen: screen, mapper: mapper)
        XCTAssertEqual(scene.visualSettings.liquidAnimations, false)
    }

    @MainActor func testIndependentShaderSwitchesAndReduceMotionFallback() throws {
        let ambience = TerrainAmbience(assets: BuiltInAssetProvider())
        let shader = ambience.shader(mask: SKTexture())
        ambience.advance(at: 1.23, reducedMotion: true, sceneryAnimations: true)
        XCTAssertEqual(shader.uniformNamed("u_motion")?.floatValue, 1)
        XCTAssertEqual(shader.uniformNamed("u_ambienceTime")?.floatValue, 1.23)
        let frozen = shader.uniformNamed("u_lavaPhase")?.vectorFloat3Value
        ambience.advance(at: 2.35, reducedMotion: false, sceneryAnimations: false)
        XCTAssertEqual(shader.uniformNamed("u_motion")?.floatValue, 0)
        XCTAssertNotEqual(shader.uniformNamed("u_lavaPhase")?.vectorFloat3Value, frozen)
        ambience.advance(at: 2.35, reducedMotion: true)
        XCTAssertEqual(shader.uniformNamed("u_motion")?.floatValue, 0)
        XCTAssertEqual(shader.uniformNamed("u_lavaPhase")?.vectorFloat3Value, frozen)
    }

    @MainActor func testAppPropagatesToExistingAndNewEditorDesktopAndBuildScenes() throws {
        let screen = screen, spy = VisualBuildSpy()
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), buildControllerFactory: { _, _, _ in spy },
            finderReferenceProviding: { screen })
        defer { app.shutdown() }
        let editor = EditorCanvasRenderer(), session = EditorSession(testScheduler: ManualCircuitTickScheduler())
        let scene = try XCTUnwrap(editor.update(appState: app, editor: session, size: screen.frame.size))
        app.toggleDesktopWorld()
        let desktop = try XCTUnwrap(app.desktopController?.scene)
        let library = app.library, power = app.simulator.power
        let settings = VisualSettings(liquidAnimations: false, sceneryAnimations: false, particles: false)
        app.setVisualSettings(settings)
        XCTAssertEqual(scene.visualSettings, settings)
        XCTAssertEqual(desktop.visualSettings, settings)
        XCTAssertEqual(app.library, library); XCTAssertEqual(app.simulator.power, power)
        app.toggleDesktopWorld(); app.toggleDesktopWorld()
        XCTAssertEqual(app.desktopController?.scene.visualSettings, settings)
        XCTAssertTrue(app.enterDesktopBuildMode())
        XCTAssertEqual(spy.settings, settings)
        app.setVisualSettings(VisualSettings())
        XCTAssertEqual(spy.settings, VisualSettings())
        XCTAssertEqual(scene.visualSettings, VisualSettings())
    }
}
