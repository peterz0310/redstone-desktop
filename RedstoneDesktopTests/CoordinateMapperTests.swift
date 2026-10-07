import Foundation
import XCTest
@testable import RedstoneDesktop

final class CoordinateMapperTests: XCTestCase {
    func testWorldScreenRoundTripsAcrossOriginsAndScales() throws {
        for frame in frames {
            for scale in [16.0, 48.0, 96.5] {
                let mapper = try makeMapper(frame: frame, scale: scale)
                for world in [WorldPoint(x: -142.25, y: 80), WorldPoint(x: 0, y: 0), WorldPoint(x: 37.125, y: -91.5)] {
                    let result = mapper.worldPoint(fromScreen: mapper.screenPoint(fromWorld: world))
                    XCTAssertEqual(result.x, world.x, accuracy: 1e-10)
                    XCTAssertEqual(result.y, world.y, accuracy: 1e-10)
                }
                for point in [frame.origin, CGPoint(x: frame.midX, y: frame.midY), CGPoint(x: frame.maxX, y: frame.maxY)] {
                    let result = mapper.screenPoint(fromWorld: mapper.worldPoint(fromScreen: point))
                    XCTAssertEqual(result.x, point.x, accuracy: 1e-10)
                    XCTAssertEqual(result.y, point.y, accuracy: 1e-10)
                }
            }
        }
    }

    func testCanvasLowerLeftIsExactlyCameraOrigin() throws {
        let mapper = try makeMapper(frame: frames[1], scale: 48)
        XCTAssertEqual(mapper.worldPoint(fromScreen: frames[1].origin), mapper.camera.worldOrigin)
        XCTAssertEqual(mapper.screenPoint(fromWorld: mapper.camera.worldOrigin), frames[1].origin)
    }

    func testExactTileBoundariesAndBothSidesThroughScreenMapping() throws {
        for scale in [16.0, 48.0, 96.5] {
            let mapper = try makeMapper(frame: frames[1], scale: scale)
            for boundary in [-3, -1, 0, 1, 4] {
                for offset in [-0.000001, 0, 0.000001] {
                    let world = WorldPoint(x: Double(boundary) + offset, y: Double(boundary) + offset)
                    let expected = offset < 0 ? boundary - 1 : boundary
                    XCTAssertEqual(mapper.tile(atScreen: mapper.screenPoint(fromWorld: world)), WorldCoordinate(x: expected, y: expected))
                }
            }
        }
    }

    func testNegativeFractionalPositionsFloorInsteadOfTruncating() throws {
        let mapper = try makeMapper()
        XCTAssertEqual(mapper.tile(containing: WorldPoint(x: -0.1, y: -1.9)), WorldCoordinate(x: -1, y: -2))
        XCTAssertEqual(mapper.tile(containing: WorldPoint(x: -1, y: 0)), WorldCoordinate(x: -1, y: 0))
    }

    func testDisplayRearrangementChangesScreenPositionButPreservesWorld() throws {
        let original = try makeMapper(frame: frames[0])
        let rearranged = try makeMapper(frame: frames[1])
        let world = WorldPoint(x: 4, y: -3)
        let before = original.screenPoint(fromWorld: world)
        let after = rearranged.screenPoint(fromWorld: world)
        XCTAssertEqual(after.x - before.x, frames[1].minX - frames[0].minX)
        XCTAssertEqual(after.y - before.y, frames[1].minY - frames[0].minY)
        XCTAssertEqual(rearranged.worldPoint(fromScreen: after), world)
    }

    func testRetinaScaleDoesNotChangeWorldOccupancy() throws {
        let mapper = try makeMapper(frame: frames[1])
        let point = CGPoint(x: -1000, y: 200)
        let screens = [1.0, 2.0].map { ScreenDescriptor(id: "display", frame: frames[1], backingScale: $0) }
        XCTAssertEqual(mapper.scenePoint(fromScreen: point, on: screens[0]), mapper.scenePoint(fromScreen: point, on: screens[1]))
        for screen in screens {
            let sameGeometry = try CoordinateMapper(canvasFrame: screen.frame, camera: mapper.camera)
            XCTAssertEqual(sameGeometry.tile(atScreen: point), mapper.tile(atScreen: point))
        }
    }

    func testTileRectangleAndSceneCoordinatesUseDisplayOrigin() throws {
        let screen = ScreenDescriptor(id: "left", frame: frames[1], backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let tile = WorldCoordinate(x: 2, y: 3)
        XCTAssertEqual(mapper.screenRect(forTile: tile), CGRect(x: -1152, y: -8, width: 64, height: 64))
        XCTAssertEqual(mapper.sceneRect(forTile: tile, on: screen), CGRect(x: 128, y: 192, width: 64, height: 64))
    }

    func testAdjacentDisplaysShareNoBoundaryPoints() {
        let left = ScreenDescriptor(id: "left", frame: frames[1], backingScale: 1)
        let right = ScreenDescriptor(id: "right", frame: CGRect(x: 0, y: -200, width: 1280, height: 800), backingScale: 2)
        XCTAssertTrue(left.contains(CGPoint(x: -1280, y: -200)))
        XCTAssertFalse(left.contains(CGPoint(x: 0, y: 0)))
        XCTAssertTrue(right.contains(CGPoint(x: 0, y: 0)))
        XCTAssertFalse(right.contains(CGPoint(x: 1280, y: 0)))
        XCTAssertFalse(right.contains(CGPoint(x: 0, y: 600)))
    }

    func testInvalidTransformIsRejectedAndInvalidTileDoesNotTrap() throws {
        for scale in [0.0, -1, .infinity, .nan] {
            XCTAssertThrowsError(try makeMapper(scale: scale))
        }
        XCTAssertThrowsError(try CoordinateMapper(canvasFrame: .zero, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)))
        XCTAssertThrowsError(try CoordinateMapper(canvasFrame: frames[0], camera: CameraState(worldOrigin: WorldPoint(x: .nan, y: 0), pointsPerTile: 64)))
        let mapper = try makeMapper()
        for value in [Double.nan, .infinity, -.infinity, Double(Int.max), Double.greatestFiniteMagnitude] {
            XCTAssertNil(mapper.tile(containing: WorldPoint(x: value, y: 0)))
            XCTAssertNil(mapper.tile(containing: WorldPoint(x: 0, y: value)))
        }
    }

    private var frames: [CGRect] {
        [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: -1280, y: -200, width: 1280, height: 800)]
    }

    private func makeMapper(frame: CGRect? = nil, scale: Double = 48) throws -> CoordinateMapper {
        try CoordinateMapper(canvasFrame: frame ?? frames[0], camera: CameraState(worldOrigin: WorldPoint(x: -4.25, y: 2.5), pointsPerTile: scale))
    }
}
