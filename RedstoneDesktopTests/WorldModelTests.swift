import Foundation
import XCTest
@testable import RedstoneDesktop

final class WorldModelTests: XCTestCase {
    func testEmptyWorldDoesNotGenerateOrAssumeTerrain() {
        let world = World()
        XCTAssertTrue(world.tiles.isEmpty)
        XCTAssertTrue(world.circuit.components.isEmpty)
        XCTAssertNil(world.tiles[WorldCoordinate(x: -100, y: 200)])
    }

    func testTerrainAndCircuitRemainIndependentValueData() {
        let coordinate = WorldCoordinate(x: -2, y: 4)
        var original = World(tiles: [coordinate: Tile(terrain: .grass, decoration: .flower)],
            circuit: CircuitWorld(components: [coordinate: CircuitComponent(kind: .repeater, direction: .east)]))
        let copy = original
        original.tiles[coordinate]?.terrain = .sand
        original.circuit.components.removeValue(forKey: coordinate)
        XCTAssertEqual(copy.tiles[coordinate], Tile(terrain: .grass, decoration: .flower))
        XCTAssertEqual(copy.circuit.components[coordinate]?.direction, .east)
        XCTAssertEqual(original.tiles[coordinate]?.decoration, .flower)
        XCTAssertTrue(original.circuit.components.isEmpty)
    }

    func testCodableRoundTripPreservesNegativeCoordinatesAndIdentities() throws {
        var world = World()
        for (index, terrain) in TerrainID.allCases.enumerated() {
            world.tiles[WorldCoordinate(x: -index - 1, y: index)] = Tile(terrain: terrain,
                decoration: index < DecorationID.allCases.count ? DecorationID.allCases[index] : nil)
        }
        for (index, kind) in CircuitComponentKind.allCases.enumerated() {
            world.circuit.components[WorldCoordinate(x: index, y: -index)] = CircuitComponent(kind: kind, direction: .west)
        }
        XCTAssertEqual(try JSONDecoder().decode(World.self, from: JSONEncoder().encode(world)), world)
    }

    func testCardinalAdjacencyExcludesDiagonalEmptyAndMissingCells() {
        let origin = WorldCoordinate(x: -2, y: -3)
        let north = WorldCoordinate(x: -2, y: -2), east = WorldCoordinate(x: -1, y: -3)
        let south = WorldCoordinate(x: -2, y: -4), diagonal = WorldCoordinate(x: -1, y: -2)
        let world = CircuitWorld(components: [north: CircuitComponent(kind: .dust), east: CircuitComponent(kind: .output),
                                            south: CircuitComponent(kind: .empty), diagonal: CircuitComponent(kind: .button)])
        XCTAssertEqual(world.occupiedCardinalNeighbors(at: origin), [north, east])
    }

    func testAdjacencyAtIntegerLimitsDoesNotOverflow() {
        let origin = WorldCoordinate(x: Int.max, y: Int.min)
        let north = WorldCoordinate(x: Int.max, y: Int.min + 1)
        let west = WorldCoordinate(x: Int.max - 1, y: Int.min)
        let world = CircuitWorld(components: [north: CircuitComponent(kind: .dust), west: CircuitComponent(kind: .dust)])
        XCTAssertEqual(world.occupiedCardinalNeighbors(at: origin), [north, west])
    }

    func testFeasibilityFixtureIsModelDataAndPowerIsRuntimeState() {
        let world = FixedTestCircuit.makeWorld()
        XCTAssertEqual(world.circuit.components.count, 6)
        XCTAssertEqual(world.tiles.count, 6)
        XCTAssertEqual(world.circuit.components[FixedTestCircuit.button]?.kind, .button)
        XCTAssertEqual(world.circuit.components[FixedTestCircuit.output]?.kind, .output)
        var pulse = FixedTestCircuit()
        XCTAssertTrue(pulse.poweredTiles.isEmpty)
        _ = pulse.press(at: FixedTestCircuit.button)
        XCTAssertEqual(pulse.poweredTiles, Set(world.circuit.components.keys))
    }
}
