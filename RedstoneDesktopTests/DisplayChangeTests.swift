import AppKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class DisplayProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var calls = 0
    var denied = false
    var holdNext = false
    var continuation: CheckedContinuation<[DesktopItem], Error>?
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if denied { throw FinderReadError.permissionDenied }
        if holdNext {
            holdNext = false
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return items
    }
}

@MainActor
private final class DisplayFixture {
    var screen: ScreenDescriptor? = ScreenDescriptor(id: "primary", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
    var reference: ScreenDescriptor? { screen }
    let center = NotificationCenter()
    let events = FakeGlobalMouseEventMonitor()
    let scheduler = ManualCircuitTickScheduler()
    let provider = DisplayProvider()
    let opener = FixtureItemOpener()
    func makeState() -> AppState {
        AppState(screenProviding: { [self] in screen }, clickEventMonitoring: events,
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fake desktop") },
            tickScheduler: scheduler, itemOpener: opener, displayNotificationCenter: center,
            displaySettleDelay: .milliseconds(20), finderReferenceProviding: { [self] in reference })
    }
    func notify() { center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil) }
    func resize(id: String = "primary", x: CGFloat = -640, y: CGFloat = -100, width: CGFloat = 800, height: CGFloat = 600, scale: Double = 2) {
        screen = ScreenDescriptor(id: id, frame: CGRect(x: x, y: y, width: width, height: height), backingScale: scale)
        notify()
    }
    func item(_ name: String = "folder") -> DesktopItem {
        DesktopItem(id: name, url: URL(fileURLWithPath: "/tmp/\(name)"), displayName: name,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .folder)
    }
}

final class DisplayChangeTests: XCTestCase {
    @MainActor
    func testPublicNotificationAdapterDuplicateStartStopAndRestart() {
        let center = NotificationCenter()
        var changes = 0
        let monitor = DisplayChangeMonitor(center: center) { changes += 1 }
        monitor.start(); monitor.start()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(changes, 1)
        monitor.stop()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(changes, 1)
        monitor.start()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(changes, 2)
        monitor.stop()
    }

    @MainActor
    func testResizeRecreatesRendererInputAndFinderMappingPreservingCameraCircuitAndPulse() async throws {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        fixture.scheduler.fire()
        await state.activationTask?.value
        let simulator = state.simulator, camera = state.desktopCamera, library = state.library
        let oldController = try XCTUnwrap(state.desktopController)
        let oldEvents = fixture.events.callbacks[0]
        fixture.provider.items = [fixture.item()]
        fixture.resize()
        let current = try XCTUnwrap(state.desktopController)
        XCTAssertFalse(current === oldController)
        XCTAssertFalse(oldController.window!.isVisible)
        XCTAssertEqual(current.window?.frame, fixture.screen?.frame)
        XCTAssertEqual(current.scene.size, fixture.screen?.frame.size)
        XCTAssertEqual(current.scene.mapper.canvasFrame, fixture.screen?.frame)
        XCTAssertEqual(current.scene.screen.backingScale, 2)
        XCTAssertTrue(current.window!.ignoresMouseEvents)
        XCTAssertFalse(current.window!.canBecomeKey)
        XCTAssertEqual(state.desktopCamera, camera)
        XCTAssertEqual(state.library, library)
        XCTAssertEqual(state.simulator, simulator)
        XCTAssertTrue(state.isDisplaySettling)
        XCTAssertFalse(state.finderDiagnostics.hasRead)
        let count = state.observedClickCount
        oldEvents(CGPoint(x: 160, y: 224))
        XCTAssertEqual(state.observedClickCount, count)
        fixture.events.callbacks.last?(CGPoint(x: -416, y: 124))
        XCTAssertEqual(state.lastClick?.tile, WorldCoordinate(x: 3, y: 3))
        await state.displayRefreshTask?.value
        XCTAssertFalse(state.isDisplaySettling)
        XCTAssertEqual(state.finderMappings.first?.screenCenter, CGPoint(x: -160, y: 244))
        XCTAssertEqual(state.finderMappings.first?.tile, WorldCoordinate(x: 7, y: 5))
        XCTAssertEqual(state.desktopOccupancy.state(at: WorldCoordinate(x: 7, y: 5)), .occupied(fixture.item()))
        XCTAssertTrue(fixture.opener.urls.isEmpty, "Resize does not replay a powered Output")
        fixture.scheduler.fire()
        XCTAssertTrue(state.isDesktopWorldEnabled)
        XCTAssertFalse(state.simulator.poweredTiles.isEmpty, "A running pulse continues after the scheduler is rebound")
    }

