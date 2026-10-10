import XCTest
@testable import RedstoneDesktop

final class PlacementRulesTests: XCTestCase {
    private let coordinate = WorldCoordinate(x: -4, y: -2)
    private let rules = PlacementRules()
    private var kinds: [CircuitComponentKind] { CircuitComponentKind.allCases.filter { $0 != .empty } }

    func testTerrainDefinitionsMatchCapabilityTable() {
        for id in TerrainID.allCases {
            let definition = id.definition
            let water = id == .shallowWater || id == .deepWater || id == .lava
            XCTAssertEqual(definition.id, id)
            XCTAssertEqual(definition.isLiquid, water)
            XCTAssertEqual(definition.isSolidSurface, !water)
            XCTAssertEqual(definition.supportsCircuit, !water)
            XCTAssertEqual(definition.supportsHeavyComponent, !water)
        }
    }

    func testEveryComponentAllowedOnEachDryTerrain() {
        for terrain in TerrainID.allCases.filter({ !$0.definition.isLiquid }) {
            let world = World(tiles: [coordinate: Tile(terrain: terrain)])
            for kind in kinds {
                XCTAssertEqual(rules.canPlace(component: CircuitComponent(kind: kind), at: coordinate, in: world), .allowed)
            }
        }
    }

    func testAllLiquidsRejectAllComponentsWithoutMutation() {
        for terrain in [TerrainID.shallowWater, .deepWater, .lava] {
            for kind in kinds {
                var world = World(tiles: [coordinate: Tile(terrain: terrain)])
                let before = world
                XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: kind), at: coordinate, in: &world), .rejected(.liquid))
                XCTAssertEqual(world, before)
            }
        }
    }

    func testEveryDecorationBlocksPlacementAndIsPreserved() {
        for decoration in DecorationID.allCases {
            for kind in kinds {
                var world = World(tiles: [coordinate: Tile(terrain: .grass, decoration: decoration)])
                let before = world
                XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: kind), at: coordinate, in: &world), .rejected(.blockedByDecoration(decoration)))
                XCTAssertEqual(world, before)
            }
        }
    }

    func testExistingComponentNeverSilentlyOverwrittenEvenByIdenticalPlacement() {
        for existingKind in kinds {
            let existing = CircuitComponent(kind: existingKind, direction: .west, repeaterDelay: .four)
            var world = World(tiles: [coordinate: Tile(terrain: .stone)], circuit: CircuitWorld(components: [coordinate: existing]))
            let before = world
            for proposedKind in kinds {
                XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: proposedKind), at: coordinate, in: &world), .rejected(.circuitOccupied))
                XCTAssertEqual(world, before)
            }
            XCTAssertEqual(CircuitPlacement().place(existing, at: coordinate, in: &world), .rejected(.circuitOccupied))
        }
    }

    func testSuccessfulTransactionPreservesOtherDataAndAllRepeaterConfiguration() {
        let other = WorldCoordinate(x: 2, y: 3)
        let existing = CircuitComponent(kind: .button)
        for direction in Direction.allCases {
            for delay in RepeaterDelay.allCases {
                var world = World(tiles: [coordinate: Tile(terrain: .sand), other: Tile(terrain: .dirt, decoration: .tree)],
                    circuit: CircuitWorld(components: [other: existing]))
                let terrainBefore = world.tiles
                let proposed = CircuitComponent(kind: .repeater, direction: direction, repeaterDelay: delay)
                XCTAssertEqual(CircuitPlacement().place(proposed, at: coordinate, in: &world), .allowed)
                XCTAssertEqual(world.tiles, terrainBefore)
                XCTAssertEqual(world.circuit.components[coordinate], proposed)
                XCTAssertEqual(world.circuit.components[other], existing)
            }
        }
    }

    func testUnspecifiedTerrainAndExtremeCoordinatesFailClosed() {
        for coordinate in [coordinate, WorldCoordinate(x: Int.min, y: Int.max)] {
            var world = World()
            XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: .dust), at: coordinate, in: &world), .rejected(.noSolidSurface))
            XCTAssertEqual(world, World())
        }
    }

    func testEmptyComponentIsNotEraseAndStoredEmptyCellDoesNotBlockPlacement() {
        var world = World(tiles: [coordinate: Tile(terrain: .grass)], circuit: CircuitWorld(components: [coordinate: CircuitComponent(kind: .empty)]))
        let before = world
        XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: .empty), at: coordinate, in: &world), .rejected(.emptyComponent))
        XCTAssertEqual(world, before)
        XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: .dust), at: coordinate, in: &world), .allowed)
        XCTAssertEqual(world.circuit.components[coordinate]?.kind, .dust)
    }

    func testReservedCoordinatesRejectOtherwiseValidPlacement() {
        var world = World(tiles: [coordinate: Tile(terrain: .grass)])
        let before = world
        let placement = CircuitPlacement(rules: PlacementRules(reservedCoordinates: [coordinate]))
        XCTAssertEqual(placement.place(CircuitComponent(kind: .lever), at: coordinate, in: &world), .rejected(.reserved))
        XCTAssertEqual(world, before)
    }

    func testRejectionPriorityAndMessagesAreDeterministic() {
        let world = World(tiles: [coordinate: Tile(terrain: .deepWater, decoration: .flower)],
                          circuit: CircuitWorld(components: [coordinate: CircuitComponent(kind: .output)]))
        XCTAssertEqual(rules.canPlace(component: CircuitComponent(kind: .dust), at: coordinate, in: world), .rejected(.liquid))
        let reasons: [PlacementFailureReason] = [.emptyComponent, .reserved, .noSolidSurface, .liquid,
            .unsupportedSurface, .blockedByDecoration(.tree), .circuitOccupied]
        XCTAssertTrue(reasons.allSatisfy { !PlacementResult.rejected($0).message.isEmpty })
    }

    func testRightwardFixturePreservesOriginalCircuitsAndDoesNotGenerateTerrain() {
        let original = DemoCircuit.makeWorld(), fixture = DeveloperPlacementFixture.makeWorld()
        XCTAssertEqual(fixture.circuit, original.circuit)
        for (coordinate, tile) in original.tiles { XCTAssertEqual(fixture.tiles[coordinate], tile) }
        XCTAssertTrue(DeveloperPlacementFixture.targets.allSatisfy { $0.coordinate.x > 7 })
        XCTAssertEqual(fixture.tiles.count, original.tiles.count + TerrainID.allCases.count + DecorationID.allCases.count)
        XCTAssertNil(fixture.tiles[WorldCoordinate(x: 14, y: 5)])
    }
}
