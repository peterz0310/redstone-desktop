import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor private final class TerrainBuildFixture: DesktopBuildPresenting {
    var last: World?
    func show() {}
    func close() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) { last = world }
}
final class TerrainEditingTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 9) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    private func document() -> WorldDocument { WorldDocument(name: "Terrain", terrainProfile: .legacyFixtureV1) }
    @MainActor private func app(_ build: TerrainBuildFixture = TerrainBuildFixture()) -> AppState {
        let screen = ScreenDescriptor(id: "terrain", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), tickScheduler: ManualCircuitTickScheduler(),
            buildControllerFactory: { _, _, _ in build }, finderReferenceProviding: { screen })
    }
    @MainActor private func point(_ coordinate: WorldCoordinate, editor: EditorSession) -> CGPoint {
        let rect = editor.mapper(size: editor.viewport)!.screenRect(forTile: coordinate)
        return CGPoint(x: rect.midX, y: rect.midY)
    }
    func testBrushFootprintsAndBoundedInterpolationHandleNegativeCoordinatesAndOverflow() throws {
        XCTAssertEqual(try TerrainEditing.footprint(center: p(-3), size: 5).count, 25)
        let line = try TerrainEditing.line(from: p(-3, -2), to: p(4, 3))
        XCTAssertEqual(line.first, p(-3, -2)); XCTAssertEqual(line.last, p(4, 3)); XCTAssertEqual(line.count, 8)
        for pair in zip(line, line.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(pair.0.x - pair.1.x), 1); XCTAssertLessThanOrEqual(abs(pair.0.y - pair.1.y), 1)
        }
        XCTAssertThrowsError(try TerrainEditing.line(from: p(Int.min), to: p(Int.max)))
        XCTAssertThrowsError(try TerrainEditing.line(from: p(0), to: p(4096)))
        XCTAssertThrowsError(try TerrainEditing.footprint(center: p(Int.max), size: 3))
        XCTAssertThrowsError(try TerrainEditing.footprint(center: p(0), size: 2))
    }
    func testPaintingCreatesDryBuildableGroundAndClearsDecorations() throws {
        let original = document(), target = p(14, 3)
        XCTAssertEqual(try original.restoredWorld().tile(at: target)?.terrain, .shallowWater)
        let plan = try TerrainEditing.plan(document: original, brush: .grass, tiles: [target])
        XCTAssertEqual(plan.world.tile(at: target), Tile(terrain: .grass))
        XCTAssertEqual(plan.changed, [target])
        XCTAssertEqual(PlacementRules().canPlace(component: CircuitComponent(kind: .dust), at: target, in: plan.world), .allowed)
        XCTAssertTrue(original.terrainOverrides.isEmpty)
    }
    func testWaterAndRestoreProtectCircuitsWithoutRejectingOtherBrushTiles() throws {
        var document = document()
        document.circuit.components[p(16)] = CircuitComponent(kind: .lever)
        document.activeLevers = [p(16)]
        let water = try TerrainEditing.plan(document: document, brush: .deepWater, tiles: [p(16), p(17)])
        XCTAssertEqual(water.protected, [p(16)]); XCTAssertEqual(water.changed, [p(17)])
        XCTAssertEqual(water.world.circuit, document.circuit)
        XCTAssertEqual(water.world.tile(at: p(16)), Tile(terrain: .grass))
        XCTAssertEqual(water.world.tile(at: p(17)), Tile(terrain: .deepWater))
        document.terrainOverrides[p(14, 3)] = Tile(terrain: .grass)
        document.circuit.components[p(14, 3)] = CircuitComponent(kind: .pressurePlate)
        let restore = try TerrainEditing.plan(document: document, brush: .restore, tiles: [p(14, 3)])
        XCTAssertEqual(restore.protected, [p(14, 3)])
        XCTAssertEqual(restore.overrides[p(14, 3)], Tile(terrain: .grass))
    }
    func testClearDecorationAndRestoreRecoverExactlyTheOriginalProfile() throws {
        var document = document()
        let target = p(40)
        document.terrainOverrides[target] = Tile(terrain: .stone, decoration: .rock)
        let clear = try TerrainEditing.plan(document: document, brush: .clearDecorations, tiles: [target])
        XCTAssertEqual(clear.world.tile(at: target), Tile(terrain: .stone))
        document.terrainOverrides = clear.overrides
        let restore = try TerrainEditing.plan(document: document, brush: .restore, tiles: [target])
        XCTAssertNil(restore.overrides[target])
        XCTAssertEqual(restore.world, document.unmodifiedWorld())
        let noop = try TerrainEditing.plan(document: document, brush: .restore, tiles: [p(80)])
        XCTAssertTrue(noop.changed.isEmpty)
        XCTAssertEqual(noop.world.tile(at: p(80)), document.unmodifiedWorld().tile(at: p(80)))
    }
    func testStrokeAccumulatesWithoutGapsAndFailsBeforeExceedingBudget() throws {
        var stroke = TerrainStroke(document: document(), brush: .stone, size: 3)
        try stroke.extend(to: p(10)); try stroke.extend(to: p(20))
        for x in 9...21 { for y in 8...10 { XCTAssertTrue(stroke.tiles.contains(p(x,y))) } }
        let before = stroke.tiles
        XCTAssertThrowsError(try stroke.extend(to: p(5000)))
        XCTAssertEqual(stroke.tiles, before)
        var document = document()
        document.terrainOverrides = Dictionary(uniqueKeysWithValues: (0..<TerrainEditing.maximumSavedTiles).map { (p($0, 50), Tile(terrain: .grass)) })
        XCTAssertThrowsError(try TerrainEditing.plan(document: document, brush: .sand, tiles: [p(-1, 50)]))
        XCTAssertThrowsError(try TerrainEditing.plan(document: document, brush: .grass, tiles: Set((0...4096).map { p($0) })))
    }
    func testVersionThreeDecodesWithoutEditsAndVersionFourPersistsOverrides() throws {
        var original = document(); original.terrainOverrides[p(-5, -7)] = Tile(terrain: .sand)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(WorldDocument.self, from: data)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(try restored.restoredWorld().tile(at: p(-5, -7)), Tile(terrain: .sand))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["formatVersion"] = 3; json.removeValue(forKey: "terrainOverrides")
        let old = try JSONDecoder().decode(WorldDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.formatVersion, 4); XCTAssertTrue(old.terrainOverrides.isEmpty)
        XCTAssertEqual(try old.restoredWorld(), old.unmodifiedWorld())
        json["formatVersion"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(WorldDocument.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testEditedTerrainIncludedInLibraryExportImportAndValidation() throws {
        var document = document(); document.terrainOverrides[p(14, 3)] = Tile(terrain: .grass)
        document.circuit.components[p(14, 3)] = CircuitComponent(kind: .fileSensor)
        let library = WorldLibraryDocument(world: document)
        let incoming = try LibraryImport.decode(JSONEncoder().encode(library))
        let combined = try LibraryImport.adding(incoming, to: WorldLibraryDocument())
        XCTAssertEqual(combined.worlds.last?.terrainOverrides, document.terrainOverrides)
        XCTAssertEqual(combined.worlds.last?.circuit, document.circuit)
        var invalid = document; invalid.terrainOverrides[p(14, 3)] = Tile(terrain: .deepWater)
        XCTAssertThrowsError(try invalid.restoredWorld())
    }
    func testClearingGeneratedDecorationPreservesVisibleGrassAndUndoPreservesCurrentLeverState() throws {
        let document = WorldDocument(generation: WorldGenerationSettings(seed: 42))
        let generator = try WorldGenerator(settings: document.generation)
        let target = try XCTUnwrap((-64...64).flatMap { y in (-64...64).map { p($0,y) } }.first {
            let tile = generator.tile(at: $0); return tile.terrain == .dirt && tile.decoration != nil
        })
        let plan = try TerrainEditing.plan(document: document, brush: .clearDecorations, tiles: [target])
        XCTAssertEqual(plan.world.tile(at: target), Tile(terrain: .grass))
        let lever = p(10), circuit = CircuitWorld(components: [lever: CircuitComponent(kind: .lever)])
        let change = CircuitChange(before: circuit, after: circuit, leversBefore: [], leversAfter: [], terrainAfter: [lever: Tile(terrain: .stone)])
        let (_, levers) = try change.applying(to: circuit, levers: [lever], undo: true)
        XCTAssertEqual(levers, [lever])
        XCTAssertTrue(try change.applyingTerrain(to: [lever: Tile(terrain: .stone)], undo: true).isEmpty)
    }
    @MainActor func testEditorStrokeIsPreviewOnlyUntilReleaseAndUndoIsOneStep() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let original = app.library, desktopCamera = app.desktopCamera
        editor.tool = .terrain; editor.terrainBrush = .sand; editor.terrainBrushSize = 1
        editor.terrainInput(at: point(p(10), editor: editor), size: editor.viewport, phase: .begin, appState: app)
        editor.terrainInput(at: point(p(16), editor: editor), size: editor.viewport, phase: .drag, appState: app)
        XCTAssertEqual(app.library, original)
        XCTAssertEqual(editor.browsingWorld(app).tile(at: p(13)), Tile(terrain: .sand))
        editor.terrainInput(at: point(p(16), editor: editor), size: editor.viewport, phase: .end, appState: app)
        XCTAssertNil(editor.terrainStroke)
        XCTAssertEqual(app.selectedDocument.terrainOverrides.count, 7)
        XCTAssertEqual(app.desktopCamera, desktopCamera)
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.library, original)
        XCTAssertFalse(app.canUndoCircuit)
        XCTAssertTrue(app.undoCircuit(redo: true)); XCTAssertEqual(app.editorWorld.tile(at: p(13)), Tile(terrain: .sand))
        XCTAssertFalse(app.finderDiagnostics.hasRead)
    }
    @MainActor func testStrokeCancellationWorldSwitchAndConcurrentEditRejectWithoutSavingDraft() {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        editor.tool = .terrain
        let original = app.library
        let start = point(p(16), editor: editor)
        editor.terrainInput(at: start, size: editor.viewport, phase: .begin, appState: app)
        editor.clearSelection(); XCTAssertEqual(app.library, original); XCTAssertNil(editor.terrainStroke)
        editor.terrainInput(at: start, size: editor.viewport, phase: .begin, appState: app)
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .button), at: p(16)), .allowed)
        editor.terrainInput(at: start, size: editor.viewport, phase: .end, appState: app)
        XCTAssertTrue(app.selectedDocument.terrainOverrides.isEmpty)
        editor.terrainInput(at: start, size: editor.viewport, phase: .begin, appState: app)
        app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)); editor.syncSelectedWorld(app)
        XCTAssertNil(editor.terrainStroke); XCTAssertTrue(app.selectedDocument.terrainOverrides.isEmpty)
    }
    @MainActor func testRunningAndTestModeBlockTerrainAndNewCircuitsRespectPaintedGround() {
        let app = app(), editor = EditorSession(testScheduler: ManualCircuitTickScheduler()); defer { app.shutdown(); editor.stopTesting() }
        let target = p(14, 3)
        XCTAssertTrue(app.applyTerrain(brush: .grass, tiles: [target]))
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .dust), at: target), .allowed)
        XCTAssertTrue(app.applyTerrain(brush: .shallowWater, tiles: [target]))
        XCTAssertEqual(app.editorWorld.tile(at: target), Tile(terrain: .grass))
        editor.startTesting(app); editor.tool = .terrain
        editor.click(at: point(p(16), editor: editor), size: editor.viewport, appState: app)
        XCTAssertNil(app.selectedDocument.terrainOverrides[p(16)])
        editor.stopTesting(); app.toggleDesktopWorld()
        XCTAssertFalse(app.applyTerrain(brush: .sand, tiles: [p(16)]))
    }
    @MainActor func testTerrainUndoDoesNotChangeUnrelatedLeverStateOrCircuitConfiguration() {
        let app = app(); defer { app.shutdown() }
        let circuit = app.selectedDocument.circuit
        XCTAssertTrue(app.applyTerrain(brush: .stone, tiles: [DemoCircuit.lever]))
        XCTAssertTrue(app.undoCircuit())
        XCTAssertEqual(app.selectedDocument.circuit, circuit)
        XCTAssertEqual(app.selectedDocument.activeLevers, [])
        XCTAssertTrue(app.undoCircuit(redo: true))
        XCTAssertEqual(app.editorWorld.tile(at: DemoCircuit.lever), Tile(terrain: .stone))
    }
    @MainActor func testDesktopStrokeUsesAssignedWorldAndDoesNotSavePreview() throws {
        let presenter = TerrainBuildFixture(), app = app(presenter); defer { app.shutdown() }
        let active = app.activeWorldID
        XCTAssertTrue(app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession), original = app.library
        session.tool = .terrain; session.terrainBrush = .sand; session.terrainBrushSize = 1
        func point(_ x: Int) -> CGPoint { let rect = session.mapper.screenRect(forTile: p(x)); return CGPoint(x: rect.midX, y: rect.midY) }
        app.buildTerrain(at: point(10), phase: .begin, sessionID: session.id)
        app.buildTerrain(at: point(15), phase: .drag, sessionID: session.id)
        XCTAssertEqual(app.library, original)
        XCTAssertEqual(presenter.last?.tile(at: p(12)), Tile(terrain: .sand))
        app.buildTerrain(at: point(15), phase: .end, sessionID: session.id)
        XCTAssertEqual(app.library.world(id: active)?.terrainOverrides.count, 6)
        XCTAssertTrue(app.selectedDocument.terrainOverrides.isEmpty)
        app.exitDesktopBuildMode(); XCTAssertFalse(app.isDesktopWorldEnabled)
    }
    @MainActor func testNativeCanvasDragPaintsAllIntermediateTilesAndEscapeCancelsDraft() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: editor.viewport), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let view = EditorCanvasSurface(frame: CGRect(origin: .zero, size: editor.viewport))
        window.contentView = view; view.editor = editor; view.appState = app
        editor.tool = .terrain; editor.terrainBrush = .stone; editor.terrainBrushSize = 1
        func event(_ type: NSEvent.EventType, _ coordinate: WorldCoordinate) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point(coordinate, editor: editor), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, p(10)))
        view.mouseDragged(with: try event(.leftMouseDragged, p(16)))
        XCTAssertTrue(app.selectedDocument.terrainOverrides.isEmpty)
        view.mouseUp(with: try event(.leftMouseUp, p(16)))
        XCTAssertEqual(app.selectedDocument.terrainOverrides.count, 7)
        view.mouseDown(with: try event(.leftMouseDown, p(17)))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        view.mouseUp(with: try event(.leftMouseUp, p(17)))
        XCTAssertNil(app.selectedDocument.terrainOverrides[p(17)])
    }
    @MainActor func testRendererInvalidatesOnlyEditedChunkAndRetainsUnchangedNodeAndCache() throws {
        let renderer = TerrainChunkRenderer(), layer = SKNode()
        let screen = ScreenDescriptor(id: "chunks", frame: CGRect(x: 0, y: 0, width: 800, height: 600), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0,y: 0), pointsPerTile: 40))
        var world = World(generation: WorldGenerationSettings(seed: 42))
        renderer.render(world, mapper: mapper, screen: screen, viewport: screen.frame, into: layer)
        let before = renderer.metrics, unchanged = try XCTUnwrap(layer.childNode(withName: "chunk:-1,0"))
        world.tiles[p(5)] = Tile(terrain: .sand)
        renderer.render(world, mapper: mapper, screen: screen, viewport: screen.frame, into: layer)
        XCTAssertEqual(renderer.metrics.textureBuilds, before.textureBuilds + 1)
        XCTAssertEqual(renderer.metrics.generatedChunks, before.generatedChunks)
        XCTAssertTrue(layer.childNode(withName: "chunk:-1,0") === unchanged)
    }
}