    @MainActor
    func testIdenticalGeometryNotificationsAreNoOpIncludingFirstNotification() async throws {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        state.toggleDesktopWorld()
        let controller = try XCTUnwrap(state.desktopController)
        fixture.notify(); fixture.notify()
        XCTAssertTrue(state.desktopController === controller)
        XCTAssertNil(state.displayRefreshTask)
        XCTAssertEqual(fixture.events.callbacks.count, 1)
        XCTAssertEqual(fixture.provider.calls, 0)
    }

    @MainActor
    func testBurstCoalescesFreshReadAndBackingOnlyChangeRebuildsWithoutRescalingCamera() async {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        let camera = state.desktopCamera
        fixture.resize(scale: 1)
        let firstTask = state.displayRefreshTask
        fixture.resize(width: 960, scale: 2)
        fixture.resize(width: 1000, scale: 1)
        await firstTask?.value
        await state.displayRefreshTask?.value
        XCTAssertEqual(fixture.provider.calls, 2, "One original read and one settled read")
        XCTAssertEqual(state.desktopCamera, camera)
        XCTAssertEqual(state.desktopController?.scene.screen, fixture.screen)
        let before = state.desktopController
        fixture.resize(width: 1000, scale: 2)
        XCTAssertFalse(state.desktopController === before)
        await state.displayRefreshTask?.value
        XCTAssertEqual(state.desktopCamera, camera)
        XCTAssertTrue(fixture.opener.urls.isEmpty)
    }

    @MainActor
    func testMissingOrInvalidDisplayStopsSafelyAndReturningDisplayRequiresExplicitStart() async {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        state.toggleDesktopWorld()
        let camera = state.desktopCamera, library = state.library
        fixture.screen = nil; fixture.notify()
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertNil(state.desktopController)
        XCTAssertNil(state.desktopScreen)
        XCTAssertNil(fixture.scheduler.callback)
        await state.displayRefreshTask?.value
        fixture.resize(id: "replacement")
        await state.displayRefreshTask?.value
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertEqual(state.desktopCamera, camera)
        XCTAssertEqual(state.library, library)
        XCTAssertEqual(fixture.provider.calls, 0)
        state.toggleDesktopWorld()
        XCTAssertTrue(state.isDesktopWorldEnabled)
        fixture.resize(width: 0)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertNil(state.desktopController)
        await state.displayRefreshTask?.value
    }

    @MainActor
    func testStoppedStartupChangeDoesNotReadFinderButOptedInEditorRefreshesNewGeometry() async throws {
        let fixture = DisplayFixture(), state = fixture.makeState(), editor = EditorSession()
        defer { state.shutdown() }
        fixture.resize()
        await state.displayRefreshTask?.value
        XCTAssertEqual(fixture.provider.calls, 0)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        state.setEditorFinderItemsVisible(true)
        for _ in 0..<1000 where !state.finderDiagnostics.hasRead { await Task.yield() }
        fixture.provider.items = [fixture.item()]
        fixture.resize(width: 900, height: 700)
        XCTAssertTrue(editor.finderProjection(state).markers.isEmpty)
        await state.displayRefreshTask?.value
        let projection = editor.finderProjection(state)
        XCTAssertEqual(projection.markers.first?.tile, WorldCoordinate(x: 7, y: 6))
        XCTAssertTrue(state.desktopItemTracker.isPolling)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertTrue(fixture.opener.urls.isEmpty)
    }

