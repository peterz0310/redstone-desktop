import AppKit
import CoreGraphics
import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class DesktopWindowTests: XCTestCase {
    @MainActor
    func testWindowUsesRequestedFrameAndCannotTakeFinderInput() throws {
        let frame = CGRect(x: -1280, y: -200, width: 1280, height: 800)
        let screen = ScreenDescriptor(id: "test", frame: frame, backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: frame, camera: camera)
        let controller = DesktopWindowController(screen: screen, mapper: mapper)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }

        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(window.styleMask, .borderless)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertGreaterThan(window.level.rawValue, Int(CGWindowLevelForKey(.desktopWindow)))
        XCTAssertLessThan(window.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertLessThan(window.level.rawValue, NSWindow.Level.normal.rawValue)
        let view = try XCTUnwrap(window.contentView as? SKView)
        XCTAssertTrue(view.scene is DesktopScene)
        XCTAssertEqual(view.scene?.size, frame.size)
        // Repeating enable uses the same window and never makes it key.
        controller.enable()
        controller.enable()
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        // Ordering out is safe to repeat and leaves the window hidden.
        controller.disable()
        controller.disable()
        XCTAssertFalse(window.isVisible)
    }

    @MainActor
    func testCheckerRebuildKeepsNodeCountBoundedWhenResized() throws {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: camera)
        let scene = DesktopScene(screen: screen, mapper: mapper)
        XCTAssertEqual(scene.children.count, 5)
        for size in [CGSize(width: 800, height: 600), CGSize(width: 2560, height: 1440)] {
            scene.size = size
            XCTAssertEqual(scene.children.count, 5)
            XCTAssertEqual(scene.children.filter { $0 is SKShapeNode }.count, 4)
        }
    }

    @MainActor
    func testDesktopCheckerStartsDisabled() {
        let state = AppState()
        XCTAssertFalse(state.isDesktopWorldEnabled)
    }

    @MainActor
    func testStateCanEnableDisableAndEnableAgain() {
        let state = AppState(screenProviding: {
            ScreenDescriptor(id: "test", frame: CGRect(x: -100, y: -100, width: 64, height: 64), backingScale: 1)
        }, clickEventMonitoring: FakeGlobalMouseEventMonitor())
        for _ in 0..<2 {
            state.toggleDesktopWorld()
            XCTAssertTrue(state.isDesktopWorldEnabled)
            state.toggleDesktopWorld()
            XCTAssertFalse(state.isDesktopWorldEnabled)
            XCTAssertNil(state.pointer)
        }
    }

    @MainActor
    func testUnavailableDisplayLeavesCheckerDisabled() {
        let state = AppState(screenProviding: { nil })
        state.toggleDesktopWorld()
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertEqual(state.desktopStatus, "No main display is available.")
    }

    private var camera: CameraState {
        CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    }
}
