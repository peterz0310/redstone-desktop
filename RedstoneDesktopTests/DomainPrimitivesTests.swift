import Foundation
import XCTest
@testable import RedstoneDesktop

final class DomainPrimitivesTests: XCTestCase {
    func testTileCoordinatesPreserveNegativeAndExtremeValues() throws {
        let coordinates = [
            WorldCoordinate(x: -142, y: 81),
            WorldCoordinate(x: 0, y: 0),
            WorldCoordinate(x: Int.min, y: Int.max)
        ]
        for coordinate in coordinates {
            try assertJSONRoundTrip(coordinate)
        }
        XCTAssertEqual(Set(coordinates + coordinates).count, 3)
        XCTAssertNotEqual(coordinates[0], WorldCoordinate(x: -142, y: 82))
    }

    func testFractionalWorldPointRoundTripAndEquality() throws {
        let point = WorldPoint(x: -142.25, y: 80.5)
        try assertJSONRoundTrip(point)
        XCTAssertNotEqual(point, WorldPoint(x: -142, y: 80.5))
    }

    func testCameraPreservesOriginAndLogicalScale() throws {
        let origin = WorldPoint(x: -142.25, y: 80)
        for scale in [24.0, 48.0, 96.5] {
            try assertJSONRoundTrip(CameraState(worldOrigin: origin, pointsPerTile: scale))
        }
        XCTAssertNotEqual(
            CameraState(worldOrigin: origin, pointsPerTile: 48),
            CameraState(worldOrigin: origin, pointsPerTile: 96)
        )
    }

    func testAllDirectionsAndComponentKindsRoundTrip() throws {
        for direction in Direction.allCases {
            try assertJSONRoundTrip(direction)
            for kind in CircuitComponentKind.allCases {
                try assertJSONRoundTrip(kind)
                try assertJSONRoundTrip(CircuitComponent(kind: kind, direction: direction))
            }
        }
        XCTAssertNotEqual(CircuitComponent(kind: .dust), CircuitComponent(kind: .output))
        XCTAssertNotEqual(
            CircuitComponent(kind: .repeater, direction: .east),
            CircuitComponent(kind: .repeater, direction: .west)
        )
    }

    func testPowerClampsWithoutOverflowAndComparesNumerically() throws {
        for value in [Int.min, -1, 0] {
            XCTAssertEqual(PowerLevel(value), .off)
        }
        for value in [15, 16, 256, Int.max] {
            XCTAssertEqual(PowerLevel(value), .full)
        }
        for value in 0...15 {
            let power = PowerLevel(value)
            XCTAssertEqual(Int(power.rawValue), value)
            try assertJSONRoundTrip(power)
        }
        XCTAssertLessThan(PowerLevel.off, PowerLevel(1))
        XCTAssertLessThan(PowerLevel(14), .full)
    }

    func testJSONCannotBypassPowerRange() throws {
        for (json, expected) in [
            (#"{"rawValue":-1}"#, PowerLevel.off),
            (#"{"rawValue":7}"#, PowerLevel(7)),
            (#"{"rawValue":256}"#, PowerLevel.full)
        ] {
            XCTAssertEqual(try JSONDecoder().decode(PowerLevel.self, from: Data(json.utf8)), expected)
        }
        for json in [#"{}"#, #"{"rawValue":"15"}"#, #"{"rawValue":null}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(PowerLevel.self, from: Data(json.utf8)))
        }
    }

    func testUnknownKindsAndDirectionsAreRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(Direction.self, from: Data(#""up""#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(CircuitComponentKind.self, from: Data(#""unknown-component""#.utf8)))
    }

    private func assertJSONRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(T.self, from: data), value, file: file, line: line)
    }
}
