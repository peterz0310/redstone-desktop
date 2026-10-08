import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class AppearanceTests: XCTestCase {
    func testDecorationChoicesAreStableAcrossOrderSeedsAndIntegerLimits() {
        let coordinates = (-20...20).map { WorldCoordinate(x: $0, y: -$0) } + [WorldCoordinate(x: .min, y: .max)]
        let first = coordinates.map { DecorationAppearance.choose(.flower, at: $0, seed: 42) }
        XCTAssertEqual(Set(first), Set([.poppy, .dandelion, .blueOrchid, .allium, .oxeyeDaisy]))
        XCTAssertEqual(Array(first.reversed()), coordinates.reversed().map { DecorationAppearance.choose(.flower, at: $0, seed: 42) })
        XCTAssertNotEqual(first, coordinates.map { DecorationAppearance.choose(.flower, at: $0, seed: 2026) })
        XCTAssertEqual(Set(coordinates.map { DecorationAppearance.choose(.rock, at: $0, seed: 42) }), Set([.coal, .iron]))
        XCTAssertEqual(DecorationID.rock.rawValue, "rock", "Preserve legacy generator/save identity and blocking behavior")
    }

    @MainActor
    func testVariantAssetsResolveExactThenFamilyThenCompleteOriginalFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let red = RasterAsset(width: 1, height: 1, pixels: [200, 0, 0, 255])
        let blue = RasterAsset(width: 1, height: 1, pixels: [0, 0, 200, 255])
        try red.pngData().write(to: root.appendingPathComponent("red.png"))
        try blue.pngData().write(to: root.appendingPathComponent("blue.png"))
        try JSONEncoder().encode(PackManifest(name: "Variants", assets: ["decorationFlower": "red.png", "decorationDandelion": "blue.png", "decorationRock": "red.png"])).write(to: root.appendingPathComponent("pack.json"))
        let assets = AssetLibrary()
        assets.apply(try ResourcePackLoader.load(root))
        let flower = Tile(terrain: .grass, decoration: .flower)
        XCTAssertEqual(assets.pixel(flower, x: 0, y: 0, appearance: .dandelion).2, 200)
        XCTAssertEqual(assets.pixel(flower, x: 0, y: 0, appearance: .allium).0, 200)
        XCTAssertEqual(assets.pixel(Tile(terrain: .stone, decoration: .rock), x: 0, y: 0, appearance: .iron).0, 200)
        assets.useBuiltIn()
        let colors = [DecorationAppearance.poppy, .dandelion, .blueOrchid, .allium, .oxeyeDaisy].map {
            assets.pixel(flower, x: 3, y: 5, appearance: $0)
        }
        XCTAssertEqual(Set(colors.map { "\($0.0),\($0.1),\($0.2)" }).count, 5)
        for id in TextureAssetID.allCases { XCTAssertNotNil(assets.texture(for: id), id.rawValue) }
    }

    func testJavaCircuitRecipesHaveVisibleStatesOrientationAndContinuousBrightRedMaterial() {
        var pixels: [UInt8] = []
        for y in 0..<16 { for x in 0..<16 { pixels += [UInt8(x * 15), UInt8(y * 15), 40, 255] } }
        let source = RasterAsset(width: 16, height: 16, pixels: pixels)
        let pairs: [(JavaCircuitArt, JavaCircuitArt)] = [(.button(false), .button(true)), (.lever(false), .lever(true)), (.repeater(false), .repeater(true))]
        for pair in pairs {
            XCTAssertNotEqual(pair.0.render(source).pixels, pair.1.render(source).pixels)
        }
        XCTAssertEqual(Array(JavaCircuitArt.button(false).render(source).pixels.prefix(4)), [0, 0, 0, 0])
        XCTAssertEqual(Array(JavaCircuitArt.repeater(false).render(source).pixels.prefix(4)), Array(pixels[(15 * 16 * 4)..<(15 * 16 * 4 + 4)]))
        let transparent = RasterAsset(width: 1, height: 1, pixels: [0, 0, 0, 0])
        let on = JavaCircuitArt.dust(true).render(transparent).pixels
        let off = JavaCircuitArt.dust(false).render(transparent).pixels
        XCTAssertEqual(on[3], 255); XCTAssertGreaterThanOrEqual(on[0], 184)
        XCTAssertLessThan(on[1], 24); XCTAssertLessThan(on[2], 32)
        XCTAssertLessThan(off[0], on[0])
    }

    @MainActor
    func testWireWidthAndInactiveLeverTexturePreserveCommittedState() throws {
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 640), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let lever = WorldCoordinate(x: 1, y: 1), dust = WorldCoordinate(x: 2, y: 1)
        let world = World(circuit: CircuitWorld(components: [lever: CircuitComponent(kind: .lever), dust: CircuitComponent(kind: .dust)]))
        scene.updateWorld(world, poweredTiles: [], leverPositions: [lever])
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        let icon = try XCTUnwrap(layer.childNode(withName: "LEVER")?.childNode(withName: "component-icon:1,1") as? SKSpriteNode)
        let on = icon.texture
        XCTAssertGreaterThan(icon.size.width, 32)
        scene.updateWorld(world, leverPositions: [])
        XCTAssertFalse((layer.childNode(withName: "LEVER")?.childNode(withName: "component-icon:1,1") as? SKSpriteNode)?.texture === on)
        let wire = try XCTUnwrap(layer.childNode(withName: "dust-path") as? SKShapeNode)
        XCTAssertEqual(wire.path?.boundingBoxOfPath.height, 16)
        XCTAssertEqual(wire.fillColor.usingColorSpace(.sRGB)?.redComponent, 1)
        XCTAssertEqual(wire.fillColor.usingColorSpace(.sRGB)?.greenComponent, 1)
        XCTAssertEqual(wire.fillColor.usingColorSpace(.sRGB)?.blueComponent, 1)
        XCTAssertEqual(wire.lineWidth, 0)
    }
}
