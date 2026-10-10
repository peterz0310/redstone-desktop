import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

private final class BrowserBlueprintStore: CircuitBlueprintStoring {
    var document = CircuitBlueprintDocument()
    var fail = false
    func load() throws -> CircuitBlueprintDocument { document }
    func save(_ document: CircuitBlueprintDocument) throws { if fail { throw BlueprintError("Fixture write failed") }; self.document = document }
}
final class BlueprintBrowserContextTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 9) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    @MainActor private func app() -> AppState {
        let screen = ScreenDescriptor(id: "browser", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), tickScheduler: ManualCircuitTickScheduler(), finderReferenceProviding: { screen })
    }
    @MainActor func testSwitchedClockRunsOnlyWhileLeverEnabledAfterSettlingAndRestarts() throws {
        let blueprint = try XCTUnwrap(BlueprintLibrary.examples.first { $0.name == "Switched Pulse Generator" })
        let lever = try XCTUnwrap(blueprint.circuit.components.first { $0.value.kind == .lever }?.key)
        let output = try XCTUnwrap(blueprint.circuit.components.first { $0.value.kind == .output }?.key)
        for turns in 0..<4 {
            var rotated = blueprint
            for _ in 0..<turns { rotated = try rotated.rotatedClockwise() }
            let switchTile = try XCTUnwrap(rotated.circuit.components.first { $0.value.kind == .lever }?.key)
            let outputTile = try XCTUnwrap(rotated.circuit.components.first { $0.value.kind == .output }?.key)
            var simulator = CircuitSimulator(world: rotated.circuit)
            for _ in 0..<50 { _ = simulator.advanceTick() }
            for _ in 0..<100 { XCTAssertTrue(simulator.advanceTick().isEmpty); XCTAssertEqual(simulator.power(at: outputTile), .off) }
            XCTAssertTrue(simulator.toggleLever(at: switchTile))
            var pulses = 0
            for _ in 0..<200 { pulses += simulator.advanceTick().count }
            XCTAssertGreaterThan(pulses, 3)
            XCTAssertTrue(simulator.toggleLever(at: switchTile))
            for _ in 0..<50 { _ = simulator.advanceTick() }
            for _ in 0..<100 { XCTAssertTrue(simulator.advanceTick().isEmpty); XCTAssertEqual(simulator.power(at: outputTile), .off) }
            simulator.toggleLever(at: switchTile)
            pulses = 0
            for _ in 0..<200 { pulses += simulator.advanceTick().count }
            XCTAssertGreaterThan(pulses, 3)
        }
        XCTAssertNotEqual(lever, output)
    }
    @MainActor func testNewExamplesValidateAndDoWhatTheirDescriptionsSay() throws {
        for example in BlueprintLibrary.examples { try example.validate(); XCTAssertNotNil(BlueprintLibrary.description(for: example)) }
        let either = try XCTUnwrap(BlueprintLibrary.examples.first { $0.name == "Either Button" })
        for tile in either.circuit.components.filter({ $0.value.kind == .button }).keys {
            var sim = CircuitSimulator(world: either.circuit); sim.pressButton(at: tile)
            XCTAssertEqual(sim.advanceTick().count, 1)
        }
        let inverter = try XCTUnwrap(BlueprintLibrary.examples.first { $0.name == "Inverted Switch" })
        var sim = CircuitSimulator(world: inverter.circuit)
        let output = try XCTUnwrap(inverter.circuit.components.first { $0.value.kind == .output }?.key)
        let lever = try XCTUnwrap(inverter.circuit.components.first { $0.value.kind == .lever }?.key)
        for _ in 0..<10 { _ = sim.advanceTick() }; XCTAssertGreaterThan(sim.power(at: output), .off)
        sim.toggleLever(at: lever)
        for _ in 0..<10 { _ = sim.advanceTick() }; XCTAssertEqual(sim.power(at: output), .off)
        let pdf = try XCTUnwrap(BlueprintLibrary.examples.first { $0.name == "PDF Detector" })
        XCTAssertEqual(pdf.circuit.components.values.first { $0.kind == .fileSensor }?.sensorFilter, FileSensorFilter(match: .fileExtension, value: "pdf"))
        XCTAssertTrue(BlueprintLibrary.examples.allSatisfy { $0.circuit.components.values.filter { $0.kind == .output }.allSatisfy { $0.outputAction == .none } })
    }
    @MainActor func testBlueprintPreviewsAreCachedDistinctAndBoundedAndDoNotTouchAppState() throws {
        let app = app(), original = app.library; defer { app.shutdown() }
        var data: Set<Data> = []
        for blueprint in BlueprintLibrary.examples {
            let first = BlueprintPreviewImage.image(for: blueprint)
            XCTAssertTrue(first === BlueprintPreviewImage.image(for: blueprint))
            XCTAssertEqual(first.size, CGSize(width: 192, height: 100))
            data.insert(try XCTUnwrap(first.tiffRepresentation))
        }
        let sheet = NSImage(size: CGSize(width: 768, height: 200), flipped: false) { _ in
            for (index, blueprint) in BlueprintLibrary.examples.enumerated() {
                BlueprintPreviewImage.image(for: blueprint).draw(in: CGRect(x: (index % 4) * 192, y: (1 - index / 4) * 100, width: 192, height: 100))
            }
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(sheet.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/redstone-blueprint-previews.png"))
        XCTAssertEqual(data.count, BlueprintLibrary.examples.count)
        XCTAssertEqual(app.library, original); XCTAssertFalse(app.finderDiagnostics.hasRead); XCTAssertNil(app.activationTask)
    }
    @MainActor func testRenamePersistsSameIdentityAndFailurePreservesPriorTemplate() throws {
        let store = BrowserBlueprintStore(), library = BlueprintLibrary(store: store)
        XCTAssertTrue(library.save(BlueprintLibrary.examples[0]))
        let id = try XCTUnwrap(library.saved.first?.id), circuit = library.saved[0].circuit
        XCTAssertTrue(library.rename(id, to: "  Morning circuit  "))
        XCTAssertEqual(library.saved[0].id, id); XCTAssertEqual(library.saved[0].name, "Morning circuit")
        XCTAssertEqual(library.saved[0].circuit, circuit)
        XCTAssertEqual(BlueprintLibrary(store: store).saved, library.saved)
        let before = library.saved
        XCTAssertFalse(library.rename(id, to: "")); XCTAssertEqual(library.saved, before)
        store.fail = true; XCTAssertFalse(library.rename(id, to: "Failed")); XCTAssertEqual(library.saved, before)
    }
    @MainActor func testRightClickRotatesRepeaterSetsDelayAndDeletesWithUndoAndNoActivation() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let tile = p(16)
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .repeater, direction: .east), at: tile), .allowed)
        let before = app.library
        editor.tool = .button; editor.prepareContext(at: tile, appState: app)
        XCTAssertEqual(app.library, before); XCTAssertNil(app.activationTask)
        let options = editor.contextOptions(at: tile, appState: app)
        XCTAssertTrue(options.contains { $0.action == .rotate && $0.enabled })
        XCTAssertEqual(options.filter { if case .delay = $0.action { return true }; return false }.count, 4)
        editor.performContext(.rotate, at: tile, worldID: app.selectedWorldID, appState: app)
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.direction, .south)
        editor.performContext(.delay(.four), at: tile, worldID: app.selectedWorldID, appState: app)
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.repeaterDelay, .four)
        editor.performContext(.saveBlueprint, at: tile, worldID: app.selectedWorldID, appState: app)
        XCTAssertEqual(editor.sidebarTab, .blueprints); XCTAssertTrue(editor.isSavingBlueprint)
        editor.performContext(.delete, at: tile, worldID: app.selectedWorldID, appState: app)
        XCTAssertNil(app.editorWorld.circuit.components[tile]); XCTAssertTrue(app.undoCircuit())
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.repeaterDelay, .four)
        XCTAssertFalse(app.finderDiagnostics.hasRead)
    }
    @MainActor func testDecorationAndTerrainMenuActionsAreUndoableAndPreserveCircuit() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let tile = p(10, 5), before = app.editorWorld.tile(at: tile)
        editor.prepareContext(at: tile, appState: app)
        XCTAssertTrue(editor.contextOptions(at: tile, appState: app).contains { $0.action == .clearDecoration })
        editor.performContext(.clearDecoration, at: tile, worldID: app.selectedWorldID, appState: app)
        XCTAssertNil(app.editorWorld.tile(at: tile)?.decoration)
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.editorWorld.tile(at: tile), before)
        let ground = p(16)
        app.applyTerrain(brush: .sand, tiles: [ground]); app.placeCircuitComponent(CircuitComponent(kind: .button), at: ground)
        editor.prepareContext(at: ground, appState: app)
        editor.performContext(.restoreTerrain, at: ground, worldID: app.selectedWorldID, appState: app)
        XCTAssertEqual(app.editorWorld.tile(at: ground), Tile(terrain: .grass))
        XCTAssertEqual(app.editorWorld.circuit.components[ground]?.kind, .button)
    }
    @MainActor func testRightClickPreservesAGroupAndRotatesAndDeletesItAsSingleUndoOperations() {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let circuit = CircuitWorld(components: [p(16): CircuitComponent(kind: .button), p(17): CircuitComponent(kind: .output, outputAction: .none)])
        XCTAssertTrue(app.replaceEditorCircuit(circuit))
        editor.selectAll(app); editor.prepareContext(at: p(16), appState: app)
        XCTAssertEqual(editor.selection(app).count, 2)
        XCTAssertTrue(editor.contextOptions(at: p(16), appState: app).contains { $0.title == "Delete Selection (2)" })
        editor.performContext(.rotate, at: p(16), worldID: app.selectedWorldID, appState: app)
        XCTAssertEqual(app.editorWorld.circuit.components[p(16,10)]?.kind, .button)
        editor.prepareContext(at: p(16,10), appState: app)
        editor.performContext(.delete, at: p(16,10), worldID: app.selectedWorldID, appState: app)
        XCTAssertTrue(app.editorWorld.circuit.components.isEmpty)
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.editorWorld.circuit.components.count, 2)
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.editorWorld.circuit, circuit)
    }
    @MainActor func testContextActionsAreDisabledDuringTestRuntimeAndRejectStaleWorld() {
        let app = app(), editor = EditorSession(testScheduler: ManualCircuitTickScheduler()); defer { app.shutdown(); editor.stopTesting() }
        let tile = DemoCircuit.button, id = app.selectedWorldID
        editor.prepareContext(at: tile, appState: app)
        XCTAssertFalse(editor.contextOptions(at: tile, appState: app).contains { $0.action == .rotate })
        editor.startTesting(app)
        editor.performContext(.delete, at: tile, worldID: id, appState: app)
        XCTAssertNotNil(app.editorWorld.circuit.components[tile])
        editor.stopTesting(); app.toggleDesktopWorld()
        XCTAssertFalse(editor.contextOptions(at: tile, appState: app).first { $0.action == .delete }!.enabled)
        editor.performContext(.delete, at: tile, worldID: id, appState: app)
        XCTAssertNotNil(app.editorWorld.circuit.components[tile])
        app.shutdown(); app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42))
        let new = app.library
        editor.performContext(.delete, at: tile, worldID: id, appState: app)
        XCTAssertEqual(app.library, new)
    }
    @MainActor func testNativeContextMenuSelectsWithoutPlacingAndCarriesEnabledActions() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: editor.viewport), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let view = EditorCanvasSurface(frame: CGRect(origin: .zero, size: editor.viewport)); view.appState = app; view.editor = editor; window.contentView = view
        let tile = DemoCircuit.repeater, rect = editor.mapper(size: editor.viewport)!.screenRect(forTile: tile)
        editor.tool = .erase
        let before = app.library
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: rect.midX,y: rect.midY), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        var presented: [NSMenu] = []
        view.presentContextMenu = { menu, received, surface in
            XCTAssertTrue(surface === view)
            XCTAssertTrue(received === event)
            presented.append(menu)
        }
        view.rightMouseDown(with: event)
        let menu = try XCTUnwrap(presented.first)
        XCTAssertEqual(presented.count, 1)
        XCTAssertTrue(window.firstResponder === view)
        XCTAssertEqual(editor.selectedTile, tile); XCTAssertEqual(app.library, before)
        XCTAssertTrue(menu.items.contains { $0.title == "Rotate Clockwise" && $0.isEnabled })
        XCTAssertTrue(menu.items.contains { $0.title == "Delete Component" && $0.isEnabled })
    }
    @MainActor func testControlClickPresentsContextWithoutPaintingTerrainOnMouseUp() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: editor.viewport), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let view = EditorCanvasSurface(frame: CGRect(origin: .zero, size: editor.viewport))
        view.appState = app; view.editor = editor; window.contentView = view
        let tile = DemoCircuit.repeater, rect = editor.mapper(size: editor.viewport)!.screenRect(forTile: tile)
        editor.tool = .terrain
        let before = app.library
        var presentations = 0
        view.presentContextMenu = { _, _, _ in presentations += 1 }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: rect.midX, y: rect.midY), modifierFlags: .control, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
        XCTAssertEqual(presentations, 1)
        XCTAssertEqual(editor.selectedTile, tile)
        XCTAssertNil(editor.terrainStroke)
        XCTAssertEqual(app.library, before)
    }

    @MainActor func testInspectOpensOwnTabAndToolsStartWithTwoUtilityRows() {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let before = app.library
        editor.tool = .erase
        editor.prepareContext(at: DemoCircuit.repeater, appState: app)
        editor.performContext(.inspect, at: DemoCircuit.repeater, worldID: app.selectedWorldID, appState: app)
        XCTAssertEqual(editor.sidebarTab, .inspector)
        XCTAssertEqual(editor.tool, .select)
        editor.tool = .terrain
        editor.selectSidebar(.build)
        XCTAssertEqual(editor.tool, .terrain)
        editor.selectSidebar(.inspector)
        XCTAssertEqual(editor.tool, .select)
        XCTAssertEqual(editor.selectedTile, DemoCircuit.repeater)
        XCTAssertEqual(app.library, before)
        XCTAssertEqual(Array(EditorSession.Tool.allCases.prefix(4)), [.select, .region, .erase, .terrain])
        XCTAssertTrue(EditorSession.Tool.allCases.dropFirst(4).allSatisfy { $0.componentKind != nil })
        XCTAssertEqual(EditorSession.SidebarTab.allCases, [.build, .blueprints, .inspector])
    }

    @MainActor func testInspectorChangesPreserveOtherStoredSettingAfterPlacementDefaultsChange() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let tile = DemoCircuit.repeater
        editor.prepareContext(at: tile, appState: app)
        let original = try XCTUnwrap(app.selectedDocument.circuit.components[tile])
        editor.direction = .south
        editor.delay = original.repeaterDelay == .one ? .four : .one
        let newDirection: Direction = original.direction == .north ? .east : .north
        editor.setDirection(newDirection, appState: app)
        XCTAssertEqual(app.selectedDocument.circuit.components[tile]?.repeaterDelay, original.repeaterDelay)
        editor.direction = .south
        editor.setDelay(.three, appState: app)
        XCTAssertEqual(app.selectedDocument.circuit.components[tile]?.direction, newDirection)
        XCTAssertEqual(app.selectedDocument.circuit.components[tile]?.repeaterDelay, .three)
    }

    @MainActor func testToolDescriptionsCoverBothBuildModes() {
        for tool in EditorSession.Tool.allCases { XCTAssertGreaterThan(tool.description.count, 35) }
        for tool in DesktopBuildSession.Tool.allCases { XCTAssertGreaterThan(tool.description.count, 35) }
        XCTAssertEqual(EditorSession.Tool.repeater.description, DesktopBuildSession.Tool.repeater.description)
        XCTAssertEqual(EditorSession.Tool.terrain.description, DesktopBuildSession.Tool.terrain.description)
    }
}
