import XCTest
@testable import RedstoneDesktop

final class FixedTestCircuitTests: XCTestCase {
    func testOneSecondPulseAndExactlyOneRisingActivation() {
        var circuit = FixedTestCircuit()
        XCTAssertEqual(circuit.press(at: WorldCoordinate(x: 0, y: 0)), [])
        XCTAssertFalse(circuit.isPowered)
        XCTAssertEqual(circuit.press(at: FixedTestCircuit.button), [.outputActivated(FixedTestCircuit.output)])
        for _ in 0..<19 { circuit.advanceTick() }
        XCTAssertTrue(circuit.isPowered)
        circuit.advanceTick()
        XCTAssertFalse(circuit.isPowered)
        circuit.advanceTick()
        XCTAssertEqual(circuit.remainingTicks, 0)
        XCTAssertEqual(circuit.press(at: FixedTestCircuit.button), [.outputActivated(FixedTestCircuit.output)])
    }

    func testPressWhilePoweredRestartsWithoutReactivatingOutput() {
        var circuit = FixedTestCircuit()
        _ = circuit.press(at: FixedTestCircuit.button)
        for _ in 0..<10 { circuit.advanceTick() }
        XCTAssertEqual(circuit.press(at: FixedTestCircuit.button), [])
        XCTAssertEqual(circuit.remainingTicks, 20)
    }
}
