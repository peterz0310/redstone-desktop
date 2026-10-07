import Foundation
import XCTest
@testable import RedstoneDesktop

final class RepeaterTests: XCTestCase {
    private func cell(_ x: Int, _ y: Int = 0) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    private func line(_ delay: RepeaterDelay, source: CircuitComponentKind = .lever) -> CircuitWorld {
        CircuitWorld(components: [cell(0): CircuitComponent(kind: source),
            cell(1): CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: delay),
            cell(2): CircuitComponent(kind: .output)])
    }

    func testEveryDelayShiftsBothEdgesByExactNumberOfSimulationTicks() {
        for delay in RepeaterDelay.allCases {
            var sim = CircuitSimulator(world: line(delay))
            sim.toggleLever(at: cell(0))
            for tick in 1...delay.simulationTicks {
                XCTAssertEqual(sim.advanceTick(), [], "delay \(delay), tick \(tick)")
                XCTAssertEqual(sim.power(at: cell(1)), .off)
            }
            XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(2))])
            XCTAssertEqual(sim.power(at: cell(1)), .full)
            for _ in 0..<20 { XCTAssertEqual(sim.advanceTick(), []) }
            sim.toggleLever(at: cell(0))
            for _ in 0..<delay.simulationTicks {
                XCTAssertEqual(sim.advanceTick(), [])
                XCTAssertEqual(sim.power(at: cell(2)), .full)
            }
            XCTAssertEqual(sim.advanceTick(), [])
            XCTAssertTrue(sim.poweredTiles.isEmpty)
            sim.toggleLever(at: cell(0))
            for _ in 0..<delay.simulationTicks { XCTAssertEqual(sim.advanceTick(), []) }
            XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(2))])
        }
    }

    func testButtonPulsePreservesTwentySnapshotsAfterEveryDelay() {
        for delay in RepeaterDelay.allCases {
            var sim = CircuitSimulator(world: line(delay, source: .button))
            sim.pressButton(at: cell(0))
            for tick in 1...(delay.simulationTicks + 21) {
                let events = sim.advanceTick()
                let powered = tick > delay.simulationTicks && tick <= delay.simulationTicks + 20
                XCTAssertEqual(sim.power(at: cell(2)), powered ? .full : .off)
                XCTAssertEqual(events, tick == delay.simulationTicks + 1 ? [.outputActivated(cell(2))] : [])
            }
            XCTAssertTrue(sim.poweredTiles.isEmpty)
        }
    }

    func testOneTickPulseIsRetainedEvenIfSourceTurnsOffBeforeDelayExpires() {
        var sim = CircuitSimulator(world: line(.four))
        sim.toggleLever(at: cell(0))
        _ = sim.advanceTick()
        sim.toggleLever(at: cell(0))
        for _ in 2...8 { XCTAssertEqual(sim.advanceTick(), []) }
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(2))])
        XCTAssertEqual(sim.power(at: cell(2)), .full)
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertTrue(sim.poweredTiles.isEmpty)
    }

    func testEveryOrientationReadsRearAndSuppliesFrontOutput() throws {
        let repeater = cell(-10, -10)
        for direction in Direction.allCases {
            let rear = try XCTUnwrap(direction.opposite.neighbor(of: repeater))
            let front = try XCTUnwrap(direction.neighbor(of: repeater))
            var sim = CircuitSimulator(world: CircuitWorld(components: [
                rear: CircuitComponent(kind: .lever), front: CircuitComponent(kind: .output),
                repeater: CircuitComponent(kind: .repeater, direction: direction)]))
            sim.toggleLever(at: rear)
            XCTAssertEqual(sim.advanceTick(), [])
            XCTAssertEqual(sim.advanceTick(), [])
            XCTAssertEqual(sim.advanceTick(), [.outputActivated(front)])
            XCTAssertEqual(sim.power(at: repeater), .full)
        }
    }

    func testFrontAndSideInputsNeverPowerRepeaterInAnyOrientation() throws {
        let repeater = cell(0)
        for facing in Direction.allCases {
            for inputDirection in Direction.allCases where inputDirection != facing.opposite {
                let source = try XCTUnwrap(inputDirection.neighbor(of: repeater))
                var sim = CircuitSimulator(world: CircuitWorld(components: [
                    source: CircuitComponent(kind: .lever),
                    repeater: CircuitComponent(kind: .repeater, direction: facing)]))
                sim.toggleLever(at: source)
                for _ in 0..<20 {
                    XCTAssertEqual(sim.advanceTick(), [])
                    XCTAssertEqual(sim.power(at: repeater), .off)
                }
            }
        }
    }

    func testRepeaterDoesNotEmitToSideOrRearDustOrOutputs() {
        for kind in [CircuitComponentKind.dust, .output] {
            let source = cell(-2)
            let rearDust = cell(-1)
            var sim = CircuitSimulator(world: CircuitWorld(components: [
                source: CircuitComponent(kind: .lever), rearDust: CircuitComponent(kind: .dust),
                cell(0): CircuitComponent(kind: .repeater, direction: .east),
                cell(1): CircuitComponent(kind: kind), cell(0, 1): CircuitComponent(kind: kind),
                cell(0, -1): CircuitComponent(kind: kind)]))
            sim.toggleLever(at: source)
            for _ in 0..<3 { _ = sim.advanceTick() }
            XCTAssertEqual(sim.power(at: cell(1)), .full)
            XCTAssertEqual(sim.power(at: cell(0, 1)), .off)
            XCTAssertEqual(sim.power(at: cell(0, -1)), .off)
            sim.toggleLever(at: source)
            _ = sim.advanceTick()
            XCTAssertEqual(sim.power(at: rearDust), .off, "Powered repeater must not feed its rear")
        }
    }

    func testWeakRearDustIsRestoredToFifteenAndForwardDustAttenuatesAgain() {
        var components = [cell(0): CircuitComponent(kind: .lever)]
        for x in 1...14 { components[cell(x)] = CircuitComponent(kind: .dust) }
        components[cell(15)] = CircuitComponent(kind: .repeater, direction: .east)
        components[cell(16)] = CircuitComponent(kind: .dust)
        components[cell(17)] = CircuitComponent(kind: .dust)
        components[cell(18)] = CircuitComponent(kind: .output)
        var sim = CircuitSimulator(world: CircuitWorld(components: components))
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertEqual(sim.power(at: cell(14)), PowerLevel(2))
        XCTAssertEqual(sim.advanceTick(), [])
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(18))])
        XCTAssertEqual(sim.power(at: cell(15)), .full)
        XCTAssertEqual(sim.power(at: cell(16)), .full)
        XCTAssertEqual(sim.power(at: cell(17)), PowerLevel(14))
        XCTAssertEqual(sim.power(at: cell(18)), PowerLevel(14))
    }

    func testAlignedChainAddsDelaysAndReversedRepeaterBlocksSignal() {
        var components = line(.one).components
        components[cell(2)] = CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: .two)
        components[cell(3)] = CircuitComponent(kind: .output)
        var sim = CircuitSimulator(world: CircuitWorld(components: components))
        sim.toggleLever(at: cell(0))
        for _ in 0..<6 { XCTAssertEqual(sim.advanceTick(), []) }
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(3))])
        sim.toggleLever(at: cell(0))
        for _ in 0..<6 { _ = sim.advanceTick(); XCTAssertEqual(sim.power(at: cell(3)), .full) }
        _ = sim.advanceTick()
        XCTAssertTrue(sim.poweredTiles.isEmpty)
        components[cell(2)]?.direction = .west
        var reversed = CircuitSimulator(world: CircuitWorld(components: components))
        reversed.toggleLever(at: cell(0))
        for _ in 0..<30 {
            XCTAssertEqual(reversed.advanceTick(), [])
            XCTAssertEqual(reversed.power(at: cell(2)), .off)
        }
    }

    func testOutputsCannotFeedRearInputs() {
        let components = [cell(0): CircuitComponent(kind: .lever), cell(1): CircuitComponent(kind: .output),
            cell(2): CircuitComponent(kind: .repeater, direction: .east), cell(3): CircuitComponent(kind: .output)]
        var sim = CircuitSimulator(world: CircuitWorld(components: components))
        sim.toggleLever(at: cell(0))
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(cell(1))])
        for _ in 0..<20 { XCTAssertEqual(sim.advanceTick(), []) }
        XCTAssertEqual(sim.power(at: cell(2)), .off)
        XCTAssertEqual(sim.power(at: cell(3)), .off)
    }

    func testRepeaterNetworksAreInsertionOrderIndependentAndBoundedOverManyTicks() {
        var components = DemoCircuit.makeWorld().circuit.components
        // A large grid of repeaters exercises bounded histories even with no input.
        for y in 10..<30 { for x in 0..<20 {
            components[cell(x, y)] = CircuitComponent(kind: .repeater, direction: .east,
                repeaterDelay: RepeaterDelay.allCases[(x + y) % 4])
        } }
        let entries = components.sorted { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }
        var a = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries)))
        var b = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries.reversed())))
        for simTick in 0..<100 {
            if simTick % 17 == 0 {
                a.pressButton(at: DemoCircuit.repeaterButton); b.pressButton(at: DemoCircuit.repeaterButton)
            }
            XCTAssertEqual(a.advanceTick(), b.advanceTick())
            XCTAssertEqual(a, b)
        }
    }

    func testDelayedFeedbackLoopRunsBoundedlyWithoutInsertionOrderEffects() {
        let source = cell(-2)
        var components = [source: CircuitComponent(kind: .lever),
            cell(0): CircuitComponent(kind: .repeater, direction: .east),
            cell(2, 3): CircuitComponent(kind: .repeater, direction: .north, repeaterDelay: .four)]
        for point in [cell(1), cell(2), cell(2, 1), cell(2, 2), cell(2, 4), cell(1, 4),
                      cell(0, 4), cell(-1, 4), cell(-1, 3), cell(-1, 2), cell(-1, 1), cell(-1)] {
            components[point] = CircuitComponent(kind: .dust)
        }
        let entries = components.sorted { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }
        var a = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries)))
        var b = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries.reversed())))
        a.toggleLever(at: source); b.toggleLever(at: source)
        var observedDelayedPower = false
        for tick in 1...200 {
            XCTAssertEqual(a.advanceTick(), b.advanceTick())
            XCTAssertEqual(a, b)
            XCTAssertTrue(a.power.values.allSatisfy { $0 > .off && $0 <= .full })
            if a.power(at: cell(2, 3)) == .full { observedDelayedPower = true }
            if tick == 1 { a.toggleLever(at: source); b.toggleLever(at: source) }
        }
        XCTAssertTrue(observedDelayedPower, "The test must exercise the delayed feedback path")
    }

    func testDirectionAtIntegerLimitsAndRepeaterOutOfBoundsAreSafe() {
        XCTAssertNil(Direction.east.neighbor(of: cell(Int.max)))
        XCTAssertNil(Direction.west.neighbor(of: cell(Int.min)))
        XCTAssertNil(Direction.north.neighbor(of: cell(0, Int.max)))
        XCTAssertNil(Direction.south.neighbor(of: cell(0, Int.min)))
        let repeater = cell(Int.max, Int.min), rear = cell(Int.max - 1, Int.min)
        var sim = CircuitSimulator(world: CircuitWorld(components: [rear: CircuitComponent(kind: .lever),
            repeater: CircuitComponent(kind: .repeater, direction: .east)]))
        sim.toggleLever(at: rear)
        for _ in 0..<3 { _ = sim.advanceTick() }
        XCTAssertEqual(sim.power(at: repeater), .full)
    }

    func testDelayCodableValidationAndLegacyComponentDefault() throws {
        for delay in RepeaterDelay.allCases {
            let component = CircuitComponent(kind: .repeater, direction: .south, repeaterDelay: delay)
            XCTAssertEqual(try JSONDecoder().decode(CircuitComponent.self, from: JSONEncoder().encode(component)), component)
            XCTAssertEqual(delay.simulationTicks, delay.rawValue * 2)
        }
        let legacy = Data(#"{"kind":"repeater","direction":"east"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CircuitComponent.self, from: legacy).repeaterDelay, .one)
        for value in ["null", "0", "5", "-1", "1.5", "\"two\""] {
            let json = "{\"kind\":\"repeater\",\"direction\":\"east\",\"repeaterDelay\":\(value)}"
            XCTAssertThrowsError(try JSONDecoder().decode(CircuitComponent.self, from: Data(json.utf8)))
        }
    }
}
