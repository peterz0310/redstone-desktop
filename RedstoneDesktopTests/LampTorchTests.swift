import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class LampTorchTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 0) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }

    func testLampSensesPowerOnAllSidesAndNeverRelaysOrExecutesActions() {
        for direction in Direction.allCases {
            let lamp = p(0), source = direction.neighbor(of: lamp)!
            var circuit = CircuitWorld()
            circuit.components[lamp] = CircuitComponent(kind: .lamp)
            circuit.components[source] = CircuitComponent(kind: .lever)
            circuit.components[direction.opposite.neighbor(of: lamp)!] = CircuitComponent(kind: .output)
            var sim = CircuitSimulator(world: circuit)
            XCTAssertTrue(sim.toggleLever(at: source))
            XCTAssertTrue(sim.advanceTick().isEmpty)
            XCTAssertEqual(sim.power(at: lamp), .full)
            XCTAssertEqual(sim.poweredTiles.count, 2)
            XCTAssertTrue(sim.toggleLever(at: source))
            XCTAssertTrue(sim.advanceTick().isEmpty)
            XCTAssertEqual(sim.power(at: lamp), .off)
        }
    }

    func testLampReceivesAttenuatedDustAndRepeaterFrontButNotSide() {
        var circuit = CircuitWorld()
        circuit.components[p(0)] = CircuitComponent(kind: .lever)
        circuit.components[p(1)] = CircuitComponent(kind: .dust)
        circuit.components[p(2)] = CircuitComponent(kind: .dust)
        circuit.components[p(3)] = CircuitComponent(kind: .lamp)
        circuit.components[p(4)] = CircuitComponent(kind: .repeater, direction: .east)
        circuit.components[p(5)] = CircuitComponent(kind: .dust)
        var sim = CircuitSimulator(world: circuit)
        sim.toggleLever(at: p(0))
        for _ in 0..<5 { XCTAssertTrue(sim.advanceTick().isEmpty) }
        XCTAssertEqual(sim.power(at: p(3)), PowerLevel(14))
        XCTAssertEqual(sim.power(at: p(4)), .off, "A lamp is a sink, even next to a repeater rear")
        circuit.components[p(2)] = CircuitComponent(kind: .repeater, direction: .east)
        circuit.components[p(2, 1)] = CircuitComponent(kind: .lamp)
        sim = CircuitSimulator(world: circuit); sim.toggleLever(at: p(0))
        for _ in 0..<5 { _ = sim.advanceTick() }
        XCTAssertEqual(sim.power(at: p(3)), .full)
        XCTAssertEqual(sim.power(at: p(2, 1)), .off)
    }

    func testRegularTorchHasNoSignalAndNewComponentsRoundTrip() throws {
        var circuit = CircuitWorld()
        circuit.components[p(0)] = CircuitComponent(kind: .lightTorch)
        circuit.components[p(1)] = CircuitComponent(kind: .dust)
        circuit.components[p(-1)] = CircuitComponent(kind: .output)
        circuit.components[p(0, 1)] = CircuitComponent(kind: .repeater)
        circuit.components[p(0, -1)] = CircuitComponent(kind: .lamp)
        var sim = CircuitSimulator(world: circuit)
        for _ in 0..<30 { XCTAssertTrue(sim.advanceTick().isEmpty); XCTAssertTrue(sim.power.isEmpty) }
        XCTAssertFalse(sim.pressButton(at: p(0))); XCTAssertFalse(sim.toggleLever(at: p(0)))
        let decoded = try JSONDecoder().decode(CircuitWorld.self, from: JSONEncoder().encode(circuit))
        XCTAssertEqual(decoded, circuit)
    }

    @MainActor func testBothBuildModesExposeToolsAndOriginalArtAndJavaImports() throws {
        XCTAssertEqual(EditorSession.Tool.lamp.componentKind, .lamp)
        XCTAssertEqual(EditorSession.Tool.lightTorch.componentKind, .lightTorch)
        XCTAssertEqual(DesktopBuildSession.Tool.lamp.kind, .lamp)
        XCTAssertEqual(DesktopBuildSession.Tool.lightTorch.kind, .lightTorch)
        XCTAssertEqual(DesktopBuildSession.Tool.allCases[7], .pressurePlate, "Keep existing keyboard shortcuts")
        let assets = BuiltInAssetProvider()
        for id in [TextureAssetID.redstoneLampOff, .redstoneLampOn, .lightTorch] { XCTAssertNotNil(assets.texture(for: id)) }
        XCTAssertNotEqual(CircuitTextures.image(for: .lampOff).tiffRepresentation, CircuitTextures.image(for: .lampOn).tiffRepresentation)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LampImport-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let blocks = root.appendingPathComponent("source/assets/minecraft/textures/block")
        try FileManager.default.createDirectory(at: blocks, withIntermediateDirectories: true)
        let image = RasterAsset(width: 2, height: 2, pixels: [UInt8](repeating: 255, count: 16))
        for name in ["redstone_lamp", "redstone_lamp_on", "torch"] { try image.pngData().write(to: blocks.appendingPathComponent(name + ".png")) }
        let imported = try JavaTextureImporter.importTextures(from: root.appendingPathComponent("source"), cacheRoot: root.appendingPathComponent("cache"))
        for id in [TextureAssetID.redstoneLampOff, .redstoneLampOn, .lightTorch] { XCTAssertNotNil(imported.pack.textures[id]) }
    }

    @MainActor func testTorchAlwaysLightsGroundAndLampLightsOnlyWithPower() throws {
        let screen = ScreenDescriptor(id: "lamp", frame: CGRect(x: 0, y: 0, width: 320, height: 320), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 32))
        let root = SKNode(), layer = SKNode(), renderer = WorldLightingRenderer()
        let ground = SKSpriteNode(color: .white, size: screen.frame.size); ground.anchorPoint = .zero
        root.addChild(ground); layer.zPosition = 1; root.addChild(layer)
        let tile = p(4, 4), view = SKView(frame: screen.frame)
        var world = World(); world.lighting = WorldLightingSettings(mode: .night)
        func brightness() throws -> CGFloat {
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(view.texture(from: root, crop: screen.frame)).cgImage())
            let rect = mapper.sceneRect(forTile: tile, on: screen)
            return try XCTUnwrap(bitmap.colorAt(x: Int(rect.midX * Double(bitmap.pixelsWide) / 320), y: bitmap.pixelsHigh - 1 - Int(rect.midY * Double(bitmap.pixelsHigh) / 320))?.usingColorSpace(.deviceRGB)).redComponent
        }
        world.circuit.components[tile] = CircuitComponent(kind: .lamp)
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, time: 0)
        let dark = try brightness()
        renderer.render(world: world, lava: [], power: [tile: .full], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertGreaterThan(try brightness(), dark + 0.4)
        world.circuit.components[tile] = CircuitComponent(kind: .lightTorch)
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertGreaterThan(try brightness(), dark + 0.4)
        world.lighting?.localLights = false
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertEqual(try brightness(), dark, accuracy: 0.03)
    }
}
