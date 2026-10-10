import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor private final class BlueprintFinderFixture: DesktopItemProviding {
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] { calls += 1; return [] }
}
private final class BlueprintFailingStore: CircuitBlueprintStoring {
    var fails = false
    var document = CircuitBlueprintDocument()
    func load() throws -> CircuitBlueprintDocument { document }
    func save(_ document: CircuitBlueprintDocument) throws {
        if fails { throw BlueprintError("Fixture write failed") }
        self.document = document
    }
}
final class SelectionBlueprintTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 0) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    @MainActor private func app() -> AppState {
        let screen = ScreenDescriptor(id: "selection", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), finderDiagnostics: FinderDiagnosticsModel(provider: BlueprintFinderFixture()),
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: FixtureItemOpener(), finderReferenceProviding: { screen })
    }
    @MainActor private func point(_ tile: WorldCoordinate, _ editor: EditorSession) -> CGPoint {
        let rect = editor.mapper(size: editor.viewport)!.screenRect(forTile: tile)
        return CGPoint(x: rect.midX, y: rect.midY)
    }
    @MainActor func testNativeShiftMarqueeReturningToStartDoesNotPanAndKeyboardUndoRedo() throws {
        let app = app(), editor = EditorSession()
        defer { app.shutdown() }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: editor.viewport), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = EditorCanvasSurface(frame: CGRect(origin: .zero, size: editor.viewport))
        window.contentView = view; view.appState = app; view.editor = editor
        defer { window.close() }
        let target = p(12, 8)
        editor.tool = .dust
        editor.click(at: point(target, editor), size: editor.viewport, appState: app)
        editor.tool = .select
        let camera = editor.camera, start = point(target, editor)
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [.shift], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try mouse(.leftMouseDown, start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: start.x + 50, y: start.y + 50)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, start))
        view.mouseUp(with: try mouse(.leftMouseUp, start))
        XCTAssertEqual(editor.camera, camera)
        XCTAssertTrue(editor.selection(app).contains(target))
        func key(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        }
        XCTAssertTrue(window.makeFirstResponder(view))
        XCTAssertTrue(view.performKeyEquivalent(with: try key([.command])))
        XCTAssertNil(app.editorWorld.circuit.components[target])
        XCTAssertTrue(view.performKeyEquivalent(with: try key([.command, .shift])))
        XCTAssertEqual(app.editorWorld.circuit.components[target]?.kind, .dust)
    }
    func testCaptureNormalizesNegativeCoordinatesAndRotationPreservesConfigurationAndLeverState() throws {
        let original: [WorldCoordinate: CircuitComponent] = [p(-5,-9): CircuitComponent(kind: .lever), p(-3,-9): CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: .four),
            p(-3,-8): CircuitComponent(kind: .output, outputAction: .executeOccupant)]
        let blueprint = try CircuitBlueprint.capture(name: "My build", components: original, levers: [p(-5,-9)])
        XCTAssertEqual(blueprint.width, 3); XCTAssertEqual(blueprint.height, 2)
        let rotated = try blueprint.rotatedClockwise()
        XCTAssertEqual(rotated.width, 2); XCTAssertEqual(rotated.height, 3)
        XCTAssertEqual(rotated.circuit.components[p(0)]?.repeaterDelay, .four)
        XCTAssertEqual(rotated.circuit.components[p(0)]?.direction, .south)
        XCTAssertEqual(rotated.circuit.components[p(1)]?.outputAction, .executeOccupant)
        XCTAssertEqual(rotated.activeLevers, [p(0,2)])
        XCTAssertEqual(try rotated.rotatedClockwise().rotatedClockwise().rotatedClockwise(), blueprint)
        let (placed, levers) = try blueprint.positioned(at: p(50,-20))
        XCTAssertEqual(placed.components[p(52,-20)]?.repeaterDelay, .four)
        XCTAssertEqual(levers, [p(50,-20)])
    }
    func testBoundsUnknownConfigurationAndCoordinateOverflowFailClosed() throws {
        XCTAssertThrowsError(try CircuitBlueprint.capture(name: "empty", components: [:]))
        XCTAssertThrowsError(try CircuitBlueprint.capture(name: "wide", components: [p(0): CircuitComponent(kind: .dust), p(256): CircuitComponent(kind: .dust)]))
        XCTAssertThrowsError(try CircuitBlueprint.capture(name: "overflow", components: [p(Int.min): CircuitComponent(kind: .dust), p(Int.max): CircuitComponent(kind: .dust)]))
        let blueprint = try CircuitBlueprint.capture(name: "Pair", components: [p(0): CircuitComponent(kind: .lever), p(1): CircuitComponent(kind: .dust)])
        XCTAssertThrowsError(try blueprint.positioned(at: p(Int.max)))
        var invalid = blueprint; invalid.activeLevers = [p(1)]; XCTAssertThrowsError(try invalid.validate())
        invalid = blueprint; invalid.circuit.components[p(0)] = CircuitComponent(kind: .empty); XCTAssertThrowsError(try invalid.validate())
    }
    func testPlacementRejectsLateCollisionOrTerrainWithoutChangingAnything() throws {
        let blueprint = try CircuitBlueprint.capture(name: "Pair", components: [p(0): CircuitComponent(kind: .button), p(1): CircuitComponent(kind: .dust)])
        let world = World(tiles: [p(0): Tile(terrain: .grass), p(1): Tile(terrain: .deepWater)])
        XCTAssertThrowsError(try BlueprintPlacement.applying(blueprint, at: p(0), to: world))
        XCTAssertTrue(world.circuit.components.isEmpty)
        let occupied = World(tiles: [p(0): Tile(terrain: .grass), p(1): Tile(terrain: .stone)], circuit: CircuitWorld(components: [p(1): CircuitComponent(kind: .output)]))
        XCTAssertThrowsError(try BlueprintPlacement.applying(blueprint, at: p(0), to: occupied))
        XCTAssertEqual(occupied.circuit.components.count, 1)
    }
    func testSparseHistoryBoundsRedoInvalidationAndConflictDetection() throws {
        let before = CircuitWorld(), after = CircuitWorld(components: [p(0): CircuitComponent(kind: .lever)])
        let change = CircuitChange(before: before, after: after, leversBefore: [], leversAfter: [p(0)])
        XCTAssertEqual(change.coordinates, [p(0)])
        let (undo, levers) = try change.applying(to: after, levers: [p(0)], undo: true)
        XCTAssertEqual(undo, before); XCTAssertTrue(levers.isEmpty)
        XCTAssertThrowsError(try change.applying(to: before, levers: [], undo: true))
        var history = CircuitEditHistory()
        for _ in 0..<105 { history.record(change) }
        XCTAssertEqual(history.undo.count, 100)
        history.didUndo(); XCTAssertEqual(history.redo.count, 1)
        history.record(change); XCTAssertTrue(history.redo.isEmpty)
        history.didUndo(); history.didRedo(); XCTAssertTrue(history.redo.isEmpty)
    }
    @MainActor func testDragRegionShiftClickAndCopyDoNotMutateWorldOrDesktop() throws {
        let state = app(), editor = EditorSession(); defer { state.shutdown() }
        let before = state.library, camera = state.desktopCamera
        editor.tool = .region
        editor.beginRegion(at: point(DemoCircuit.button, editor), size: editor.viewport, additive: false)
        editor.dragRegion(to: point(DemoCircuit.output, editor), size: editor.viewport, appState: state)
        editor.endRegion()
        XCTAssertEqual(editor.selection(state).count, 6)
        XCTAssertTrue(editor.copySelection(state))
        XCTAssertEqual(editor.clipboard?.circuit.components.count, 6)
        editor.click(at: point(DemoCircuit.output, editor), size: editor.viewport, appState: state, additive: true)
        XCTAssertEqual(editor.selection(state).count, 5)
        XCTAssertEqual(state.library, before); XCTAssertEqual(state.desktopCamera, camera)
        XCTAssertFalse(state.isDesktopWorldEnabled); XCTAssertFalse(state.finderDiagnostics.hasRead)
    }
    @MainActor func testGroupPasteMoveEraseAndUndoRedoAreSingleOperations() throws {
        let state = app(), editor = EditorSession(); defer { state.shutdown() }
        let original = state.library, camera = state.desktopCamera
        let pair = try CircuitBlueprint.capture(name: "Pair", components: [p(0): CircuitComponent(kind: .button), p(1): CircuitComponent(kind: .dust)])
        editor.beginPaste(state, blueprint: pair)
        editor.click(at: point(p(12,8), editor), size: editor.viewport, appState: state)
        let pasted = state.selectedDocument.circuit
        XCTAssertEqual(editor.selection(state), [p(12,8), p(13,8)])
        editor.beginMove(state)
        editor.click(at: point(p(16,9), editor), size: editor.viewport, appState: state)
        XCTAssertNil(state.selectedDocument.circuit.components[p(12,8)])
        XCTAssertEqual(state.selectedDocument.circuit.components[p(16,9)]?.kind, .button)
        editor.undo(state); XCTAssertEqual(state.selectedDocument.circuit, pasted)
        editor.undo(state, redo: true)
        XCTAssertEqual(state.selectedDocument.circuit.components[p(17,9)]?.kind, .dust)
        editor.undo(state)
        editor.undo(state); XCTAssertEqual(state.library.worlds, original.worlds)
        XCTAssertEqual(state.desktopCamera, camera); XCTAssertEqual(state.library.activeAreaID, original.activeAreaID)
        XCTAssertFalse(state.finderDiagnostics.hasRead)
        editor.undo(state, redo: true)
        editor.selectAll(state)
        editor.deleteSelection(state); XCTAssertTrue(state.selectedDocument.circuit.components.isEmpty)
        editor.undo(state); XCTAssertEqual(state.selectedDocument.circuit, pasted)
    }
    @MainActor func testFailedGroupPastePreservesCircuitAndHistoryAndCanRetry() throws {
        let state = app(), editor = EditorSession(); defer { state.shutdown() }
        let before = state.library
        let pair = try CircuitBlueprint.capture(name: "Pair", components: [p(0): CircuitComponent(kind: .button), p(1): CircuitComponent(kind: .dust)])
        editor.beginPaste(state, blueprint: pair)
        editor.click(at: point(p(13,3), editor), size: editor.viewport, appState: state)
        XCTAssertEqual(state.library, before); XCTAssertFalse(state.canUndoCircuit); XCTAssertNotNil(editor.pendingPlacement)
        editor.click(at: point(p(13,8), editor), size: editor.viewport, appState: state)
        XCTAssertNil(editor.pendingPlacement); XCTAssertTrue(state.canUndoCircuit)
        XCTAssertTrue(state.undoCircuit()); XCTAssertEqual(state.library, before)
    }
    @MainActor func testRotationIsOneEditAndHistoryStaysOwnedByEachWorld() throws {
        let state = app(), editor = EditorSession(); defer { state.shutdown() }
        let template = try CircuitBlueprint.capture(name: "Repeater", components: [p(0): CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: .four)])
        editor.beginPaste(state, blueprint: template)
        editor.click(at: point(p(12,8), editor), size: editor.viewport, appState: state)
        editor.rotateSelection(state)
        XCTAssertEqual(state.selectedDocument.circuit.components[p(12,8)]?.direction, .south)
        XCTAssertTrue(state.undoCircuit()); XCTAssertEqual(state.selectedDocument.circuit.components[p(12,8)]?.direction, .east)
        let original = state.selectedWorldID
        XCTAssertTrue(state.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        editor.syncSelectedWorld(state); XCTAssertFalse(state.canUndoCircuit); XCTAssertNil(editor.pendingPlacement)
        XCTAssertTrue(state.selectWorld(original)); XCTAssertTrue(state.canUndoCircuit)
        XCTAssertTrue(state.undoCircuit()); XCTAssertNil(state.selectedDocument.circuit.components[p(12,8)])
    }
    @MainActor func testHistoryCoversInspectorChangesAndErasingSavedOnLever() throws {
        let state = app(); defer { state.shutdown() }
        let before = state.selectedDocument
        XCTAssertTrue(state.configureRepeater(at: DemoCircuit.repeater, direction: .west, delay: .two))
        XCTAssertTrue(state.undoCircuit()); XCTAssertEqual(state.selectedDocument, before)
        XCTAssertTrue(state.undoCircuit(redo: true)); XCTAssertEqual(state.selectedDocument.circuit.components[DemoCircuit.repeater]?.repeaterDelay, .two)
        var circuit = state.selectedDocument.circuit
        circuit.components[p(12,8)] = CircuitComponent(kind: .lever)
        XCTAssertTrue(state.replaceEditorCircuit(circuit, levers: [p(12,8)]))
        XCTAssertTrue(state.eraseCircuitComponent(at: p(12,8)))
        XCTAssertFalse(state.selectedDocument.activeLevers.contains(p(12,8)))
        XCTAssertTrue(state.undoCircuit()); XCTAssertTrue(state.selectedDocument.activeLevers.contains(p(12,8)))
    }
    @MainActor func testTestModeAndRunningWorldRejectGroupChangesAndUndo() throws {
        let state = app(), editor = EditorSession(testScheduler: ManualCircuitTickScheduler()); defer { editor.stopTesting(); state.shutdown() }
        state.placeCircuitComponent(CircuitComponent(kind: .dust), at: p(12,8))
        let before = state.library
        editor.selectedTile = p(12,8); editor.startTesting(state)
        editor.deleteSelection(state); editor.undo(state); editor.rotateSelection(state)
        XCTAssertEqual(state.library, before)
        editor.stopTesting(); state.setDesktopRunning(true)
        XCTAssertFalse(state.canUndoCircuit); XCTAssertFalse(state.undoCircuit())
        XCTAssertFalse(state.replaceEditorCircuit(CircuitWorld()))
        XCTAssertEqual(state.library, before)
    }
    @MainActor func testBlueprintSaveReloadFailureAndClipboardRoundTripUseIsolatedStorage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CircuitBlueprintStore(fileURL: root.appendingPathComponent("blueprints.json")), library = BlueprintLibrary(store: store)
        let blueprint = try CircuitBlueprint.capture(name: "Reusable", components: [p(0): CircuitComponent(kind: .repeater, direction: .west, repeaterDelay: .three)])
        XCTAssertTrue(library.save(blueprint))
        XCTAssertEqual(BlueprintLibrary(store: store).saved, library.saved)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        try EditorCircuitClipboard.write(blueprint, to: pasteboard)
        XCTAssertEqual(try EditorCircuitClipboard.read(from: pasteboard), blueprint)
        pasteboard.setData(Data("{}".utf8), forType: EditorCircuitClipboard.type)
        XCTAssertThrowsError(try EditorCircuitClipboard.read(from: pasteboard))
        let failing = BlueprintFailingStore(), other = BlueprintLibrary(store: failing)
        XCTAssertTrue(other.save(blueprint)); let saved = other.saved
        failing.fails = true; XCTAssertFalse(other.save(blueprint)); XCTAssertEqual(other.saved, saved)
        XCTAssertFalse(other.delete(saved[0].id)); XCTAssertEqual(other.saved, saved)
        XCTAssertTrue(library.delete(library.saved[0].id)); XCTAssertTrue(try store.load().blueprints.isEmpty)
    }
    @MainActor func testCorruptBlueprintLibraryIsPreservedAndCannotBeOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = CircuitBlueprintStore(fileURL: root.appendingPathComponent("blueprints.json"))
        let invalid = Data("not a library".utf8); try invalid.write(to: store.fileURL)
        let library = BlueprintLibrary(store: store)
        XCTAssertFalse(library.save(BlueprintLibrary.examples[0]))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), invalid)
    }
    @MainActor func testEveryExampleValidatesAndPulseGeneratorActuallyPulses() throws {
        let examples = BlueprintLibrary.examples
        XCTAssertEqual(examples.count, 3)
        for example in examples {
            try example.validate()
            XCTAssertTrue(example.circuit.components.values.filter { $0.kind == .output }.allSatisfy { $0.outputAction == .none })
        }
        var test = EditorCircuitTest(worldID: UUID(), circuit: examples[2].circuit, levers: [])
        for _ in 0..<200 { test.advance() }
        XCTAssertGreaterThan(test.outputPulses.values.reduce(0, +), 1)
    }
}
