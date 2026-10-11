import AppKit
import Combine
import XCTest
@testable import RedstoneDesktop

private final class PolishImportStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    var fails = false
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw WorldStoreError.invalidDocument("Fixture disk failure") }
        self.document = document
    }
}
final class PolishFollowupTests: XCTestCase {
    @MainActor private func app(_ store: PolishImportStore = PolishImportStore()) -> AppState {
        let screen = ScreenDescriptor(id: "polish", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 2)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), libraryStore: store, autosaveDelay: .seconds(3600), finderReferenceProviding: { screen })
    }
    func testImportCopiesCollidingIDsAndPreservesCurrentAssignmentAndAllBuilds() throws {
        let current = try WorldLibraryDocument(legacy: LegacyWorldDocument())
        let data = try JSONEncoder().encode(current)
        let incoming = try LibraryImport.decode(data)
        let merged = try LibraryImport.adding(incoming, to: current)
        XCTAssertEqual(merged.activeAreaID, current.activeAreaID)
        XCTAssertEqual(Array(merged.worlds.prefix(current.worlds.count)), current.worlds)
        XCTAssertEqual(Array(merged.areas.prefix(current.areas.count)), current.areas)
        let copied = try XCTUnwrap(merged.worlds.last)
        XCTAssertNotEqual(copied.id, current.worlds.last?.id)
        XCTAssertEqual(copied.circuit, current.worlds.last?.circuit)
        XCTAssertEqual(merged.areas.last?.worldID, copied.id)
        XCTAssertNotEqual(merged.areas.last?.id, current.areas.last?.id)
        let again = try LibraryImport.adding(incoming, to: merged)
        XCTAssertEqual(Set(again.worlds.map(\.id)).count, again.worlds.count)
        XCTAssertEqual(Set(again.areas.map(\.id)).count, again.areas.count)
    }
    func testImportRejectsInvalidAndOversizedDocuments() throws {
        XCTAssertThrowsError(try LibraryImport.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try LibraryImport.decode(Data(repeating: 32, count: WorldLibraryStore.maximumBytes + 1)))
        var incoming = try WorldLibraryDocument(legacy: LegacyWorldDocument())
        incoming.worlds = []
        XCTAssertThrowsError(try LibraryImport.adding(incoming, to: WorldLibraryDocument(legacy: LegacyWorldDocument())))
    }
    func testFileImportBoundsReadAndValidatesBeforeUse() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = WorldLibraryDocument()
        try JSONEncoder().encode(document).write(to: url)
        XCTAssertEqual(try LibraryImport.read(from: url), document)
        try Data(repeating: 32, count: WorldLibraryStore.maximumBytes + 100).write(to: url)
        XCTAssertThrowsError(try LibraryImport.read(from: url))
    }
    @MainActor func testMenuRefreshesAutomaticallyAfterItsOwnerChanges() async {
        let state = app(); defer { state.shutdown() }
        let model = state.menuPresentation
        let changed = expectation(description: "Menu receives committed name")
        let token = model.$snapshot.dropFirst().sink { snapshot in
            if snapshot.menu.assignedWorld == "Updated automatically" { changed.fulfill() }
        }
        XCTAssertTrue(state.renameWorld(state.selectedWorldID, name: "Updated automatically"))
        await fulfillment(of: [changed], timeout: 1)
        withExtendedLifetime(token) {}
    }
    @MainActor func testImportCommitsBeforePublishingAndDiskFailurePreservesLibrary() throws {
        let store = PolishImportStore(), state = app(store)
        defer { state.shutdown() }
        let before = state.library, selection = state.selectedAreaID, world = state.editorWorld
        store.fails = true
        XCTAssertFalse(state.importLibrary(before)); XCTAssertEqual(state.library, before)
        store.fails = false
        XCTAssertTrue(state.importLibrary(before)); XCTAssertEqual(store.document, state.library)
        XCTAssertEqual(state.selectedAreaID, selection); XCTAssertEqual(state.editorWorld, world)
        XCTAssertEqual(state.library.activeAreaID, before.activeAreaID); XCTAssertFalse(state.isDesktopWorldEnabled)
    }
    @MainActor func testMenuIgnoresUnrelatedAppUpdatesButPublishesMenuChanges() {
        let state = app(); defer { state.shutdown() }
        let model = state.menuPresentation
        var publications = 0
        let token = model.objectWillChange.sink { publications += 1 }
        for _ in 0..<100 { state.objectWillChange.send(); model.refreshNow() }
        XCTAssertEqual(publications, 0)
        let library = state.library
        XCTAssertTrue(state.renameWorld(state.selectedWorldID, name: "Menu world"))
        model.refreshNow()
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(model.snapshot.menu.assignedWorld, "Menu world")
        XCTAssertNotEqual(state.library, library)
        withExtendedLifetime(token) {}
    }
    @MainActor func testNewWorldAndAreaFitDesktopBoundsWithoutChangingAssignment() throws {
        let state = app(), editor = EditorSession(); defer { state.shutdown() }
        let assigned = state.library.activeAreaID
        editor.seedText = "42"; editor.newWorldName = "New landscape"
        XCTAssertTrue(editor.createWorld(state))
        XCTAssertEqual(state.library.activeAreaID, assigned)
        XCTAssertEqual(editor.camera.worldOrigin, state.selectedAreaCamera.worldOrigin)
        let extent = CGSize(width: 1280 / state.selectedAreaCamera.pointsPerTile * editor.camera.pointsPerTile,
                            height: 800 / state.selectedAreaCamera.pointsPerTile * editor.camera.pointsPerTile)
        XCTAssertLessThanOrEqual(extent.width, editor.viewport.width)
        XCTAssertLessThanOrEqual(extent.height, editor.viewport.height)
        editor.pan(by: CGSize(width: -300, height: 80), size: editor.viewport)
        editor.areaName = "Another spot"
        XCTAssertTrue(editor.saveArea(state))
        XCTAssertEqual(editor.camera.worldOrigin, state.selectedAreaCamera.worldOrigin)
        XCTAssertEqual(state.library.activeAreaID, assigned)
    }
    @MainActor func testConfigurationSettersSaveRepeaterImmediatelyAndRespectLock() throws {
        let state = app(), editor = EditorSession(); defer { state.shutdown() }
        let coordinate = try XCTUnwrap(state.editorWorld.circuit.components.first { $0.value.kind == .repeater }?.key)
        let original = try XCTUnwrap(state.editorWorld.circuit.components[coordinate])
        editor.selectedTile = coordinate; editor.direction = original.direction; editor.delay = original.repeaterDelay
        editor.setDirection(.north, appState: state)
        XCTAssertEqual(state.editorWorld.circuit.components[coordinate]?.direction, .north)
        editor.setDelay(.four, appState: state)
        XCTAssertEqual(state.editorWorld.circuit.components[coordinate]?.repeaterDelay, .four)
        XCTAssertEqual(state.editorWorld.circuit.components[coordinate]?.direction, .north)
        editor.seedText = "42"; XCTAssertTrue(editor.previewSeed())
        let saved = state.library
        editor.setDirection(.south, appState: state); editor.setDelay(.one, appState: state)
        XCTAssertEqual(state.library, saved)
    }
    func testOresAreBuildableButCactusesAndTreesStayBlocked() {
        let coordinate = WorldCoordinate(x: 0, y: 0)
        for kind in CircuitComponentKind.allCases where kind != .empty {
            let tile = Tile(terrain: .stone, decoration: .rock)
            var world = World(tiles: [coordinate: tile])
            XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: kind), at: coordinate, in: &world), .allowed)
            XCTAssertEqual(world.tiles[coordinate], tile)
            for terrain in [TerrainID.sand, .grass] {
                var blocked = World(tiles: [coordinate: Tile(terrain: terrain, decoration: .rock)])
                XCTAssertEqual(CircuitPlacement().place(CircuitComponent(kind: kind), at: coordinate, in: &blocked), .rejected(.blockedByDecoration(.rock)))
            }
        }
    }
    @MainActor func testBothToolbarsHaveRecognizableTemplateIcons() throws {
        for name in ["Dust", "Button", "Lever", "Repeater", "Output", "Torch"] {
            let image = try XCTUnwrap(name == "Dust" ? NSImage(named: "MenuLogo") : NSImage(systemSymbolName: ToolIcon.symbol(for: name), accessibilityDescription: nil))
            XCTAssertTrue(image.isTemplate)
            XCTAssertGreaterThan(image.size.width, 0)
        }
        XCTAssertNotNil(NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil))
        XCTAssertNotNil(NSImage(systemSymbolName: "eraser.fill", accessibilityDescription: nil))
    }
}
