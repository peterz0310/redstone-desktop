import XCTest
@testable import RedstoneDesktop

final class CircuitSimulatorTests: XCTestCase {
    private func cell(_ x: Int, _ y: Int = 0) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    private func line(length: Int, source: CircuitComponentKind = .lever) -> CircuitWorld {
        var components: [WorldCoordinate: CircuitComponent] = [cell(0): CircuitComponent(kind: source)]
        for x in 1...length { components[cell(x)] = CircuitComponent(kind: .dust) }
        components[cell(length + 1)] = CircuitComponent(kind: .output)
        return CircuitWorld(components: components)
    }

    func testStraightLineAttenuatesAndEventuallyReachesZero() {
        var sim = CircuitSimulator(world: line(length: 18))
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), []) // final output is beyond the reach of power
        XCTAssertEqual(sim.power(at: cell(0)), .full)
        for x in 1...18 { XCTAssertEqual(sim.power(at: cell(x)), PowerLevel(16 - x)) }
        XCTAssertEqual(sim.power(at: cell(19)), .off)
    }

    func testOutputSensesDustWithoutRelayingAndHeldPowerDoesNotRetrigger() {
        var sim = CircuitSimulator(world: line(length: 4))
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(5))])
        XCTAssertEqual(sim.power(at: cell(5)), PowerLevel(12))
        for _ in 0..<100 { XCTAssertEqual(sim.advanceTick(), []) }
        XCTAssertEqual(sim.power(at: cell(0)), .full)
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertTrue(sim.poweredTiles.isEmpty)
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(5))])
    }

    func testButtonHasExactlyTwentyPoweredSnapshotsAndThenExpires() {
        var sim = CircuitSimulator(world: line(length: 1, source: .button))
        sim.pressButton(at: cell(0))
        XCTAssertTrue(sim.poweredTiles.isEmpty, "Input does not commit simulation early")
        for tick in 1...20 {
            XCTAssertEqual(sim.advanceTick(), tick == 1 ? [.outputActivated(cell(2))] : [])
            XCTAssertEqual(sim.power(at: cell(0)), .full)
        }
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertTrue(sim.poweredTiles.isEmpty)
        sim.pressButton(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(2))])
    }

    func testPressWhileActiveRestartsPulseWithoutExtraActivation() {
        var sim = CircuitSimulator(world: line(length: 1, source: .button))
        sim.pressButton(at: cell(0))
        for _ in 0..<10 { _ = sim.advanceTick() }
        sim.pressButton(at: cell(0))
        for _ in 0..<20 {
            XCTAssertEqual(sim.advanceTick(), [])
            XCTAssertEqual(sim.power(at: cell(0)), .full)
        }
        _ = sim.advanceTick()
        XCTAssertTrue(sim.poweredTiles.isEmpty)
    }

    func testLoopsAreBoundedAndLosePowerImmediatelyAfterSourceTurnsOff() {
        var components: [WorldCoordinate: CircuitComponent] = [cell(-1): CircuitComponent(kind: .lever)]
        for point in [cell(0), cell(1), cell(1, 1), cell(0, 1)] { components[point] = CircuitComponent(kind: .dust) }
        var sim = CircuitSimulator(world: CircuitWorld(components: components))
        sim.toggleLever(at: cell(-1))
        for _ in 0..<100 {
            _ = sim.advanceTick()
            XCTAssertEqual(sim.power(at: cell(0)), .full)
            XCTAssertEqual(sim.power(at: cell(1, 1)), PowerLevel(13))
        }
        sim.toggleLever(at: cell(-1))
        _ = sim.advanceTick()
        XCTAssertTrue(sim.poweredTiles.isEmpty)
    }

    func testInsertionOrderDoesNotChangePowerOrEventOrder() {
        let world = DemoCircuit.makeWorld().circuit
        let entries = world.components.sorted { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }
        var a = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries)))
        var b = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries.reversed())))
        a.pressButton(at: DemoCircuit.button); b.pressButton(at: DemoCircuit.button)
        a.toggleLever(at: DemoCircuit.lever); b.toggleLever(at: DemoCircuit.lever)
        for _ in 0..<30 {
            XCTAssertEqual(a.advanceTick(), b.advanceTick())
            XCTAssertEqual(a.power, b.power)
        }
    }

    func testStrongestSourceWinsAndRemovingOneKeepsOutputPowered() {
        var components = line(length: 4).components
        components[cell(3, 1)] = CircuitComponent(kind: .lever)
        var sim = CircuitSimulator(world: CircuitWorld(components: components))
        sim.toggleLever(at: cell(0))
        _ = sim.advanceTick()
        XCTAssertEqual(sim.power(at: cell(4)), PowerLevel(12))
        sim.toggleLever(at: cell(3, 1))
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertEqual(sim.power(at: cell(4)), PowerLevel(14))
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertEqual(sim.power(at: cell(5)), PowerLevel(14))
    }

    func testOutputIsNotASourceAndThereIsNoDiagonalConnection() {
        let world = CircuitWorld(components: [cell(0): CircuitComponent(kind: .lever),
            cell(1): CircuitComponent(kind: .output), cell(2): CircuitComponent(kind: .dust),
            cell(1, 1): CircuitComponent(kind: .dust), cell(0, 1): CircuitComponent(kind: .empty)])
        var sim = CircuitSimulator(world: world)
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(1))])
        XCTAssertEqual(sim.power(at: cell(2)), .off)
        XCTAssertEqual(sim.power(at: cell(1, 1)), .off)
    }

    func testAdjacentOutputsDoNotRelayPowerDuringTwoPhaseEvaluation() {
        var sim = CircuitSimulator(world: CircuitWorld(components: [cell(0): CircuitComponent(kind: .lever),
            cell(1): CircuitComponent(kind: .output), cell(2): CircuitComponent(kind: .output)]))
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(1))])
        XCTAssertEqual(sim.power(at: cell(2)), .off)
    }

    func testDisconnectedComponentsInvalidInputsAndSidewaysRepeater() {
        let world = CircuitWorld(components: [cell(0): CircuitComponent(kind: .lever),
            cell(1): CircuitComponent(kind: .repeater), cell(2): CircuitComponent(kind: .output)])
        var sim = CircuitSimulator(world: world)
        XCTAssertFalse(sim.pressButton(at: cell(0)))
        XCTAssertFalse(sim.toggleLever(at: cell(2)))
        XCTAssertFalse(sim.pressButton(at: cell(100)))
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertEqual(sim.power(at: cell(2)), .off)
    }

    func testNegativeCoordinatesAndIntegerLimitsAreSafe() {
        let source = cell(Int.max, Int.min), dust = cell(Int.max - 1, Int.min)
        var sim = CircuitSimulator(world: CircuitWorld(components: [source: CircuitComponent(kind: .lever), dust: CircuitComponent(kind: .dust)]))
        sim.toggleLever(at: source)
        _ = sim.advanceTick()
        XCTAssertEqual(sim.power(at: dust), .full)
    }

    func testLargeCyclicGridCompletesAndContainsOnlyClampedPositivePower() {
        var components: [WorldCoordinate: CircuitComponent] = [cell(-1): CircuitComponent(kind: .lever)]
        for y in 0..<40 { for x in 0..<40 { components[cell(x, y)] = CircuitComponent(kind: .dust) } }
        var sim = CircuitSimulator(world: CircuitWorld(components: components))
        sim.toggleLever(at: cell(-1))
        _ = sim.advanceTick()
        XCTAssertTrue(sim.power.values.allSatisfy { $0 > .off && $0 <= .full })
        XCTAssertEqual(sim.power(at: cell(39, 39)), .off)
        sim.toggleLever(at: cell(-1))
        _ = sim.advanceTick()
        XCTAssertTrue(sim.poweredTiles.isEmpty)
    }
}
