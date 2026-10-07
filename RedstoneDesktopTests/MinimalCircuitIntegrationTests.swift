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
    private func item(_ id: String, tileX: Int = 7) -> DesktopItem {
        DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), displayName: id, position: CGPoint(x: tileX * 64 + 32, y: 480 - (3 * 64 + 32)), estimatedIconSize: nil, kind: .folder)
    }
    @MainActor
    private func makeState(_ provider: CircuitFixtureProvider, _ opener: FixtureItemOpener, allowed: @escaping () -> Bool = { true }, events: FakeGlobalMouseEventMonitor = FakeGlobalMouseEventMonitor()) -> AppState {
        AppState(screenProviding: { self.screen }, clickEventMonitoring: events,
                 finderDiagnostics: FinderDiagnosticsModel(provider: provider), desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: allowed() ? nil : "Fixture desktop check rejected the click.", details: "Fixture recipient details") },
                 itemOpener: opener, finderReferenceProviding: { self.screen })
    }
    @MainActor
    private func press(_ state: AppState) async {
        state.handleCircuitClick(FixedTestCircuit.button)
        await state.activationTask?.value
    }
    @MainActor
    private func release(_ state: AppState) {
        for _ in 0..<20 { state.advanceCircuitTick() }
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
        let rect = mapper.screenRect(forTile: FixedTestCircuit.button)
        events.callbacks[0](CGPoint(x: rect.midX, y: rect.midY))
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [item("new").url], "Must use the click-time read, not the cached item")
        XCTAssertTrue(state.testCircuit.isPowered)
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
        XCTAssertFalse(state.testCircuit.isPowered)
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
            XCTAssertFalse(state.testCircuit.isPowered)
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
        state.handleCircuitClick(FixedTestCircuit.button)
        let pending = state.activationTask
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(result, .completed)
        for _ in 0..<10 { state.handleCircuitClick(FixedTestCircuit.button) }
        XCTAssertEqual(provider.calls, 2)
        state.shutdown()
        state.toggleDesktopWorld()
        state.handleCircuitClick(FixedTestCircuit.button)
        XCTAssertEqual(provider.calls, 2)
        continuation?.resume(returning: [item("late")])
        await pending?.value
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertFalse(state.testCircuit.isPowered)
        XCTAssertTrue(state.finderDiagnostics.items.isEmpty)
    }

    @MainActor
    func testCircuitVisualsUseMapperAndRemainBounded() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let layer = try XCTUnwrap(scene.childNode(withName: "test-circuit"))
        var circuit = FixedTestCircuit()
        scene.updateTestCircuit(circuit)
        let path = try XCTUnwrap(layer.childNode(withName: "dust-path") as? SKShapeNode)
        let offColor = path.strokeColor
        let button = try XCTUnwrap(layer.childNode(withName: "PRESS") as? SKShapeNode)
        XCTAssertEqual(button.path?.boundingBoxOfPath, mapper.sceneRect(forTile: FixedTestCircuit.button, on: screen).insetBy(dx: 8, dy: 8))
        _ = circuit.press(at: FixedTestCircuit.button)
        scene.updateTestCircuit(circuit)
        XCTAssertNotEqual((layer.childNode(withName: "dust-path") as? SKShapeNode)?.strokeColor, offColor)
        for _ in 0..<10 { scene.updateTestCircuit(circuit); scene.flashOutput() }
        XCTAssertEqual(layer.children.count, 5)
        XCTAssertEqual(scene.children.count, 8)
        let flash = try XCTUnwrap(scene.childNode(withName: "output-flash") as? SKShapeNode)
        XCTAssertFalse(flash.isHidden)
        XCTAssertEqual(flash.path?.boundingBoxOfPath, mapper.sceneRect(forTile: FixedTestCircuit.output, on: screen).insetBy(dx: 3, dy: 3))
    }
}
