import AppKit
import XCTest
@testable import RedstoneDesktop

@MainActor private final class DustBuildSpy: DesktopBuildPresenting {
    var world: World?
    func show() {}
    func close() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) { self.world = world }
}
final class DustStrokeTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 9) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    @MainActor private func app(_ spy: DustBuildSpy = DustBuildSpy()) -> AppState {
        let screen = ScreenDescriptor(id: "dust", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), buildControllerFactory: { _, _, _ in spy }, finderReferenceProviding: { screen })
    }
    func testDiagonalPathsFillElbowsAndDeduplicateAndRejectOverflow() throws {
        let document = WorldDocument(name: "Dust", terrainProfile: .legacyFixtureV1)
        var stroke = DustStroke(document: document)
        try stroke.extend(to: p(-4,-4)); try stroke.extend(to: p(3,3))
        XCTAssertEqual(stroke.tiles.count, 15)
        var reached: Set<WorldCoordinate> = [p(-4,-4)]
        for _ in 0..<15 {
            for tile in stroke.tiles where reached.contains(where: { abs($0.x - tile.x) + abs($0.y - tile.y) == 1 }) { reached.insert(tile) }
        }
        XCTAssertEqual(reached, stroke.tiles)
        let before = stroke.tiles
        try stroke.extend(to: p(-4,-4)); XCTAssertEqual(stroke.tiles, before)
        XCTAssertThrowsError(try stroke.extend(to: p(Int.max)))
        XCTAssertEqual(stroke.tiles, before)
        XCTAssertThrowsError(try stroke.extend(to: p(4096)))
    }
    func testPlanPreservesComponentsAndLiquidsAndExistingDust() throws {
        var document = WorldDocument(name: "Dust", terrainProfile: .legacyFixtureV1)
        document.terrainOverrides = Dictionary(uniqueKeysWithValues: (10...16).map { (p($0), Tile(terrain: $0 == 13 ? .lava : .grass)) })
        document.circuit.components[p(12)] = CircuitComponent(kind: .repeater)
        document.circuit.components[p(14)] = CircuitComponent(kind: .dust)
        var stroke = DustStroke(document: document)
        try stroke.extend(to: p(10)); try stroke.extend(to: p(16))
        XCTAssertEqual(stroke.placed, 4); XCTAssertEqual(stroke.blocked, 2)
        XCTAssertEqual(stroke.world?.circuit.components[p(12)]?.kind, .repeater)
        XCTAssertNil(stroke.world?.circuit.components[p(13)])
        XCTAssertEqual(document.circuit.components.count, 2)
    }
    @MainActor func testNativeEditorDragPreviewsAndCommitsOnceAndEscapeDoesNotPlaceOnRelease() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        XCTAssertTrue(app.applyTerrain(brush: .grass, tiles: Set((10...18).map { p($0) })))
        let baseline = app.selectedDocument.circuit
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: editor.viewport), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let view = EditorCanvasSurface(frame: CGRect(origin: .zero, size: editor.viewport))
        window.contentView = view; view.editor = editor; view.appState = app; editor.tool = .dust
        func event(_ type: NSEvent.EventType, _ coordinate: WorldCoordinate) throws -> NSEvent {
            let rect = try XCTUnwrap(editor.mapper(size: editor.viewport)).screenRect(forTile: coordinate)
            return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: rect.midX, y: rect.midY), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, p(10)))
        view.mouseDragged(with: try event(.leftMouseDragged, p(16)))
        XCTAssertEqual(app.selectedDocument.circuit, baseline)
        XCTAssertEqual(editor.dustStroke?.placed, 7)
        view.mouseUp(with: try event(.leftMouseUp, p(16)))
        for x in 10...16 { XCTAssertEqual(app.editorWorld.circuit.components[p(x)]?.kind, .dust) }
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.selectedDocument.circuit, baseline)
        XCTAssertTrue(app.undoCircuit(redo: true))
        view.mouseDown(with: try event(.leftMouseDown, p(17)))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        view.mouseUp(with: try event(.leftMouseUp, p(17)))
        XCTAssertNil(app.editorWorld.circuit.components[p(17)])
        view.mouseDown(with: try event(.leftMouseDown, p(18)))
        view.mouseUp(with: try event(.leftMouseUp, p(18)))
        XCTAssertEqual(app.editorWorld.circuit.components[p(18)]?.kind, .dust, "Single clicks still place dust")
    }
    @MainActor func testDesktopBuildDragPreviewReleaseAndCancelAndStaleSession() throws {
        let spy = DustBuildSpy(), app = app(spy); defer { app.shutdown() }
        XCTAssertTrue(app.applyTerrain(brush: .grass, tiles: Set((10...18).map { p($0) })))
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession), baseline = app.desktopWorld.circuit
        func point(_ x: Int) -> CGPoint { let rect = session.mapper.screenRect(forTile: p(x)); return CGPoint(x: rect.midX, y: rect.midY) }
        app.buildDust(at: point(10), phase: .begin, sessionID: session.id)
        app.buildDust(at: point(16), phase: .drag, sessionID: session.id)
        XCTAssertEqual(app.desktopWorld.circuit, baseline)
        XCTAssertEqual(spy.world?.circuit.components[p(13)]?.kind, .dust)
        app.buildDust(at: point(16), phase: .end, sessionID: session.id)
        for x in 10...16 { XCTAssertEqual(app.desktopWorld.circuit.components[p(x)]?.kind, .dust) }
        app.buildDust(at: point(17), phase: .begin, sessionID: session.id)
        app.buildDust(at: point(17), phase: .cancel, sessionID: session.id)
        app.buildDust(at: point(17), phase: .end, sessionID: session.id)
        XCTAssertNil(app.desktopWorld.circuit.components[p(17)])
        app.exitDesktopBuildMode()
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.desktopWorld.circuit, baseline)
        XCTAssertTrue(app.enterDesktopBuildMode())
        app.buildDust(at: point(18), phase: .begin, sessionID: session.id)
        XCTAssertNil(app.buildSession?.dustStroke)
    }
    @MainActor func testNativeDesktopSurfaceDispatchesCompleteDustDrag() throws {
        let app = app(); defer { app.shutdown() }
        XCTAssertTrue(app.applyTerrain(brush: .grass, tiles: Set((10...16).map { p($0) })))
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession)
        let screen = ScreenDescriptor(id: "dust", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 1)
        let surface = DesktopBuildSurface(session: session, screen: screen)
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = surface
        surface.dustInput = { point, phase in app.buildDust(at: point, phase: phase, sessionID: session.id) }
        func event(_ type: NSEvent.EventType, _ x: Int) throws -> NSEvent {
            let rect = session.mapper.screenRect(forTile: p(x))
            let local = session.mapper.scenePoint(fromScreen: CGPoint(x: rect.midX, y: rect.midY), on: screen)
            return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        surface.mouseDown(with: try event(.leftMouseDown, 10))
        surface.mouseDragged(with: try event(.leftMouseDragged, 16))
        XCTAssertEqual(session.dustStroke?.placed, 7)
        surface.mouseUp(with: try event(.leftMouseUp, 16))
        XCTAssertNil(session.dustStroke)
        for x in 10...16 { XCTAssertEqual(app.desktopWorld.circuit.components[p(x)]?.kind, .dust) }
    }
    @MainActor func testWorldChangeAndTestModeRejectDraftWithoutMutatingData() throws {
        let app = app(), editor = EditorSession(testScheduler: ManualCircuitTickScheduler()); defer { app.shutdown() }
        editor.tool = .dust
        let rect = try XCTUnwrap(editor.mapper(size: editor.viewport)).screenRect(forTile: p(10))
        let point = CGPoint(x: rect.midX, y: rect.midY)
        editor.dustInput(at: point, size: editor.viewport, phase: .begin, appState: app)
        XCTAssertNotNil(editor.dustStroke)
        XCTAssertTrue(app.applyTerrain(brush: .grass, tiles: [p(10)]))
        let baseline = app.selectedDocument.circuit
        editor.dustInput(at: point, size: editor.viewport, phase: .end, appState: app)
        XCTAssertNil(editor.dustStroke); XCTAssertEqual(app.selectedDocument.circuit, baseline)
        editor.startTesting(app); editor.tool = .dust
        editor.dustInput(at: point, size: editor.viewport, phase: .begin, appState: app)
        XCTAssertNil(editor.dustStroke); XCTAssertEqual(app.selectedDocument.circuit, baseline)
        editor.stopTesting(); XCTAssertNil(editor.circuitTest)
    }
}
