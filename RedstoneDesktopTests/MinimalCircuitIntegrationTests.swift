import AppKit
import Combine
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class CircuitFixtureProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var error: FinderReadError?
    var operation: (@MainActor () async throws -> [DesktopItem])?
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if let operation { return try await operation() }
        if let error { throw error }
        return items
    }
}

final class MinimalCircuitIntegrationTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: -100, y: -100, width: 640, height: 480), backingScale: 2)
    private func item(_ id: String, tileX: Int = 7, tileY: Int = 3) -> DesktopItem {
        DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), displayName: id, position: CGPoint(x: tileX * 64 + 32, y: 480 - (tileY * 64 + 32)), estimatedIconSize: nil, kind: .folder)
    }
    @MainActor
    private func makeState(_ provider: CircuitFixtureProvider, _ opener: FixtureItemOpener, allowed: @escaping () -> Bool = { true }, events: FakeGlobalMouseEventMonitor = FakeGlobalMouseEventMonitor()) -> AppState {
        AppState(screenProviding: { self.screen }, clickEventMonitoring: events,
                 finderDiagnostics: FinderDiagnosticsModel(provider: provider), desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: allowed() ? nil : "Fixture desktop check rejected the click.", details: "Fixture recipient details") },
                 tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, finderReferenceProviding: { self.screen })
    }
    @MainActor
    private func press(_ state: AppState) async {
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
    }
    @MainActor
    private func release(_ state: AppState) {
        for _ in 0..<20 { state.advanceCircuitTick() }
    }

    @MainActor
    private func outputChainState(_ provider: CircuitFixtureProvider, _ opener: FixtureItemOpener, width: CGFloat = 1600) throws -> AppState {
        let screen = ScreenDescriptor(id: "chain", frame: CGRect(x: 0, y: 0, width: width, height: 900), backingScale: 1)
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, finderReferenceProviding: { screen })
        for (x, kind) in [(10, CircuitComponentKind.button), (11, .dust), (12, .dust), (13, .output), (14, .repeater), (15, .output)] {
            XCTAssertEqual(state.placeCircuitComponent(CircuitComponent(kind: kind, direction: .east), at: WorldCoordinate(x: x, y: 9)), .allowed)
        }
        return state
    }

    private func chainItem(_ id: String, x: Int) -> DesktopItem {
        DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), displayName: id,
            position: CGPoint(x: x * 64 + 32, y: 900 - (9 * 64 + 32)), estimatedIconSize: nil, kind: .folder)
    }

    @MainActor
    func testChainedOutputUsesFreshTargetDespiteEmptyAmbiguousOrDisabledFirstAction() async throws {
        let button = WorldCoordinate(x: 10, y: 9), a = WorldCoordinate(x: 13, y: 9), b = WorldCoordinate(x: 15, y: 9)
        for first in ["empty", "ambiguous", "disabled", "invalidScript", "occupied"] {
            let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
            let state = try outputChainState(provider, opener)
            defer { state.shutdown() }
            var firstItems: [DesktopItem] = []
            if first == "ambiguous" { firstItems = [chainItem("a1", x: 13), chainItem("a2", x: 13)] }
            if ["occupied", "disabled", "invalidScript"].contains(first) { firstItems = [chainItem("a1", x: 13)] }
            if first == "disabled" { XCTAssertTrue(state.configureOutput(at: a, mode: .none)) }
            if first == "invalidScript" { XCTAssertTrue(state.configureOutput(at: a, mode: .executeOccupant)) }
            provider.items = firstItems + [chainItem("old-b", x: 15)]
            await state.finderDiagnostics.readItems()
            state.toggleDesktopWorld()
            state.handleCircuitClick(button)
            await state.activationTask?.value
            state.advanceCircuitTick()
            await state.activationTask?.value
            XCTAssertEqual(state.simulator.power(at: a), PowerLevel(14))
            provider.items = firstItems + [chainItem("current-b", x: 15)]
            for _ in 0..<2 { state.advanceCircuitTick(); await state.activationTask?.value }
            XCTAssertEqual(state.simulator.power(at: b), .full)
            let expected = (first == "occupied" ? [chainItem("a1", x: 13).url] : []) + [chainItem("current-b", x: 15).url]
            XCTAssertEqual(opener.urls, expected)
            // Refresh/movement and renderer appearance updates must not replay either edge.
            provider.items = firstItems + [chainItem("later-b", x: 15)]
            await state.finderDiagnostics.readItems()
            state.desktopController?.scene.updateWorld(state.desktopWorld, poweredTiles: state.simulator.poweredTiles)
            for _ in 0..<30 { state.advanceCircuitTick(); await state.activationTask?.value }
            XCTAssertEqual(opener.urls, expected)
            XCTAssertTrue(state.simulator.power.isEmpty)
            state.handleCircuitClick(button)
            await state.activationTask?.value
            for _ in 0..<3 { state.advanceCircuitTick(); await state.activationTask?.value }
            XCTAssertEqual(opener.urls.last, chainItem("later-b", x: 15).url)
        }
    }

    @MainActor
    func testOffscreenChainedOutputGetsPowerWithoutLaunchingItsOccupant() async throws {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = try outputChainState(provider, opener, width: 960)
        defer { state.shutdown() }
        provider.items = [chainItem("a", x: 13), chainItem("offscreen-b", x: 15)]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(WorldCoordinate(x: 10, y: 9))
        await state.activationTask?.value
        for _ in 0..<3 { state.advanceCircuitTick(); await state.activationTask?.value }
        XCTAssertEqual(state.simulator.power(at: WorldCoordinate(x: 15, y: 9)), .full)
        XCTAssertEqual(opener.urls, [chainItem("a", x: 13).url])
    }

    @MainActor
    func testStopDuringFirstOutputReadDropsQueuedDownstreamAction() async throws {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = try outputChainState(provider, opener)
        defer { state.shutdown() }
        provider.items = [chainItem("a", x: 13), chainItem("b", x: 15)]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(WorldCoordinate(x: 10, y: 9))
        await state.activationTask?.value
        let started = expectation(description: "First Output read suspended")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = { try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() } }
        state.advanceCircuitTick()
        let pending = state.activationTask
        await fulfillment(of: [started], timeout: 2)
        state.advanceCircuitTick(); state.advanceCircuitTick()
        XCTAssertEqual(state.simulator.power(at: WorldCoordinate(x: 15, y: 9)), .full)
        state.shutdown()
        provider.operation = nil
        continuation?.resume(returning: provider.items)
        await pending?.value
        state.toggleDesktopWorld()
        for _ in 0..<10 { state.advanceCircuitTick(); await state.activationTask?.value }
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(state.simulator.power.isEmpty)
    }

    @MainActor
    func testGlobalClickRefreshesTargetAndHoldingDoesNotOpenAgain() async throws {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener(), events = FakeGlobalMouseEventMonitor()
        let state = makeState(provider, opener, events: events)
        defer { state.shutdown() }
        provider.items = [item("old")]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        provider.items = [item("new")]
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: state.desktopCamera)
        let rect = mapper.screenRect(forTile: DemoCircuit.button)
        events.callbacks[0](CGPoint(x: rect.midX, y: rect.midY))
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [item("new").url], "Must use the click-time read, not the cached item")
        XCTAssertFalse(state.simulator.poweredTiles.isEmpty)
        await press(state)
        XCTAssertEqual(opener.urls.count, 1)
        release(state)
        provider.items = []
        await press(state)
        XCTAssertEqual(opener.urls.count, 1)
        XCTAssertTrue(state.lastActionResult.contains("empty"))
        release(state)
        provider.items = [item("replacement")]
        await press(state)
        XCTAssertEqual(opener.urls.last, item("replacement").url)
    }

    @MainActor
    func testAmbiguousUnavailableAndFailedRefreshNeverOpen() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        state.toggleDesktopWorld()
        await press(state)
        XCTAssertEqual(provider.calls, 0, "Do not request Finder without the initial explicit read")
        provider.items = [item("one"), item("two")]
        await state.finderDiagnostics.readItems()
        await press(state)
        XCTAssertTrue(state.lastActionResult.contains("ambiguous"))
        XCTAssertTrue(opener.urls.isEmpty)
        release(state)
        provider.error = .permissionDenied
        await press(state)
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(state.lastActionResult.contains("could not be refreshed"))
    }

    @MainActor
    func testFinderPriorityAndOtherApplicationClicksAreIgnored() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        var allowed = false
        let state = makeState(provider, opener, allowed: { allowed })
        defer { state.shutdown() }
        provider.items = [item("target")]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        await press(state)
        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(state.observedPressCount, 1)
        XCTAssertEqual(state.lastPressMetadata, "Fixture recipient details")
        XCTAssertTrue(state.lastActionResult.contains("PRESS click received"))
        XCTAssertTrue(state.lastActionResult.contains("Fixture desktop check rejected"))
        allowed = true
        for x in [2, 3] {
            provider.items = [item("target"), item("overlap", tileX: x)]
            await press(state)
            XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
            XCTAssertTrue(state.lastActionResult.contains("on or near PRESS"))
        }
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testBusyRequestsDoNotPileUpAndDisableInvalidatesLateReply() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        let started = expectation(description: "Finder read suspended")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        state.handleCircuitClick(DemoCircuit.button)
        let pending = state.activationTask
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(result, .completed)
        for _ in 0..<10 { state.handleCircuitClick(DemoCircuit.button) }
        XCTAssertEqual(provider.calls, 2)
        state.shutdown()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        XCTAssertEqual(provider.calls, 2)
        continuation?.resume(returning: [item("late")])
        await pending?.value
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(state.finderDiagnostics.items.isEmpty)
    }

    @MainActor
    func testClickDuringBackgroundReadWaitsAndUsesReplacementWithoutRetry() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        provider.items = [item("old")]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        let started = expectation(description: "Background Finder read started")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        let background = Task { await state.finderDiagnostics.readItems() }
        await fulfillment(of: [started], timeout: 2)
        state.handleCircuitClick(DemoCircuit.button)
        let input = state.activationTask
        XCTAssertNotNil(input, "A valid click must reserve input even while Finder is reading")
        XCTAssertTrue(state.lastActionResult.contains("waiting for Finder"))
        for _ in 0..<10 { state.handleCircuitClick(DemoCircuit.button) }
        XCTAssertEqual(provider.calls, 2, "Repeated clicks must not create overlapping reads")
        provider.operation = nil
        provider.items = [item("replacement")]
        continuation?.resume(returning: [item("old")])
        _ = await background.value
        await input?.value
        XCTAssertEqual(provider.calls, 3, "Input must perform its own fresh check")
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [item("replacement").url])
        release(state)
        XCTAssertEqual(opener.urls.count, 1, "Repeated busy clicks must not replay later")
    }

    @MainActor
    func testDisableCancelsInputWaitingForBackgroundRead() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        let started = expectation(description: "Background Finder read started")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        let background = Task { await state.finderDiagnostics.readItems() }
        await fulfillment(of: [started], timeout: 2)
        state.handleCircuitClick(DemoCircuit.button)
        let input = state.activationTask
        state.shutdown()
        provider.operation = nil
        continuation?.resume(returning: [item("late")])
        _ = await background.value
        await input?.value
        XCTAssertEqual(provider.calls, 2)
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testInputDuringOutputRefreshIsBoundedAndRunsAfterRead() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        let started = expectation(description: "Output Finder read started")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        state.advanceCircuitTick()
        let output = state.activationTask
        await fulfillment(of: [started], timeout: 2)
        for _ in 0..<10 { state.handleCircuitClick(DemoCircuit.lever) }
        XCTAssertTrue(state.lastActionResult.contains("queued"))
        provider.operation = nil
        continuation?.resume(returning: [])
        await output?.value
        state.handleCircuitClick(DemoCircuit.lever) // Coalesce even in the gap before the next tick.
        XCTAssertNil(state.activationTask)
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertTrue(state.simulator.activeLevers.contains(DemoCircuit.lever))
        for _ in 0..<20 { state.advanceCircuitTick() }
        await state.activationTask?.value
        XCTAssertTrue(state.simulator.activeLevers.contains(DemoCircuit.lever), "Queued repeats must not toggle back off")
    }

    @MainActor
    func testLeverHeldPowerOpensOnceAndNewRisingEdgeUsesReplacement() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        provider.items = [item("lever-target", tileY: 5)]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.lever)
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [item("lever-target", tileY: 5).url])
        for _ in 0..<100 { state.advanceCircuitTick() }
        XCTAssertEqual(opener.urls.count, 1)
        XCTAssertEqual(state.simulator.power(at: DemoCircuit.leverOutput), PowerLevel(12))
        provider.items = [item("replacement", tileY: 5)]
        state.handleCircuitClick(DemoCircuit.lever)
        await state.activationTask?.value
        state.advanceCircuitTick()
        XCTAssertEqual(state.simulator.power(at: DemoCircuit.leverOutput), .off)
        state.handleCircuitClick(DemoCircuit.lever)
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls.last, item("replacement", tileY: 5).url)
        state.shutdown()
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(state.simulator.activeLevers.isEmpty)
    }

    @MainActor
    func testRisingOutputWaitsForBusyFinderAndRefreshesCurrentTarget() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        provider.items = [item("old")]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        let started = expectation(description: "Background read busy")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        let backgroundRead = Task { await state.finderDiagnostics.readItems() }
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(result, .completed)
        let calls = provider.calls
        state.advanceCircuitTick() // emits activation, but must not overlap the read
        XCTAssertEqual(provider.calls, calls)
        XCTAssertTrue(opener.urls.isEmpty)
        provider.operation = nil
        provider.items = [item("current")]
        continuation?.resume(returning: [item("old")])
        _ = await backgroundRead.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [item("current").url])
        XCTAssertEqual(provider.calls, calls + 1)
    }

    @MainActor
    func testDisablingDuringOutputRefreshSuppressesLateOpen() async {
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        let state = makeState(provider, opener)
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        let started = expectation(description: "Output refresh suspended")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }
        state.advanceCircuitTick()
        let pending = state.activationTask
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(result, .completed)
        state.shutdown()
        state.toggleDesktopWorld()
        continuation?.resume(returning: [item("late-output")])
        await pending?.value
        for _ in 0..<30 { state.advanceCircuitTick() }
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
    }

    @MainActor
    func testDelayedDemoOpensFreshOccupantOnlyAfterDelayAndDisableClearsHistory() async {
        let largeScreen = ScreenDescriptor(id: "large", frame: CGRect(x: 0, y: 0, width: 640, height: 640), backingScale: 1)
        let provider = CircuitFixtureProvider(), opener = FixtureItemOpener()
        func target(_ id: String) -> DesktopItem {
            DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), displayName: id,
                position: CGPoint(x: 480, y: 160), estimatedIconSize: nil, kind: .folder)
        }
        let state = AppState(screenProviding: { largeScreen },
            clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture desktop") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener,
            finderReferenceProviding: { largeScreen })
        defer { state.shutdown() }
        provider.items = [target("old-delayed")]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.repeaterButton)
        await state.activationTask?.value
        for _ in 0..<8 {
            state.advanceCircuitTick()
            XCTAssertEqual(state.simulator.power(at: DemoCircuit.repeaterOutput), .off)
            XCTAssertNil(state.activationTask)
        }
        provider.items = [target("fresh-delayed")]
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [target("fresh-delayed").url])
        XCTAssertEqual(state.simulator.power(at: DemoCircuit.repeaterOutput), .full)
        for _ in 0..<30 { state.advanceCircuitTick() }
        XCTAssertEqual(opener.urls.count, 1)
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
        state.handleCircuitClick(DemoCircuit.repeaterButton)
        await state.activationTask?.value
        state.advanceCircuitTick() // input history now contains a pending pulse
        state.shutdown()
        state.toggleDesktopWorld()
        for _ in 0..<30 { state.advanceCircuitTick() }
        XCTAssertEqual(opener.urls.count, 1)
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
    }

    @MainActor
    func testCircuitVisualsUseMapperAndRemainBounded() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        var circuit = CircuitSimulator(world: DemoCircuit.makeWorld().circuit)
        scene.updateWorld(DemoCircuit.makeWorld(), poweredTiles: circuit.poweredTiles)
        let path = try XCTUnwrap(layer.childNode(withName: "dust-path") as? SKShapeNode)
        let offColor = path.strokeColor
        let button = try XCTUnwrap(layer.childNode(withName: "PRESS") as? SKShapeNode)
        XCTAssertEqual(button.path?.boundingBoxOfPath, mapper.sceneRect(forTile: DemoCircuit.button, on: screen).insetBy(dx: 8, dy: 8))
        _ = circuit.pressButton(at: DemoCircuit.button)
        _ = circuit.advanceTick()
        scene.updateWorld(DemoCircuit.makeWorld(), poweredTiles: circuit.poweredTiles)
        XCTAssertNotEqual((layer.childNode(withName: "dust-path") as? SKShapeNode)?.strokeColor, offColor)
        for _ in 0..<10 { scene.updateWorld(DemoCircuit.makeWorld(), poweredTiles: circuit.poweredTiles); scene.flashOutput(at: DemoCircuit.output) }
        XCTAssertEqual(layer.children.count, 24)
        XCTAssertEqual(scene.children.count, 11)
        let flash = try XCTUnwrap(scene.childNode(withName: "output-flash")?.childNode(withName: "output-flash:\(DemoCircuit.output.x),\(DemoCircuit.output.y)") as? SKShapeNode)
        XCTAssertFalse(flash.isHidden)
        XCTAssertEqual(flash.path?.boundingBoxOfPath, mapper.sceneRect(forTile: DemoCircuit.output, on: screen).insetBy(dx: 3, dy: 3))
    }
}
