import AppKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class MultiProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] { calls += 1; return items }
}
@MainActor
private final class MultiFixture {
    var screens = [ScreenDescriptor(id: "primary", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 2),
                   ScreenDescriptor(id: "right", frame: CGRect(x: 640, y: 0, width: 640, height: 480), backingScale: 1)]
    let provider = MultiProvider(), events = FakeGlobalMouseEventMonitor(), scheduler = ManualCircuitTickScheduler()
    let opener = FixtureItemOpener(), center = NotificationCenter()
    func app() -> AppState {
        AppState(screenProviding: { [self] in screens.first }, clickEventMonitoring: events,
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: scheduler, itemOpener: opener, displayNotificationCenter: center,
            displaySettleDelay: .milliseconds(1), screensProviding: { [self] in screens },
            finderReferenceProviding: { [self] in screens.first })
    }
    func notify() { center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil) }
}
final class MultiDisplayTests: XCTestCase {
    func testUnionNegativeOriginsMixedScalesAndHoles() throws {
        let left = ScreenDescriptor(id: "left", frame: CGRect(x: -800, y: -200, width: 800, height: 600), backingScale: 1)
        let right = ScreenDescriptor(id: "right", frame: CGRect(x: 100, y: 0, width: 640, height: 480), backingScale: 2)
        let canvas = try DesktopCanvas(screens: [left, right])
        XCTAssertEqual(canvas.frame, CGRect(x: -800, y: -200, width: 1540, height: 680))
        XCTAssertEqual(canvas.screen(at: CGPoint(x: 0, y: 0)), nil)
        XCTAssertEqual(canvas.screen(at: CGPoint(x: -1, y: 0))?.id, "left")
        let mapper = try CoordinateMapper(canvasFrame: canvas.frame, camera: SavedArea.homeCamera)
        let point = WorldPoint(x: 15, y: 5)
        XCTAssertEqual(mapper.worldPoint(fromScreen: mapper.screenPoint(fromWorld: point)), point)
    }
    func testMirrorsDeduplicateAndInvalidGeometryRefuses() throws {
        let a = ScreenDescriptor(id: "a", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let mirror = ScreenDescriptor(id: "b", frame: a.frame, backingScale: 2)
        XCTAssertEqual(try DesktopCanvas(screens: [a, mirror]).screens, [a])
        XCTAssertThrowsError(try DesktopCanvas(screens: []))
        XCTAssertThrowsError(try DesktopCanvas(screens: [a, a]))
        XCTAssertThrowsError(try DesktopCanvas(screens: [ScreenDescriptor(id: "bad", frame: .zero, backingScale: 1)]))
    }
    @MainActor
    func testOnePointerSamplerSelectsPhysicalScreenAndSuppressesGaps() throws {
        let fixture = MultiFixture(), canvas = try DesktopCanvas(screens: fixture.screens)
        let mapper = try CoordinateMapper(canvasFrame: canvas.frame, camera: SavedArea.homeCamera)
        var position = CGPoint(x: 10, y: 10), snapshots: [PointerSnapshot] = []
        let monitor = PointerMonitor(screens: canvas.screens, mapper: mapper, mouseLocation: { position }, onChange: { snapshots.append($0) })
        monitor.start(); defer { monitor.stop() }
        position = CGPoint(x: 650, y: 10); monitor.sample()
        XCTAssertEqual(snapshots.last?.screenID, "right")
        XCTAssertEqual(snapshots.last?.tile, WorldCoordinate(x: 10, y: 0))
        position = CGPoint(x: 1280, y: 10); monitor.sample()
        XCTAssertNil(snapshots.last?.tile)
    }
    @MainActor
    func testOneClickRegistrationAndSharedBoundaryMapsOnce() throws {
        let fixture = MultiFixture(), canvas = try DesktopCanvas(screens: fixture.screens)
        let mapper = try CoordinateMapper(canvasFrame: canvas.frame, camera: SavedArea.homeCamera)
        var clicks: [DesktopClickSnapshot] = []
        let monitor = DesktopClickMonitor(screens: canvas.screens, mapper: mapper, eventMonitoring: fixture.events, onClick: { clicks.append($0) })
        XCTAssertTrue(monitor.start()); defer { monitor.stop() }
        fixture.events.callbacks[0](CGPoint(x: 640, y: 64))
        XCTAssertEqual(clicks.count, 1); XCTAssertEqual(clicks[0].tile, WorldCoordinate(x: 10, y: 1))
        XCTAssertEqual(fixture.events.callbacks.count, 1)
    }
    @MainActor
    func testEachPhysicalWindowHasSharedMapperAndOneSimulationTick() throws {
        let fixture = MultiFixture(), state = fixture.app(); defer { state.shutdown() }
        let library = state.library
        state.setDesktopRunning(true)
        XCTAssertEqual(state.desktopControllers.count, 2)
        XCTAssertEqual(fixture.events.callbacks.count, 1)
        for (index, controller) in state.desktopControllers.enumerated() {
            XCTAssertEqual(controller.window?.frame, fixture.screens[index].frame)
            XCTAssertEqual(controller.scene.mapper.canvasFrame, CGRect(x: 0, y: 0, width: 1280, height: 480))
            XCTAssertTrue(controller.window!.ignoresMouseEvents)
            XCTAssertEqual(controller.scene.mapper.sceneRect(forTile: WorldCoordinate(x: 10, y: 0), on: fixture.screens[index]).minX, index == 0 ? 640 : 0)
        }
        fixture.scheduler.fire()
        XCTAssertEqual(state.simulationTick, 1)
        XCTAssertEqual(state.library, library)
        let windows = state.desktopControllers.compactMap(\.window)
        state.setDesktopRunning(false)
        XCTAssertTrue(state.desktopControllers.isEmpty)
        XCTAssertTrue(windows.allSatisfy { !$0.isVisible })
    }
    @MainActor
    func testSecondaryDisplayOccupancyProjectsAndHeldCircuitDoesNotReplayOnRebuild() async throws {
        let fixture = MultiFixture(), state = fixture.app(); defer { state.shutdown() }
        let output = WorldCoordinate(x: 11, y: 7)
        fixture.provider.items = [DesktopItem(id: "secondary", url: URL(fileURLWithPath: "/tmp/secondary"), displayName: "secondary",
            position: CGPoint(x: 736, y: 32), estimatedIconSize: nil, kind: .folder)]
        await state.finderDiagnostics.readItems(); state.setDesktopRunning(true)
        guard case let .occupied(item) = state.desktopOccupancy.state(at: output) else { return XCTFail("Secondary occupant missing") }
        XCTAssertEqual(item.id, "secondary")
        state.setEditorFinderItemsVisible(true)
        XCTAssertEqual(state.editorFinderProjection(camera: SavedArea.homeCamera).markers.first?.tile, output)
        XCTAssertEqual(fixture.provider.calls, 1)
        fixture.screens.removeLast(); fixture.notify(); await state.displayRefreshTask?.value
        XCTAssertTrue(fixture.opener.urls.isEmpty)
    }
    @MainActor
    func testSecondaryInputAndOutputOpenFreshOccupantAndOffscreenEdgesAreDropped() async throws {
        let fixture = MultiFixture()
        fixture.screens = fixture.screens.map { ScreenDescriptor(id: $0.id,
            frame: CGRect(x: $0.frame.minX, y: 0, width: 640, height: 800), backingScale: $0.backingScale) }
        let state = fixture.app(); defer { state.shutdown() }
        let button = WorldCoordinate(x: 10, y: 7), output = WorldCoordinate(x: 13, y: 7)
        XCTAssertTrue(state.placeCircuitComponent(CircuitComponent(kind: .button), at: button).isAllowed)
        for x in 11...12 { XCTAssertTrue(state.placeCircuitComponent(CircuitComponent(kind: .dust), at: WorldCoordinate(x: x, y: 7)).isAllowed) }
        XCTAssertTrue(state.placeCircuitComponent(CircuitComponent(kind: .output), at: output).isAllowed)
        fixture.provider.items = [DesktopItem(id: "secondary", url: URL(fileURLWithPath: "/tmp/secondary"), displayName: "secondary",
            position: CGPoint(x: 864, y: 320), estimatedIconSize: nil, kind: .folder)]
        await state.finderDiagnostics.readItems(); state.setDesktopRunning(true)
        fixture.events.callbacks[0](CGPoint(x: 672, y: 480))
        XCTAssertEqual(state.lastClick?.tile, button)
        await state.activationTask?.value
        fixture.scheduler.fire(); await state.activationTask?.value
        XCTAssertEqual(fixture.opener.urls, [URL(fileURLWithPath: "/tmp/secondary")])
        for _ in 0..<10 { fixture.scheduler.fire() }
        XCTAssertEqual(fixture.opener.urls.count, 1)
        let simulator = state.simulator
        fixture.screens.removeLast(); fixture.notify(); await state.displayRefreshTask?.value
        XCTAssertEqual(state.simulator, simulator)
        XCTAssertEqual(fixture.opener.urls.count, 1)
    }

    @MainActor
    func testSecondaryArrangementChangesRebuildWithoutResetAndNoDisplayRequiresStart() async throws {
        let fixture = MultiFixture(), state = fixture.app(); defer { state.shutdown() }
        state.setDesktopRunning(true); fixture.scheduler.fire()
        let simulator = state.simulator, library = state.library, old = state.desktopControllers
        fixture.screens[1] = ScreenDescriptor(id: "right", frame: CGRect(x: -640, y: -100, width: 640, height: 480), backingScale: 2)
        fixture.notify()
        XCTAssertEqual(state.simulator, simulator); XCTAssertEqual(state.library, library)
        XCTAssertEqual(state.desktopControllers.count, 2)
        XCTAssertTrue(old.allSatisfy { !$0.window!.isVisible })
        await state.displayRefreshTask?.value
        fixture.screens = []; fixture.notify()
        XCTAssertFalse(state.isDesktopWorldEnabled); XCTAssertTrue(state.desktopControllers.isEmpty)
        await state.displayRefreshTask?.value
        fixture.screens = [ScreenDescriptor(id: "back", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)]
        fixture.notify(); await state.displayRefreshTask?.value
        XCTAssertFalse(state.isDesktopWorldEnabled)
        state.setDesktopRunning(true); XCTAssertTrue(state.isDesktopWorldEnabled)
    }
    func testOccupancyUsesPhysicalDisplaysNotBoundingBoxGaps() throws {
        let a = ScreenDescriptor(id: "a", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let b = ScreenDescriptor(id: "b", frame: CGRect(x: 800, y: 0, width: 640, height: 480), backingScale: 2)
        let canvas = try DesktopCanvas(screens: [a, b]), mapper = try CoordinateMapper(canvasFrame: canvas.frame, camera: SavedArea.homeCamera)
        func item(_ x: CGFloat) -> DesktopItem { DesktopItem(id: String(describing: x), url: URL(fileURLWithPath: "/tmp/test"), displayName: "test", position: CGPoint(x: x, y: 64), estimatedIconSize: nil, kind: .folder) }
        let result = DesktopOccupancyResolver().resolve(items: [item(100), item(700), item(900)], mapper: mapper, finderReference: a, activeScreens: canvas.screens)
        guard case let .available(tiles) = result else { return XCTFail("Unavailable") }
        XCTAssertEqual(tiles.count, 2)
        XCTAssertNil(tiles[WorldCoordinate(x: 10, y: 6)])
    }
}
