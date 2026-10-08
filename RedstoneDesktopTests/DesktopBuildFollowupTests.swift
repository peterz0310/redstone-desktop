import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class FollowupPresenter: DesktopBuildPresenting {
    func show() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {}
    func close() {}
}

final class DesktopBuildFollowupTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "hover", frame: CGRect(x: -100, y: -200, width: 1280, height: 800), backingScale: 2)

    @MainActor
    private func state() -> AppState {
        let screen = screen
        return AppState(screenProviding: { screen }, tickScheduler: ManualCircuitTickScheduler(),
            buildControllerFactory: { _, _, _ in FollowupPresenter() })
    }

    @MainActor
    private func window() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: -100, y: -100, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor
    func testHoverEditsExistingRepeaterInsteadOfSelectedOneAndWrapsDelay() throws {
        let app = state()
        defer { app.shutdown() }
        let first = WorldCoordinate(x: 10, y: 3), second = WorldCoordinate(x: 11, y: 3)
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .repeater, direction: .north, repeaterDelay: .four), at: first), .allowed)
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .repeater, direction: .south, repeaterDelay: .two), at: second), .allowed)
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession)
        session.selectedTile = second
        session.hoveredTile = first
        let secondBefore = app.desktopWorld.circuit.components[second]
        app.editHoveredBuildRepeater(at: first, rotate: true)
        XCTAssertEqual(app.desktopWorld.circuit.components[first]?.direction, .east)
        XCTAssertEqual(app.desktopWorld.circuit.components[first]?.repeaterDelay, .four)
        app.editHoveredBuildRepeater(at: first, rotate: false)
        XCTAssertEqual(app.desktopWorld.circuit.components[first]?.repeaterDelay, .one)
        XCTAssertEqual(app.desktopWorld.circuit.components[second], secondBefore)
        XCTAssertEqual(session.selectedTile, first)
        XCTAssertEqual(session.direction, .east)
        XCTAssertEqual(session.delay, .one)
        XCTAssertEqual(app.editorWorld, app.desktopWorld)
        XCTAssertTrue(app.simulator.poweredTiles.isEmpty)
    }

    @MainActor
    func testHoverMissingNonRepeaterOrStaleTargetNeverEditsOldSelection() throws {
        let app = state()
        defer { app.shutdown() }
        let tile = WorldCoordinate(x: 10, y: 3)
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .repeater), at: tile), .allowed)
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession)
        session.selectedTile = tile
        let before = app.desktopWorld
        for hover in [nil, DemoCircuit.button, WorldCoordinate(x: 12, y: 3)] as [WorldCoordinate?] {
            session.hoveredTile = hover
            app.editHoveredBuildRepeater(at: hover, rotate: true)
            app.editHoveredBuildRepeater(at: hover, rotate: false)
            XCTAssertEqual(app.desktopWorld, before)
        }
        session.hoveredTile = DemoCircuit.button
        app.editHoveredBuildRepeater(at: tile, rotate: true)
        XCTAssertEqual(app.desktopWorld, before)
        app.exitDesktopBuildMode()
        app.editHoveredBuildRepeater(at: tile, rotate: true)
        XCTAssertEqual(app.desktopWorld, before)
    }

    @MainActor
    func testNativeHoverShortcutsAndMouseExitUseMappedTarget() throws {
        let app = state()
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: app.desktopCamera)
        let session = DesktopBuildSession(worldID: app.activeWorldID, areaID: app.library.activeAreaID, mapper: mapper, title: "Fixture")
        let controller = DesktopBuildController(session: session, screen: screen, appState: app)
        defer { controller.close(); app.shutdown() }
        var rotated: WorldCoordinate?, delayed: WorldCoordinate?, rotations = 0
        controller.surface.rotate = { rotated = $0; rotations += 1 }
        controller.surface.changeDelay = { delayed = $0 }
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 672, y: 224), modifierFlags: [], timestamp: 0, windowNumber: controller.inputWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        controller.surface.mouseMoved(with: mouse)
        XCTAssertEqual(session.hoveredTile, WorldCoordinate(x: 10, y: 3))
        func key(_ character: String, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: controller.inputWindow.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0))
        }
        controller.surface.keyDown(with: try key("r"))
        controller.surface.keyDown(with: try key("t"))
        XCTAssertEqual(rotated, session.hoveredTile)
        XCTAssertEqual(delayed, session.hoveredTile)
        controller.surface.keyDown(with: try key("r", flags: .command))
        XCTAssertEqual(rotations, 1)
        controller.surface.mouseExited(with: mouse)
        XCTAssertNil(session.hoveredTile)
        controller.surface.keyDown(with: try key("t"))
        XCTAssertNil(delayed)
    }

    @MainActor
    func testBoundaryPulseReducedMotionResizeAndTeardown() throws {
        let app = state()
        let session = DesktopBuildSession(worldID: app.activeWorldID, areaID: app.library.activeAreaID,
            mapper: try CoordinateMapper(canvasFrame: screen.frame, camera: app.desktopCamera), title: "Fixture")
        let controller = DesktopBuildController(session: session, screen: screen, appState: app)
        defer { controller.close(); app.shutdown() }
        let boundary = try XCTUnwrap(controller.surface.scene?.childNode(withName: "build-mode-boundary") as? SKShapeNode)
        XCTAssertEqual(boundary.path?.boundingBoxOfPath, CGRect(x: 5, y: 5, width: 1270, height: 790))
        XCTAssertEqual(boundary.fillColor.alphaComponent, 0)
        XCTAssertEqual(boundary.lineWidth, 8)
        controller.surface.setReducedMotion(false)
        XCTAssertNotNil(boundary.action(forKey: "build-pulse"))
        controller.surface.setReducedMotion(true)
        XCTAssertFalse(boundary.hasActions())
        XCTAssertEqual(boundary.alpha, 0.7, accuracy: 0.001)
        controller.surface.setFrameSize(CGSize(width: 800, height: 600))
        controller.surface.layout()
        XCTAssertEqual(boundary.path?.boundingBoxOfPath, CGRect(x: 5, y: 5, width: 790, height: 590))
        controller.surface.setReducedMotion(false)
        controller.close()
        XCTAssertFalse(boundary.hasActions())
        XCTAssertFalse(controller.inputWindow.isVisible)
    }

    @MainActor
    func testVisibilityHidesOnlyRegisteredVisibleEditorsAndRestoresSameWindows() {
        let registration = EditorWindowRegistrationView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNil(registration.hitTest(CGPoint(x: 50, y: 50)), "Window registration must never intercept editor controls")
        let manager = EditorWindowVisibility()
        let first = window(), second = window(), alreadyHidden = window(), settings = window()
        defer { for window in [first, second, alreadyHidden, settings] { window.close() } }
        first.orderFront(nil); second.orderFront(nil); settings.orderFront(nil)
        let frame = first.frame
        manager.register(first); manager.register(second); manager.register(alreadyHidden)
        manager.beginBuild(); manager.beginBuild()
        XCTAssertFalse(first.isVisible)
        XCTAssertFalse(second.isVisible)
        XCTAssertTrue(settings.isVisible)
        manager.endBuild(restore: true); manager.endBuild(restore: true)
        XCTAssertTrue(first.isVisible)
        XCTAssertTrue(second.isVisible)
        XCTAssertFalse(alreadyHidden.isVisible)
        XCTAssertEqual(first.frame, frame)
        XCTAssertFalse(first.isKeyWindow, "Restoration must not take key focus from another app")
    }

    @MainActor
    func testAppLifecycleRestoresEditorOnExitButNotShutdownOrFailedEntry() {
        let app = state(), editor = window()
        defer { app.shutdown(); editor.close() }
        app.editorWindows.register(editor)
        editor.orderFront(nil)
        XCTAssertTrue(app.enterDesktopBuildMode())
        XCTAssertFalse(editor.isVisible)
        app.exitDesktopBuildMode()
        XCTAssertTrue(editor.isVisible)
        XCTAssertFalse(app.isDesktopWorldEnabled)
        XCTAssertTrue(app.enterDesktopBuildMode())
        app.shutdown()
        XCTAssertFalse(editor.isVisible, "Quit must not flash the editor back on screen")
        editor.orderFront(nil)
        let unavailable = AppState(screenProviding: { nil })
        unavailable.editorWindows.register(editor)
        XCTAssertFalse(unavailable.enterDesktopBuildMode())
        XCTAssertTrue(editor.isVisible)
        unavailable.shutdown()
    }

    @MainActor
    func testWindowClosedDuringBuildIsNotReopened() {
        let manager = EditorWindowVisibility(), editor = window()
        manager.register(editor)
        editor.orderFront(nil)
        manager.beginBuild()
        editor.close()
        manager.endBuild(restore: true)
        XCTAssertFalse(editor.isVisible)
    }
}
