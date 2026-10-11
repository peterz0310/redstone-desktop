import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class WorldRendererTests: XCTestCase {
    @MainActor
    func testRendererFollowsDifferentModelCoordinatesAndRemovesOldContent() throws {
        let screen = ScreenDescriptor(id: "negative", frame: CGRect(x: -640, y: -100, width: 640, height: 480), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let button = WorldCoordinate(x: 1, y: 1), dust = WorldCoordinate(x: 2, y: 1), output = WorldCoordinate(x: 3, y: 1)
        let tile = WorldCoordinate(x: 0, y: 0)
        let world = World(tiles: [tile: Tile(terrain: .dirt, decoration: .rock)],
                          circuit: CircuitWorld(components: [button: CircuitComponent(kind: .button), dust: CircuitComponent(kind: .dust), output: CircuitComponent(kind: .output)]))
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        let terrain = try XCTUnwrap(scene.childNode(withName: "world-tiles"))
        scene.updateWorld(world)
        let buttonNode = try XCTUnwrap(layer.childNode(withName: "PRESS") as? SKShapeNode)
        XCTAssertEqual(buttonNode.path?.boundingBoxOfPath, mapper.sceneRect(forTile: button, on: screen).insetBy(dx: 8, dy: 8))
        let outputNode = try XCTUnwrap(layer.childNode(withName: "OUTPUT") as? SKShapeNode)
        XCTAssertEqual(outputNode.path?.boundingBoxOfPath, mapper.sceneRect(forTile: output, on: screen))
        XCTAssertEqual(terrain.children.count, 2)
        XCTAssertEqual((terrain.children.last as? SKLabelNode)?.text, "coal deposit")
        let offColor = buttonNode.strokeColor
        scene.updateWorld(world, poweredTiles: [button])
        XCTAssertNotEqual((layer.childNode(withName: "PRESS") as? SKShapeNode)?.strokeColor, offColor)
        XCTAssertEqual(layer.children.count, 4)
        scene.flashOutput(at: output)
        let flash = try XCTUnwrap(scene.childNode(withName: "output-flash")?.childNode(withName: "output-flash:\(output.x),\(output.y)") as? SKShapeNode)
        XCTAssertEqual(flash.path?.boundingBoxOfPath, mapper.sceneRect(forTile: output, on: screen).insetBy(dx: 3, dy: 3))
        scene.updateWorld(World())
        XCTAssertTrue(layer.children.isEmpty)
        XCTAssertTrue(terrain.children.isEmpty)
        XCTAssertEqual(scene.children.count, 10)
    }

    @MainActor
    func testRepeaterShowsOrientationDelayAndSimulationPowerAcrossResize() throws {
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: -640, y: -100, width: 640, height: 480), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let coordinate = WorldCoordinate(x: 2, y: 2)
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        for (direction, arrow) in [(Direction.north, "↑"), (.east, "→"), (.south, "↓"), (.west, "←")] {
            for delay in RepeaterDelay.allCases {
                let world = World(circuit: CircuitWorld(components: [coordinate: CircuitComponent(kind: .repeater, direction: direction, repeaterDelay: delay)]))
                scene.updateWorld(world)
                XCTAssertEqual((layer.childNode(withName: "repeater-label:2,2") as? SKLabelNode)?.text, "\(arrow) \(delay.rawValue)t")
                let node = try XCTUnwrap(layer.childNode(withName: "REPEATER") as? SKShapeNode)
                let bounds = try XCTUnwrap(node.path?.boundingBoxOfPath)
                let expected = mapper.sceneRect(forTile: coordinate, on: screen).insetBy(dx: 3.2, dy: 3.2)
                XCTAssertEqual(bounds.minX, expected.minX, accuracy: 0.000001)
                XCTAssertEqual(bounds.minY, expected.minY, accuracy: 0.000001)
                XCTAssertEqual(bounds.width, expected.width, accuracy: 0.000001)
                XCTAssertEqual(bounds.height, expected.height, accuracy: 0.000001)
                let icon = try XCTUnwrap(node.childNode(withName: "component-icon:2,2") as? SKSpriteNode)
                let expectedRotation: CGFloat
                switch direction {
                case .east: expectedRotation = 0
                case .north: expectedRotation = .pi / 2
                case .west: expectedRotation = .pi
                case .south: expectedRotation = -.pi / 2
                }
                XCTAssertEqual(icon.zRotation, expectedRotation, accuracy: 0.00001)
                let offTexture = try XCTUnwrap(icon.texture)
                let off = node.strokeColor
                scene.updateWorld(world, poweredTiles: [coordinate])
                XCTAssertNotEqual((layer.childNode(withName: "REPEATER") as? SKShapeNode)?.strokeColor, off)
                XCTAssertFalse((layer.childNode(withName: "REPEATER")?.childNode(withName: "component-icon:2,2") as? SKSpriteNode)?.texture === offTexture)
                scene.size = CGSize(width: 600, height: 450)
                XCTAssertEqual(layer.children.count, 2)
                XCTAssertEqual((layer.childNode(withName: "repeater-label:2,2") as? SKLabelNode)?.text, "\(arrow) \(delay.rawValue)t")
            }
        }
    }

    @MainActor
    func testVisibleModelTilesAreReevaluatedOnResizeWithoutNodeGrowth() throws {
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let world = World(tiles: [WorldCoordinate(x: 10, y: 0): Tile(terrain: .sand)])
        let terrain = try XCTUnwrap(scene.childNode(withName: "world-tiles"))
        scene.updateWorld(world)
        XCTAssertTrue(terrain.children.isEmpty)
        for _ in 0..<5 {
            scene.size = CGSize(width: 800, height: 480)
            XCTAssertEqual(terrain.children.count, 1)
            scene.size = CGSize(width: 640, height: 480)
            XCTAssertTrue(terrain.children.isEmpty)
        }
    }
}
