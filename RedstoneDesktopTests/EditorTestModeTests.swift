import XCTest
@testable import RedstoneDesktop

final class EditorTestModeTests: XCTestCase {
    func testCopySimulatesInputsAndCountsOutputsWithoutChangingSource() {
        let circuit = DemoCircuit.makeWorld().circuit
        var test = EditorCircuitTest(worldID: UUID(), circuit: circuit, levers: [])
        XCTAssertTrue(test.click(DemoCircuit.button))
        test.advance()
        XCTAssertEqual(test.outputPulses[DemoCircuit.output], 1)
        XCTAssertGreaterThan(test.simulator.power(at: DemoCircuit.output), .off)
        XCTAssertEqual(test.source, circuit)
        for _ in 0..<25 { test.advance() }
        XCTAssertEqual(test.outputPulses[DemoCircuit.output], 1)
        XCTAssertEqual(test.simulator.power(at: DemoCircuit.button), .off)
        XCTAssertFalse(test.click(DemoCircuit.output))
    }
    @MainActor func testPlayPauseStepResetAndExitNeverTouchDesktopActionsOrSavedLevers() {
        let scheduler = ManualCircuitTickScheduler(), app = AppState(tickScheduler: ManualCircuitTickScheduler()), editor = EditorSession(testScheduler: scheduler)
        defer { editor.stopTesting(); app.shutdown() }
        let library = app.library, desktop = app.simulator
        editor.startTesting(app)
        XCTAssertNotNil(editor.circuitTest)
        scheduler.fire(); XCTAssertEqual(editor.circuitTest?.tick, 1)
        editor.toggleTestPlayback(app)
        XCTAssertFalse(editor.circuitTest!.isPlaying)
        let point = editor.mapper(size: editor.viewport)!.screenRect(forTile: DemoCircuit.lever)
        editor.click(at: CGPoint(x: point.midX, y: point.midY), size: editor.viewport, appState: app)
        editor.stepTest(app)
        XCTAssertEqual(editor.circuitTest?.tick, 2)
        XCTAssertEqual(editor.circuitTest?.simulator.power(at: DemoCircuit.lever), .full)
        XCTAssertEqual(app.library, library); XCTAssertEqual(app.simulator, desktop)
        XCTAssertNil(app.activationTask); XCTAssertFalse(app.finderDiagnostics.hasRead)
        editor.resetTest(app)
        XCTAssertEqual(editor.circuitTest?.tick, 0)
        XCTAssertTrue(editor.circuitTest!.simulator.activeLevers.isEmpty)
        XCTAssertFalse(editor.circuitTest!.isPlaying)
        editor.stopTesting(); XCTAssertNil(editor.circuitTest)
    }
    @MainActor func testWorldSwitchAndConfigurationChangeInvalidateTest() {
        let app = AppState(tickScheduler: ManualCircuitTickScheduler()), editor = EditorSession(testScheduler: ManualCircuitTickScheduler())
        defer { editor.stopTesting(); app.shutdown() }
        editor.startTesting(app)
        app.configureRepeater(at: DemoCircuit.repeater, direction: .west, delay: .two)
        editor.invalidateTestIfNeeded(app); XCTAssertNil(editor.circuitTest)
        editor.startTesting(app)
        app.createWorld(name: "Elsewhere", generation: WorldGenerationSettings(seed: 42))
        editor.syncSelectedWorld(app); XCTAssertNil(editor.circuitTest)
    }
}
