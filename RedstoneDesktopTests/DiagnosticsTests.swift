import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class DiagnosticsProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var calls = 0
    var operation: (@MainActor () async throws -> [DesktopItem])?
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if let operation { return try await operation() }
        return items
    }
}

final class DiagnosticsTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "diagnostics", frame: CGRect(x: -100, y: -200, width: 640, height: 480), backingScale: 2)
    @MainActor
    private func app(_ provider: DiagnosticsProvider, _ opener: FixtureItemOpener = FixtureItemOpener()) -> AppState {
        let screen = screen
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, finderReferenceProviding: { screen })
    }
    private func item(_ id: String) -> DesktopItem {
        DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), displayName: id,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .folder)
    }

    func testRateMeterMeasuresObservedCadenceRejectsInvalidTimesAndExpires() {
        var rate = DiagnosticRateMeter()
        XCTAssertNil(rate.recentRate(at: 0))
        for index in 0...20 { rate.record(at: Double(index) / 20) }
        XCTAssertEqual(rate.count, 21)
        XCTAssertEqual(rate.recentRate(at: 1), 20)
        rate.record(at: .nan); rate.record(at: .infinity); rate.record(at: 1); rate.record(at: 0)
        XCTAssertEqual(rate.count, 21)
        XCTAssertNil(rate.recentRate(at: 4))
        XCTAssertNil(rate.recentRate(at: -1))
        rate.record(at: 4)
        XCTAssertEqual(rate.recentRate(at: 4), 1.0 / 3.0)
        rate = DiagnosticRateMeter()
        XCTAssertNil(rate.recentRate(at: 4))
        XCTAssertEqual(rate.count, 0)
    }

    @MainActor
    func testDiagnosticViewsDoNotReadFinderRequestPermissionsAdvanceOrOpen() async throws {
        let provider = DiagnosticsProvider(), opener = FixtureItemOpener(), state = app(provider, opener)
        defer { state.shutdown() }
        let before = state.library
        let views: [NSView] = [NSHostingView(rootView: DesktopDetailsView(appState: state)), NSHostingView(rootView: FinderDiagnosticsView(appState: state))]
        for view in views { view.frame = CGRect(x: 0, y: 0, width: 1200, height: 740); view.layoutSubtreeIfNeeded() }
        await Task.yield()
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(state.finderDiagnostics.permission, .notRequested)
        XCTAssertNil(state.desktopScriptAccessTask)
        XCTAssertEqual(state.library, before)
        XCTAssertTrue(state.simulator.power.isEmpty)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertFalse(state.diagnosticOverlays.enabled)
        XCTAssertFalse(state.isSimulationPaused)
    }

    @MainActor
    func testCachedDiagnosticMappingWorksStoppedAndDoesNotMutateOrQuery() async throws {
        let provider = DiagnosticsProvider(), state = app(provider)
        defer { state.shutdown() }
        provider.items = [item("mapped")]
        await state.finderDiagnostics.readItems()
        let before = state.library
        XCTAssertFalse(state.isDesktopWorldEnabled)
        let mapping = try XCTUnwrap(state.diagnosticFinderMappings.first)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: state.desktopCamera)
        XCTAssertEqual(mapping, mapper.finderMapping(for: item("mapped"), referenceScreen: screen))
        XCTAssertEqual(mapping.tile, DemoCircuit.output)
        XCTAssertEqual(state.finderDiagnostics.readAttempts, 1)
        XCTAssertNotNil(state.finderDiagnostics.lastReadDuration)
        XCTAssertNotNil(state.finderDiagnostics.lastSuccessfulRead)
        _ = state.diagnosticFinderMappings
        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(state.library, before)
        XCTAssertTrue(state.finderMappings.isEmpty, "Runtime mapping remains separate from cached diagnostic projection")
    }

    @MainActor
    func testFailedFinderReadKeepsLastSuccessEvidenceWithoutClaimingNewSuccess() async {
        let provider = DiagnosticsProvider(), model = FinderDiagnosticsModel(provider: provider)
        XCTAssertNil(model.lastSuccessfulRead)
        provider.operation = { throw FinderReadError.permissionDenied }
        let failed = await model.readItems()
        XCTAssertFalse(failed)
        XCTAssertNil(model.lastSuccessfulRead)
        XCTAssertEqual(model.readAttempts, 1)
        provider.operation = nil
        let succeeded = await model.readItems()
        XCTAssertTrue(succeeded)
        let success = model.lastSuccessfulRead
        XCTAssertNotNil(success)
        provider.operation = { throw FinderReadError.permissionDenied }
        let denied = await model.readItems()
        XCTAssertFalse(denied)
        XCTAssertEqual(model.lastSuccessfulRead, success)
        XCTAssertEqual(model.permission, .denied)
        XCTAssertEqual(model.readAttempts, 3)
        XCTAssertNotNil(model.lastReadDuration)
    }

    @MainActor
    func testOverlaysAreExplicitBoundedMappedAndRemovedWithoutPowerMutation() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let world = DemoCircuit.makeWorld()
        scene.updateWorld(world, poweredTiles: [DemoCircuit.output])
        let mappings = (0..<1000).map { mapper.finderMapping(for: item("item-\($0)"), referenceScreen: screen) }
        scene.updateFinderMarkers(mappings)
        XCTAssertNil(scene.childNode(withName: "diagnostic-overlays"))
        scene.setDiagnosticOverlays(DiagnosticOverlaySettings(tileCoordinates: true, rawFinderPoints: true,
            mappedFinderCenters: true, outputOccupancy: true, chunkBoundaries: true))
        let layer = try XCTUnwrap(scene.childNode(withName: "diagnostic-overlays"))
        XCTAssertLessThanOrEqual(layer.children.count, 128 + 768 + 64 + 256)
        let ring = try XCTUnwrap(layer.children.compactMap { $0 as? SKShapeNode }.first { $0.name?.hasPrefix("diagnostic-center:") == true })
        XCTAssertEqual(ring.position, mapper.scenePoint(fromScreen: mappings[0].screenCenter, on: screen))
        XCTAssertTrue(layer.children.contains { ($0 as? SKLabelNode)?.text?.hasPrefix("raw ") == true })
        scene.setDiagnosticOverlays(DiagnosticOverlaySettings())
        XCTAssertNil(scene.childNode(withName: "diagnostic-overlays"))
        XCTAssertTrue(scene.childNode(withName: "finder-markers")!.children.isEmpty)
        XCTAssertEqual(scene.childNode(withName: "circuit")?.children.filter { $0.name == "OUTPUT" }.count, 3)
    }

    @MainActor
    func testPauseRetainsSignalRefusesInputAndDoesNotReplayHeldOutput() async {
        let provider = DiagnosticsProvider(), opener = FixtureItemOpener(), state = app(provider, opener)
        defer { state.shutdown() }
        provider.items = [item("target")]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls.count, 1)
        XCTAssertEqual(state.lastOutputActivation?.tile, DemoCircuit.output)
        XCTAssertEqual(state.lastOutputActivation?.power, PowerLevel(12))
        XCTAssertEqual(state.lastOutputActivation?.tick, 1)
        let signal = state.simulator
        state.setSimulationPaused(true)
        for _ in 0..<30 { state.advanceCircuitTick() }
        state.handleCircuitClick(DemoCircuit.lever)
        XCTAssertEqual(state.simulator, signal)
        XCTAssertEqual(state.simulationTick, 1)
        XCTAssertNil(state.activationTask)
        XCTAssertTrue(state.lastActionResult.contains("paused"))
        state.setSimulationPaused(false)
        state.advanceCircuitTick()
        XCTAssertEqual(state.simulationTick, 2)
        XCTAssertEqual(opener.urls.count, 1)
        state.shutdown()
        XCTAssertFalse(state.isSimulationPaused)
        XCTAssertTrue(state.simulator.power.isEmpty)
    }

    @MainActor
    func testPauseCancelsLateOutputReadAndNoResumeReplay() async {
        let provider = DiagnosticsProvider(), opener = FixtureItemOpener(), state = app(provider, opener)
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        let started = expectation(description: "Output refresh suspended")
        var reply: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = { try await withCheckedThrowingContinuation { reply = $0; started.fulfill() } }
        state.advanceCircuitTick()
        let pending = state.activationTask
        await fulfillment(of: [started], timeout: 2)
        state.setSimulationPaused(true)
        provider.operation = nil
        reply?.resume(returning: [item("late")])
        await pending?.value
        state.setSimulationPaused(false)
        for _ in 0..<30 { state.advanceCircuitTick(); await state.activationTask?.value }
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertNil(state.activationTask)
    }

    @MainActor
    func testPollingFreezePreservesExplicitFreshActionReadsAndNoAutomaticReadOnView() async {
        let provider = DiagnosticsProvider(), opener = FixtureItemOpener(), state = app(provider, opener)
        defer { state.shutdown() }
        provider.items = [item("old")]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.setFinderPollingFrozen(true)
        state.desktopItemTracker.start()
        state.desktopItemTracker.requestPoll()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(provider.calls, 1)
        provider.items = [item("new")]
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [item("new").url])
        XCTAssertEqual(provider.calls, 3)
        state.setFinderPollingFrozen(false)
        XCTAssertFalse(state.isFinderPollingFrozen)
    }

    @MainActor
    func testOverlayChangesKeepLibraryActionsAndSelectedDesktopIdentityIndependent() async throws {
        let provider = DiagnosticsProvider(), state = app(provider)
        defer { state.shutdown() }
        let activeWorld = state.activeWorldID, activeArea = state.library.activeAreaID
        XCTAssertTrue(state.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        XCTAssertNotEqual(state.selectedWorldID, activeWorld)
        let before = state.library
        state.setDiagnosticOverlays(DiagnosticOverlaySettings(tileCoordinates: true))
        XCTAssertEqual(state.activeWorldID, activeWorld)
        XCTAssertEqual(state.library.activeAreaID, activeArea)
        XCTAssertEqual(state.library, before)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertNil(state.lastOutputActivation)
        let editor = EditorSession(), renderer = EditorCanvasRenderer()
        let scene = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: CGSize(width: 640, height: 480)))
        XCTAssertTrue(state.editorDiagnosticScene === scene)
        XCTAssertNotNil(scene.childNode(withName: "diagnostic-overlays"))
        state.setDiagnosticOverlays(DiagnosticOverlaySettings())
        XCTAssertNil(scene.childNode(withName: "diagnostic-overlays"))
    }
}
