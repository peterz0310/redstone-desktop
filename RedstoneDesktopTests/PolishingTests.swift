import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class PolishItems: DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem] { [] }
}

final class PolishingTests: XCTestCase {
    private let frame = CGRect(x: -1280, y: -200, width: 1280, height: 800)

    @MainActor
    private func scene() throws -> DesktopScene {
        let screen = ScreenDescriptor(id: "polish", frame: frame, backingScale: 2)
        return DesktopScene(screen: screen, mapper: try CoordinateMapper(canvasFrame: frame,
            camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)))
    }

    @MainActor
    func testAdjacentRepeatersHaveContinuousPortsOnlyAlongValidDirectedPath() throws {
        let scene = try scene(), origin = WorldCoordinate(x: 5, y: 5)
        for direction in Direction.allCases {
            let neighbor = try XCTUnwrap(direction.neighbor(of: origin))
            var circuit = CircuitWorld(components: [origin: CircuitComponent(kind: .repeater, direction: direction),
                neighbor: CircuitComponent(kind: .repeater, direction: direction)])
            scene.updateWorld(World(circuit: circuit))
            let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
            let first = try XCTUnwrap(layer.childNode(withName: "repeater-port:5,5:\(direction.rawValue)") as? SKShapeNode)
            let second = try XCTUnwrap(layer.childNode(withName: "repeater-port:\(neighbor.x),\(neighbor.y):\(direction.opposite.rawValue)") as? SKShapeNode)
            let a = try XCTUnwrap(first.path?.boundingBoxOfPath), b = try XCTUnwrap(second.path?.boundingBoxOfPath)
            if direction == .east { XCTAssertEqual(a.maxX, b.minX) }
            if direction == .west { XCTAssertEqual(a.minX, b.maxX) }
            if direction == .north { XCTAssertEqual(a.maxY, b.minY) }
            if direction == .south { XCTAssertEqual(a.minY, b.maxY) }
            circuit.components[neighbor]?.direction = direction.opposite
            scene.updateWorld(World(circuit: circuit))
            XCTAssertNil(layer.childNode(withName: "repeater-port:5,5:\(direction.rawValue)"), "No head-to-head false connection")
        }
    }

    @MainActor
    func testRepeaterSideDustHasNoPortAndLargerIconOverlapsVisibleEndTrace() throws {
        let scene = try scene(), tile = WorldCoordinate(x: 5, y: 5)
        let circuit = CircuitWorld(components: [tile: CircuitComponent(kind: .repeater, direction: .east),
            WorldCoordinate(x: 6, y: 5): CircuitComponent(kind: .dust), WorldCoordinate(x: 5, y: 6): CircuitComponent(kind: .dust)])
        scene.updateWorld(World(circuit: circuit))
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        XCTAssertNotNil(layer.childNode(withName: "repeater-port:5,5:east"))
        XCTAssertNil(layer.childNode(withName: "repeater-port:5,5:north"))
        let icon = try XCTUnwrap(layer.childNode(withName: "REPEATER")?.childNode(withName: "component-icon:5,5") as? SKSpriteNode)
        XCTAssertEqual(icon.size.width, 64 * 0.86, accuracy: 0.001)
        XCTAssertEqual(icon.position.y, 352, accuracy: 0.001)
    }

    @MainActor
    func testWireIntensityUsesRealStrengthAndSurvivesResizeAndAssetRefresh() throws {
        let scene = try scene(), tile = WorldCoordinate(x: 2, y: 2)
        let world = World(circuit: CircuitWorld(components: [tile: CircuitComponent(kind: .dust)]))
        var brightness: [CGFloat] = []
        var renderedRed: [CGFloat] = []
        let view = SKView(frame: frame)
        view.presentScene(scene)
        for level in [1, 7, 15] {
            scene.updateWorld(world, poweredTiles: [tile], powerLevels: [tile: PowerLevel(level)])
            let wire = try XCTUnwrap(scene.childNode(withName: "circuit/dust-path") as? SKShapeNode)
            brightness.append(try XCTUnwrap(wire.fillColor.usingColorSpace(.deviceRGB)).redComponent)
            XCTAssertEqual(wire.path?.boundingBoxOfPath.width ?? 0, 12.8, accuracy: 0.001)
            // Check SpriteKit's actual texture/color blending, not just node properties.
            let texture = try XCTUnwrap(view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size)))
            let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
            let rect = scene.mapper.sceneRect(forTile: tile, on: scene.screen)
            let px = Int(rect.midX / scene.size.width * CGFloat(bitmap.pixelsWide))
            let py = bitmap.pixelsHigh - 1 - Int(rect.midY / scene.size.height * CGFloat(bitmap.pixelsHigh))
            let color = try XCTUnwrap(bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB))
            renderedRed.append(color.redComponent)
            XCTAssertGreaterThan(color.redComponent, color.greenComponent * 2)
        }
        XCTAssertLessThan(brightness[0], brightness[1]); XCTAssertLessThan(brightness[1], brightness[2])
        XCTAssertLessThan(renderedRed[0], renderedRed[1]); XCTAssertLessThan(renderedRed[1], renderedRed[2])
        scene.updateWorld(world, poweredTiles: [tile], powerLevels: [tile: PowerLevel(7)])
        scene.size = CGSize(width: 1000, height: 700)
        scene.setAssets(BuiltInAssetProvider())
        let wire = try XCTUnwrap(scene.childNode(withName: "circuit/dust-path") as? SKShapeNode)
        XCTAssertEqual(try XCTUnwrap(wire.fillColor.usingColorSpace(.deviceRGB)).redComponent, brightness[1], accuracy: 0.001)
    }

    @MainActor
    func testDesktopReceivesActualSimulatorStrengthSnapshot() async throws {
        let screen = ScreenDescriptor(id: "polish", frame: frame, backingScale: 2)
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: PolishItems()),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: FixtureItemOpener(), finderReferenceProviding: { screen })
        defer { app.shutdown() }
        for (x, kind) in [(10, CircuitComponentKind.lever), (11, .dust), (12, .dust)] {
            XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: kind), at: WorldCoordinate(x: x, y: 3)), .allowed)
        }
        await app.finderDiagnostics.readItems()
        app.toggleDesktopWorld()
        app.handleCircuitClick(WorldCoordinate(x: 10, y: 3))
        await app.activationTask?.value
        app.advanceCircuitTick()
        XCTAssertEqual(app.simulator.power(at: WorldCoordinate(x: 12, y: 3)), PowerLevel(14))
        let layer = try XCTUnwrap(app.desktopController?.scene.childNode(withName: "circuit"))
        let rect = try XCTUnwrap(app.desktopController?.scene.mapper.sceneRect(forTile: WorldCoordinate(x: 12, y: 3), on: screen))
        let wire = try XCTUnwrap(layer.children.compactMap { $0 as? SKShapeNode }.first { $0.name == "dust-path" && $0.path?.contains(CGPoint(x: rect.midX, y: rect.midY)) == true })
        XCTAssertLessThan(try XCTUnwrap(wire.fillColor.usingColorSpace(.deviceRGB)).redComponent, 1)
    }

    func testGrassAndCactusPresentationPreserveStoredTerrainAndPlacement() {
        let dirt = Tile(terrain: .dirt, decoration: .flower)
        XCTAssertEqual(TerrainAppearance.tile(dirt, generated: true), Tile(terrain: .grass, decoration: .flower))
        XCTAssertEqual(TerrainAppearance.tile(dirt, generated: false), dirt)
        let tile = WorldCoordinate(x: -4, y: 7)
        XCTAssertEqual(DecorationAppearance.choose(.rock, at: tile, seed: 42, terrain: .sand), .cactus)
        XCTAssertNotEqual(DecorationAppearance.choose(.rock, at: tile, seed: 42, terrain: .stone), .cactus)
        let sand = World(tiles: [tile: Tile(terrain: .sand, decoration: .rock)])
        XCTAssertEqual(PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: tile, in: sand), .rejected(.blockedByDecoration(.rock)))
        XCTAssertEqual(sand.tiles[tile]?.decoration, .rock)
    }

    @MainActor
    func testCactusFallbackDoesNotBorrowOldOreFamilyTexture() throws {
        let assets = AssetLibrary()
        let raster = RasterAsset(width: 1, height: 1, pixels: [255, 0, 0, 255])
        assets.apply(LoadedPack(manifest: PackManifest(name: "Old", assets: [:]), textures: [.decorationRock: raster], sounds: [:], warnings: []))
        let pixel = assets.pixel(Tile(terrain: .sand, decoration: .rock), x: 8, y: 8, appearance: .cactus)
        XCTAssertGreaterThan(pixel.1, pixel.0)
        XCTAssertNil(TextureAssetID.decorationCactus.decorationFallback)
        for id in TextureAssetID.allCases { XCTAssertNotNil(assets.texture(for: id)) }
    }

    func testJavaCactusAndCommandBlockRecipesAreBoundedAndDistinct() {
        let source = RasterAsset(width: 16, height: 16, pixels: [UInt8](repeating: 255, count: 16 * 16 * 4))
        let cactus = JavaCircuitArt.cactus.render(source)
        XCTAssertEqual(cactus.width, 16); XCTAssertEqual(cactus.height, 16)
        XCTAssertEqual(cactus.pixels[3], 0)
        XCTAssertEqual(cactus.pixels[(8 * 16 + 8) * 4 + 3], 255)
        let off = JavaCircuitArt.output(false).render(source)
        XCTAssertEqual(off.pixels, source.pixels)
        XCTAssertNotEqual(off.pixels, JavaCircuitArt.output(true).render(source).pixels)
    }

    @MainActor
    func testPinchPreservesAnchorClampsAndNeverChangesSavedWorldOrArea() throws {
        let app = AppState(), editor = EditorSession(), size = CGSize(width: 800, height: 600)
        let anchor = CGPoint(x: 230, y: 150), before = app.library
        let worldPoint = try XCTUnwrap(editor.mapper(size: size)).worldPoint(fromScreen: anchor)
        editor.magnify(by: 0.25, anchor: anchor, size: size)
        let after = try XCTUnwrap(editor.mapper(size: size)).worldPoint(fromScreen: anchor)
        XCTAssertEqual(after.x, worldPoint.x, accuracy: 0.000001)
        XCTAssertEqual(after.y, worldPoint.y, accuracy: 0.000001)
        let camera = editor.camera
        for invalid in [Double.nan, .infinity, -1, -2] { editor.magnify(by: invalid, anchor: anchor, size: size) }
        XCTAssertEqual(editor.camera, camera)
        editor.magnify(by: 1000, anchor: anchor, size: size)
        XCTAssertEqual(editor.camera.pointsPerTile, 128)
        editor.magnify(by: -0.9999, anchor: anchor, size: size)
        XCTAssertEqual(editor.camera.pointsPerTile, 16)
        XCTAssertEqual(app.library, before)
    }

    @MainActor
    func testHomeAndReturnToSavedViewHaveDistinctSelectionSemantics() throws {
        let app = AppState(), editor = EditorSession(), active = app.library.activeAreaID
        XCTAssertTrue(app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        XCTAssertTrue(app.saveArea(name: "Far", camera: CameraState(worldOrigin: WorldPoint(x: 40, y: 20), pointsPerTile: 64)))
        let other = app.selectedAreaID
        XCTAssertTrue(editor.selectArea(other, appState: app))
        editor.pan(by: CGSize(width: 80, height: 40), size: CGSize(width: 800, height: 600))
        XCTAssertTrue(editor.selectArea(other, appState: app))
        XCTAssertEqual(editor.camera.worldOrigin, WorldPoint(x: 40, y: 20))
        XCTAssertEqual(app.selectedAreaID, other)
        XCTAssertEqual(app.library.activeAreaID, active)
        editor.showDesktopArea(app)
        XCTAssertEqual(app.selectedAreaID, active)
        XCTAssertEqual(editor.camera.worldOrigin, app.desktopCamera.worldOrigin)
        XCTAssertEqual(EditorSession.Tool.allCases.filter { !$0.editsWorld }, [.select])
    }
}