    @MainActor
    func testInFlightInputCannotActivateAfterDisplayChangeAndOldFinderResultIsDiscarded() async throws {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        fixture.provider.holdNext = true
        state.handleCircuitClick(DemoCircuit.button)
        for _ in 0..<1000 where fixture.provider.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(fixture.provider.continuation)
        let old = state.activationTask
        fixture.resize()
        XCTAssertNil(state.activationTask)
        state.handleCircuitClick(DemoCircuit.button)
        XCTAssertNil(state.activationTask, "Input waits for settled positions")
        continuation.resume(returning: [fixture.item("stale")])
        await old?.value
        XCTAssertTrue(state.finderDiagnostics.items.isEmpty)
        XCTAssertFalse(state.finderDiagnostics.hasRead)
        await state.displayRefreshTask?.value
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(fixture.opener.urls.isEmpty)
        XCTAssertFalse(state.finderDiagnostics.items.contains { $0.id == "stale" })
    }

    @MainActor
    func testInFlightOutputCannotOpenOldOccupantOrReplayAfterResize() async throws {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        fixture.provider.holdNext = true
        fixture.scheduler.fire()
        for _ in 0..<1000 where fixture.provider.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(fixture.provider.continuation), oldTask = state.activationTask
        fixture.resize()
        continuation.resume(returning: [fixture.item("old-output")])
        await oldTask?.value
        await state.displayRefreshTask?.value
        fixture.scheduler.fire()
        await state.activationTask?.value
        XCTAssertTrue(fixture.opener.urls.isEmpty)
        XCTAssertGreaterThan(state.simulator.power(at: DemoCircuit.output), .off)
    }

    @MainActor
    func testStoppingDesktopDuringSettleRetainsOptedInEditorRefresh() async {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.setEditorFinderItemsVisible(true)
        state.toggleDesktopWorld()
        fixture.resize()
        state.toggleDesktopWorld()
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertTrue(state.isDisplaySettling)
        XCTAssertFalse(state.desktopItemTracker.isPolling, "Polls wait for the settle delay")
        await state.displayRefreshTask?.value
        XCTAssertFalse(state.isDisplaySettling)
        XCTAssertTrue(state.desktopItemTracker.isPolling)
    }

    @MainActor
    func testGenerationInvalidationAlsoRejectsNoncancelableDiagnosticRead() async throws {
        let fixture = DisplayFixture(), model = FinderDiagnosticsModel(provider: fixture.provider)
        fixture.provider.holdNext = true
        let task = Task { await model.readItems() }
        for _ in 0..<1000 where fixture.provider.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(fixture.provider.continuation)
        model.invalidateDisplayPositions()
        continuation.resume(returning: [fixture.item("old-layout")])
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.hasRead)
        XCTAssertFalse(model.isReading)
        await model.readItems()
        XCTAssertTrue(model.hasRead)
    }

    @MainActor
    func testDeniedAccessRemainsVisibleAndResizeDoesNotRepeatPermissionRequests() async {
        let fixture = DisplayFixture(), state = fixture.makeState()
        defer { state.shutdown() }
        fixture.provider.denied = true
        await state.finderDiagnostics.readItems()
        let error = state.finderDiagnostics.error
        state.setEditorFinderItemsVisible(true)
        state.toggleDesktopWorld()
        fixture.resize()
        await state.displayRefreshTask?.value
        XCTAssertEqual(state.finderDiagnostics.permission, .denied)
        XCTAssertEqual(state.finderDiagnostics.error, error)
        XCTAssertNotNil(error)
        XCTAssertEqual(fixture.provider.calls, 1)
        XCTAssertFalse(state.desktopItemTracker.isPolling)
        XCTAssertFalse(state.isDisplaySettling)
    }

    @MainActor
    func testFullShutdownCancelsDelayedRefreshAndStopsNotificationObservation() async {
        let fixture = DisplayFixture(), state = fixture.makeState()
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        fixture.resize()
        let task = state.displayRefreshTask
        state.shutdown()
        await task?.value
        fixture.resize(width: 960)
        XCTAssertNil(state.displayRefreshTask)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertEqual(fixture.provider.calls, 1)
    }
}
