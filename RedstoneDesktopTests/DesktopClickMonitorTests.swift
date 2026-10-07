import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
final class FakeGlobalMouseEventMonitor: GlobalMouseEventMonitoring {
    var callbacks: [@MainActor (CGPoint) -> Void] = []
    var removedTokens: [UUID] = []
    var shouldFail = false

    func addLeftMouseDownMonitor(handler: @escaping @MainActor (CGPoint) -> Void) -> Any? {
        callbacks.append(handler)
        return shouldFail ? nil : UUID()
    }

    func removeMonitor(_ token: Any) {
        if let id = token as? UUID { removedTokens.append(id) }
    }
}

final class DesktopClickMonitorTests: XCTestCase {
    @MainActor
    func testDuplicateStartMappingAndStaleCallbacksAcrossRestart() throws {
        let screen = testScreen
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: camera)
        let events = FakeGlobalMouseEventMonitor()
        var clicks: [DesktopClickSnapshot] = []
        let monitor = DesktopClickMonitor(screen: screen, mapper: mapper, eventMonitoring: events) { clicks.append($0) }
        defer { monitor.stop() }

        XCTAssertTrue(monitor.start())
        XCTAssertTrue(monitor.start())
        XCTAssertEqual(events.callbacks.count, 1)
        let oldCallback = events.callbacks[0]
        oldCallback(CGPoint(x: -1216.001, y: -100))
        oldCallback(CGPoint(x: -1216, y: -100))
        XCTAssertEqual(clicks.map(\.tile), [WorldCoordinate(x: 0, y: 1), WorldCoordinate(x: 1, y: 1)])
        oldCallback(CGPoint(x: 0, y: 0))
        oldCallback(CGPoint(x: -1280, y: 600))
        XCTAssertEqual(clicks.count, 2, "Clicks outside the active display must be ignored")

        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(events.removedTokens.count, 1)
        oldCallback(CGPoint(x: -1250, y: -100))
        XCTAssertEqual(clicks.count, 2)
        XCTAssertTrue(monitor.start())
        oldCallback(CGPoint(x: -1250, y: -100))
        XCTAssertEqual(clicks.count, 2, "A prior registration must remain invalid after restart")
        events.callbacks[1](CGPoint(x: -1250, y: -100))
        XCTAssertEqual(clicks.count, 3)
        monitor.stop()
        XCTAssertEqual(events.removedTokens.count, 2)
        XCTAssertEqual(Set(events.removedTokens).count, 2)
    }

    @MainActor
    func testInstallationFailureDoesNotPublishAndCanBeRetried() throws {
        let events = FakeGlobalMouseEventMonitor()
        events.shouldFail = true
        var clicks: [DesktopClickSnapshot] = []
        let monitor = DesktopClickMonitor(screen: testScreen, mapper: try CoordinateMapper(canvasFrame: testScreen.frame, camera: camera), eventMonitoring: events) { clicks.append($0) }
        XCTAssertFalse(monitor.start())
        events.callbacks[0](testScreen.frame.origin)
        XCTAssertTrue(clicks.isEmpty)
        monitor.stop()
        XCTAssertTrue(events.removedTokens.isEmpty)
        events.shouldFail = false
        XCTAssertTrue(monitor.start())
        events.callbacks[1](testScreen.frame.origin)
        XCTAssertEqual(clicks.last?.tile, WorldCoordinate(x: 0, y: 0))
        monitor.stop()
        XCTAssertEqual(events.removedTokens.count, 1)
    }

    @MainActor
    func testEventCoordinatesUseCapturedEventPosition() throws {
        let point = CGPoint(x: -1000, y: -100)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        XCTAssertNil(event.window)
        XCTAssertEqual(CoordinateMapper.screenPoint(for: event), point)
    }

    @MainActor
    func testAppDisableAndShutdownRemoveObserverAndClearDiagnostics() {
        let events = FakeGlobalMouseEventMonitor()
        let screen = testScreen
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: events)
        defer { state.shutdown() }
        state.toggleDesktopWorld()
        events.callbacks[0](CGPoint(x: -1250, y: -100))
        XCTAssertEqual(state.observedClickCount, 1)
        XCTAssertEqual(state.lastClick?.tile, WorldCoordinate(x: 0, y: 1))
        state.toggleDesktopWorld()
        XCTAssertEqual(events.removedTokens.count, 1)
        XCTAssertNil(state.lastClick)
        XCTAssertEqual(state.observedClickCount, 0)
        state.toggleDesktopWorld()
        events.callbacks[0](screen.frame.origin)
        XCTAssertEqual(state.observedClickCount, 0)
        events.callbacks[1](screen.frame.origin)
        XCTAssertEqual(state.observedClickCount, 1)
        state.shutdown()
        state.shutdown()
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertNil(state.pointer)
        XCTAssertNil(state.lastClick)
        XCTAssertEqual(events.removedTokens.count, 2)
    }

    @MainActor
    func testRepeatedFlashesReuseNodeAndUseMapperGeometry() throws {
        let mapper = try CoordinateMapper(canvasFrame: testScreen.frame, camera: camera)
        let scene = DesktopScene(screen: testScreen, mapper: mapper)
        let flash = try XCTUnwrap(scene.childNode(withName: "click-flash") as? SKShapeNode)
        XCTAssertTrue(flash.isHidden)
        for tile in [WorldCoordinate(x: 1, y: 2), WorldCoordinate(x: 3, y: 4)] {
            scene.flashTile(tile)
            XCTAssertFalse(flash.isHidden)
            XCTAssertEqual(flash.alpha, 1)
            XCTAssertEqual(flash.path?.boundingBoxOfPath, mapper.sceneRect(forTile: tile, on: testScreen).insetBy(dx: 1, dy: 1))
            XCTAssertEqual(scene.children.count, 8)
        }
    }

    private var testScreen: ScreenDescriptor {
        ScreenDescriptor(id: "left", frame: CGRect(x: -1280, y: -200, width: 1280, height: 800), backingScale: 2)
    }

    private var camera: CameraState {
        CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    }
}
