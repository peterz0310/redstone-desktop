import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class BuildPresenterSpy: DesktopBuildPresenting {
    var shows = 0
    var closes = 0
    var worlds: [World] = []
    func show() { shows += 1 }
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) { worlds.append(world) }
    func close() { closes += 1 }
}

private final class BuildStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws { try document.validate(); self.document = document }
}

final class DesktopBuildTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "build", frame: CGRect(x: -1280, y: -200, width: 1280, height: 800), backingScale: 2)

    @MainActor
    private func state(_ spy: BuildPresenterSpy, store: BuildStore? = nil, center: NotificationCenter = NotificationCenter(), opener: FixtureItemOpener = FixtureItemOpener()) -> AppState {
        let screen = screen
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, libraryStore: store,
            autosaveDelay: .seconds(3600), displayNotificationCenter: center,
            buildControllerFactory: { _, _, _ in spy }, finderReferenceProviding: { screen })
    }

    @MainActor
    private func click(_ tile: WorldCoordinate, app: AppState, erase: Bool = false) throws {
        let session = try XCTUnwrap(app.buildSession)
        let rect = session.mapper.screenRect(forTile: tile)
        app.buildClick(at: CGPoint(x: rect.midX, y: rect.midY), erase: erase, sessionID: session.id)
    }

    @MainActor
    func testSessionMapsNegativeDisplayAndFractionalWorldAndBoundsHotbar() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame,
            camera: CameraState(worldOrigin: WorldPoint(x: -0.25, y: -2.5), pointsPerTile: 64))
        let session = DesktopBuildSession(worldID: UUID(), areaID: UUID(), mapper: mapper, title: "Fixture")
        XCTAssertEqual(session.tile(at: screen.frame.origin), WorldCoordinate(x: -1, y: -3))
        XCTAssertNil(session.tile(at: CGPoint(x: screen.frame.maxX, y: screen.frame.maxY)))
        XCTAssertNil(session.tile(at: CGPoint(x: CGFloat.infinity, y: 0)))
        let local = CGPoint(x: 32, y: 64)
        XCTAssertEqual(mapper.scenePoint(fromScreen: mapper.screenPoint(fromScene: local, on: screen), on: screen), local)
        session.selectTool(number: 4)
        XCTAssertEqual(session.component?.kind, .repeater)
        session.selectTool(number: 0); session.selectTool(number: DesktopBuildSession.Tool.allCases.count + 1)
        XCTAssertEqual(session.tool, .repeater)
        session.selectTool(number: DesktopBuildSession.Tool.allCases.count); session.cycleTool(forward: true)
        XCTAssertEqual(session.tool, .dust)
        session.cycleTool(forward: false)
        XCTAssertEqual(session.tool, .terrain)
        for _ in 0..<4 { session.rotateDirection() }
        XCTAssertEqual(session.direction, .east)
    }

    @MainActor
    func testEntryStopsRuntimeAndExitIsIdempotentWithoutRestartOrActions() throws {
        let spy = BuildPresenterSpy(), opener = FixtureItemOpener(), app = state(spy, opener: opener)
        defer { app.shutdown() }
        XCTAssertFalse(app.isDesktopBuildMode)
        app.toggleDesktopWorld()
        XCTAssertTrue(app.isDesktopWorldEnabled)
        XCTAssertTrue(app.enterDesktopBuildMode())
        XCTAssertFalse(app.isDesktopWorldEnabled)
        XCTAssertNil(app.desktopController)
        XCTAssertNil(app.activationTask)
        XCTAssertTrue(app.isEditorConfigurationLocked)
        XCTAssertFalse(app.updateSelectedArea(camera: app.selectedAreaCamera))
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .dust), at: WorldCoordinate(x: 10, y: 3)), .rejected(.reserved))
        let session = try XCTUnwrap(app.buildSession)
        XCTAssertTrue(app.enterDesktopBuildMode())
        XCTAssertEqual(spy.shows, 1)
        app.handleCircuitClick(DemoCircuit.button)
        for _ in 0..<20 { app.advanceCircuitTick() }
        XCTAssertTrue(app.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(opener.urls.isEmpty)
        app.exitDesktopBuildMode(); app.exitDesktopBuildMode()
        XCTAssertEqual(spy.closes, 1)
        XCTAssertFalse(app.isDesktopWorldEnabled)
        XCTAssertFalse(app.isEditorConfigurationLocked)
        let before = app.desktopWorld
        app.buildClick(at: screen.frame.origin, sessionID: session.id)
        XCTAssertEqual(app.desktopWorld, before)
        XCTAssertTrue(app.enterDesktopBuildMode())
        let rect = try XCTUnwrap(app.buildSession).mapper.screenRect(forTile: WorldCoordinate(x: 10, y: 3))
        app.buildClick(at: CGPoint(x: rect.midX, y: rect.midY), sessionID: session.id)
        XCTAssertEqual(app.desktopWorld, before, "An earlier session must not edit a newly entered session")
        app.exitDesktopBuildMode()
        XCTAssertEqual(spy.closes, 2)
        app.toggleDesktopWorld()
        XCTAssertTrue(app.isDesktopWorldEnabled)
        XCTAssertTrue(try XCTUnwrap(app.desktopController?.window).ignoresMouseEvents)
    }

    @MainActor
    func testBuildEditsAssignedWorldAndPersistsWithoutChangingEditorSelection() throws {
        let spy = BuildPresenterSpy(), store = BuildStore(), app = state(spy, store: store)
        defer { app.shutdown() }
        let activeID = app.activeWorldID, areaID = app.library.activeAreaID
        XCTAssertTrue(app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        let otherID = app.selectedWorldID, otherWorld = app.editorWorld
        XCTAssertTrue(app.enterDesktopBuildMode())
        try click(WorldCoordinate(x: 10, y: 3), app: app)
        XCTAssertEqual(app.desktopWorld.circuit.components[WorldCoordinate(x: 10, y: 3)]?.kind, .dust)
        XCTAssertEqual(app.selectedWorldID, otherID)
        XCTAssertEqual(app.editorWorld, otherWorld)
        XCTAssertEqual(app.buildSession?.worldID, activeID)
        XCTAssertEqual(app.library.activeAreaID, areaID)
        XCTAssertFalse(app.activateSelectedArea())
        XCTAssertEqual(app.library.activeAreaID, areaID)
        app.exitDesktopBuildMode()
        let reopened = state(BuildPresenterSpy(), store: store)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.library, app.library)
        XCTAssertFalse(reopened.isDesktopBuildMode)
        XCTAssertFalse(reopened.isDesktopWorldEnabled)
    }

    @MainActor
    func testSharedPlacementRejectionAndErasePreserveTerrain() throws {
        let app = state(BuildPresenterSpy())
        defer { app.shutdown() }
        XCTAssertTrue(app.enterDesktopBuildMode())
        let before = app.desktopWorld
        for tile in [WorldCoordinate(x: 14, y: 3), WorldCoordinate(x: 10, y: 5), DemoCircuit.button] {
            try click(tile, app: app)
            XCTAssertEqual(app.desktopWorld, before)
        }
        let tile = WorldCoordinate(x: 10, y: 3), terrain = app.desktopWorld.tile(at: tile)
        try click(tile, app: app)
        XCTAssertEqual(app.editorWorld, app.desktopWorld)
        try click(tile, app: app, erase: true)
        XCTAssertNil(app.desktopWorld.circuit.components[tile])
        XCTAssertEqual(app.desktopWorld.tile(at: tile), terrain)
        XCTAssertEqual(app.desktopWorld, before)
        app.buildSession?.tool = .erase
        try click(DemoCircuit.button, app: app)
        XCTAssertNil(app.desktopWorld.circuit.components[DemoCircuit.button])
        let erased = app.desktopWorld
        try click(DemoCircuit.button, app: app)
        XCTAssertEqual(app.desktopWorld, erased)
    }

    @MainActor
    func testRotationAndDelayApplyToSelectedRepeaterOrNextPlacementOnly() throws {
        let app = state(BuildPresenterSpy())
        defer { app.shutdown() }
        XCTAssertTrue(app.enterDesktopBuildMode())
        app.buildSession?.tool = .repeater
        app.rotateBuildRepeater()
        app.setBuildRepeaterDelay(.three)
        let tile = WorldCoordinate(x: 10, y: 3)
        try click(tile, app: app)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.direction, .south)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.repeaterDelay, .three)
        app.rotateBuildRepeater(); app.setBuildRepeaterDelay(.four)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.direction, .west)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.repeaterDelay, .four)
        try click(DemoCircuit.button, app: app)
        let before = app.desktopWorld
        app.rotateBuildRepeater(); app.setBuildRepeaterDelay(.two)
        XCTAssertEqual(app.desktopWorld, before)
        XCTAssertEqual(app.desktopWorld.circuit.components[DemoCircuit.button]?.kind, .button)
        app.exitDesktopBuildMode()
        app.rotateBuildRepeater(); app.setBuildRepeaterDelay(.one)
        XCTAssertEqual(app.desktopWorld, before)
    }

    @MainActor
    func testEntryRefusesMissingDisplayWithoutStoppingExistingRuntime() {
        var available: ScreenDescriptor? = screen
        let spy = BuildPresenterSpy()
        let app = AppState(screenProviding: { available }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), buildControllerFactory: { _, _, _ in spy })
        defer { app.shutdown() }
        app.toggleDesktopWorld()
        available = nil
        XCTAssertFalse(app.enterDesktopBuildMode())
        XCTAssertTrue(app.isDesktopWorldEnabled)
        XCTAssertNil(app.buildSession)
        XCTAssertEqual(spy.shows, 0)
    }

    @MainActor
    func testAppSwitchHideAndShutdownRemoveCapture() {
        let center = NotificationCenter(), spy = BuildPresenterSpy(), app = state(spy, center: center)
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification] {
            XCTAssertTrue(app.enterDesktopBuildMode())
            center.post(name: name, object: nil)
            XCTAssertFalse(app.isDesktopBuildMode)
            XCTAssertNil(app.buildController)
        }
        XCTAssertTrue(app.enterDesktopBuildMode())
        app.shutdown()
        XCTAssertEqual(spy.closes, 3)
        XCTAssertFalse(app.isDesktopBuildMode)
    }

    @MainActor
    func testDisplayChangeExitsAndInvalidatesOldInput() throws {
        var current = screen
        let spy = BuildPresenterSpy()
        let app = AppState(screenProviding: { current }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), displayNotificationCenter: NotificationCenter(),
            buildControllerFactory: { _, _, _ in spy }, finderReferenceProviding: { current })
        defer { app.shutdown() }
        XCTAssertTrue(app.enterDesktopBuildMode())
        let oldID = try XCTUnwrap(app.buildSession?.id), before = app.desktopWorld
        current = ScreenDescriptor(id: "new", frame: CGRect(x: 0, y: 0, width: 800, height: 600), backingScale: 1)
        app.displayParametersDidChange()
        XCTAssertFalse(app.isDesktopBuildMode)
        XCTAssertEqual(spy.closes, 1)
        app.buildClick(at: current.frame.origin, sessionID: oldID)
        XCTAssertEqual(app.desktopWorld, before)
    }

    @MainActor
    func testNativeCaptureIsTransparentAboveIconsBelowOrdinaryWindowsAndCloseRemovesInput() throws {
        let app = state(BuildPresenterSpy())
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: app.desktopCamera)
        let session = DesktopBuildSession(worldID: app.activeWorldID, areaID: app.library.activeAreaID, mapper: mapper, title: "Fixture")
        let controller = DesktopBuildController(session: session, screen: screen, appState: app)
        let window = controller.inputWindow
        XCTAssertEqual(window.frame, screen.frame)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertFalse(window.isOpaque)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertGreaterThan(window.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertLessThan(window.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertTrue(controller.surface.allowsTransparency)
        XCTAssertEqual(controller.surface.scene?.backgroundColor.alphaComponent, 0)
        XCTAssertEqual(controller.palette.level, .floating)
        var received: CGPoint?, erased = false, exits = 0
        controller.surface.click = { received = $0; erased = $1 }
        controller.surface.exit = { exits += 1 }
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: 32, y: 64), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        controller.surface.rightMouseDown(with: event)
        XCTAssertEqual(received, CGPoint(x: screen.frame.minX + 32, y: screen.frame.minY + 64))
        XCTAssertTrue(erased)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        controller.surface.keyDown(with: escape)
        XCTAssertEqual(exits, 1)
        controller.close(); controller.close()
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(controller.palette.isVisible)
        XCTAssertFalse(controller.renderer.window!.isVisible)
        XCTAssertNil(controller.surface.click)
        XCTAssertNil(controller.surface.exit)
    }
}
