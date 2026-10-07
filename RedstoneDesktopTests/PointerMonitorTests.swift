import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class PointerMonitorTests: XCTestCase {
    @MainActor
    func testPointerMappingBoundariesOutsideAreaAndRestart() throws {
        let screen = ScreenDescriptor(id: "left", frame: CGRect(x: -1280, y: -200, width: 1280, height: 800), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        var point = CGPoint(x: -1216.001, y: -100)
        var updates: [PointerSnapshot] = []
        let monitor = PointerMonitor(screen: screen, mapper: mapper, mouseLocation: { point }, onChange: { updates.append($0) })
        defer { monitor.stop() }

        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(updates.last?.tile, WorldCoordinate(x: 0, y: 1))
        XCTAssertEqual(updates.last?.screenID, "left")
        monitor.start()
        monitor.sample()
        XCTAssertEqual(updates.count, 1, "Duplicate start/unchanged polls must not publish duplicates")

        point.x = -1216
        monitor.sample()
        XCTAssertEqual(updates.last?.tile, WorldCoordinate(x: 1, y: 1))
        point.x = 0
        monitor.sample()
        XCTAssertNil(updates.last?.tile)
        XCTAssertNil(updates.last?.worldPoint)
        XCTAssertNil(updates.last?.screenID)

        point = CGPoint(x: -1280, y: -200)
        monitor.sample()
        XCTAssertEqual(updates.last?.tile, WorldCoordinate(x: 0, y: 0))
        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        let count = updates.count
        point.x += 100
        monitor.sample()
        XCTAssertEqual(updates.count, count, "Stopped polling must not update the scene")
        monitor.start()
        XCTAssertEqual(updates.count, count + 1)
        XCTAssertEqual(updates.last?.tile, WorldCoordinate(x: 1, y: 0))
    }

    @MainActor
    func testHighlightUsesMapperAndHidesWithoutAddingNodes() throws {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: -1280, y: -200, width: 1280, height: 800), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: -2.5, y: 3.25), pointsPerTile: 48))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let highlight = try XCTUnwrap(scene.childNode(withName: "cursor-highlight") as? SKShapeNode)
        XCTAssertTrue(highlight.isHidden)
        let tile = WorldCoordinate(x: -1, y: 4)
        scene.updateHighlight(tile)
        XCTAssertEqual(scene.highlightedTile, tile)
        XCTAssertFalse(highlight.isHidden)
        XCTAssertEqual(highlight.path?.boundingBoxOfPath, mapper.sceneRect(forTile: tile, on: screen).insetBy(dx: 1, dy: 1))
        scene.updateHighlight(tile)
        scene.size = CGSize(width: 800, height: 600)
        XCTAssertEqual(scene.children.count, 3)
        XCTAssertFalse(highlight.isHidden)
        scene.updateHighlight(nil)
        XCTAssertNil(scene.highlightedTile)
        XCTAssertTrue(highlight.isHidden)
        XCTAssertEqual(scene.children.count, 3)
    }
}
