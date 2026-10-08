import AppKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

private final class AreaUpdateStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    var fails = false
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw WorldStoreError.invalidDocument("Test write failure") }
        try document.validate(); self.document = document
    }
}

final class AreaUpdateTests: XCTestCase {
    @MainActor
    private func state(_ store: AreaUpdateStore = AreaUpdateStore(), events: FakeGlobalMouseEventMonitor = FakeGlobalMouseEventMonitor()) -> AppState {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: events, tickScheduler: ManualCircuitTickScheduler(),
            libraryStore: store, autosaveDelay: .seconds(3600), finderReferenceProviding: { screen })
    }

    @MainActor
    func testUpdateReplacesOnlyCameraKeepsIdentityBuildsCountAndDesktopAssignment() throws {
        let store = AreaUpdateStore(), app = state(store), editor = EditorSession()
        defer { app.shutdown() }
        let active = app.library.activeAreaID, desktop = app.desktopCamera
        app.saveArea(name: "Editable bookmark", camera: SavedArea.homeCamera)
        let before = app.library, original = app.selectedArea, circuit = app.selectedDocument.circuit
        editor.syncSelectedWorld(app)
        editor.pan(by: CGSize(width: -480, height: 240), size: editor.viewport)
        editor.zoom(by: 0.5)
        let proposed = editor.proposedDesktopCamera(app)
        XCTAssertEqual(proposed.pointsPerTile, original.camera.pointsPerTile)
        XCTAssertTrue(editor.updateArea(app))
        XCTAssertEqual(app.library.areas.count, before.areas.count)
        XCTAssertEqual(app.selectedArea.id, original.id); XCTAssertEqual(app.selectedArea.name, original.name)
        XCTAssertEqual(app.selectedArea.worldID, original.worldID); XCTAssertEqual(app.selectedArea.camera, proposed)
        XCTAssertEqual(app.library.worlds, before.worlds); XCTAssertEqual(app.selectedDocument.circuit, circuit)
        XCTAssertEqual(app.library.activeAreaID, active); XCTAssertEqual(app.desktopCamera, desktop)
        XCTAssertEqual(store.document, app.library)
        XCTAssertFalse(app.isDesktopWorldEnabled); XCTAssertFalse(app.finderDiagnostics.hasRead)
        let reopened = state(store)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.library.areas.first { $0.id == original.id }?.camera, proposed)
    }

    @MainActor
    func testUpdatingStoppedAssignedAreaPreparesCameraAndRestoresBeforeExplicitStart() {
        let store = AreaUpdateStore(), app = state(store)
        let id = app.library.activeAreaID, world = app.desktopWorld
        let camera = CameraState(worldOrigin: WorldPoint(x: -20, y: 9), pointsPerTile: 64)
        XCTAssertTrue(app.updateSelectedArea(camera: camera))
        XCTAssertEqual(app.selectedAreaID, id); XCTAssertEqual(app.library.activeAreaID, id)
        XCTAssertEqual(app.desktopCamera, camera); XCTAssertEqual(app.desktopWorld, world)
        XCTAssertFalse(app.isDesktopWorldEnabled); XCTAssertFalse(app.finderDiagnostics.hasRead)
        app.shutdown()
        let reopened = state(store)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.desktopCamera, camera); XCTAssertEqual(reopened.selectedAreaID, id)
        XCTAssertFalse(reopened.isDesktopWorldEnabled)
        reopened.toggleDesktopWorld()
        XCTAssertTrue(reopened.isDesktopWorldEnabled); XCTAssertEqual(reopened.desktopCamera, camera)
    }

    @MainActor
    func testRunningActiveAreaRefusesUpdateButAnotherBookmarkOfSameWorldCanUpdate() {
        let store = AreaUpdateStore()
        store.document!.worlds[0].activeLevers = [WorldCoordinate(x: 2, y: 5)]
        let events = FakeGlobalMouseEventMonitor(), app = state(store, events: events)
        defer { app.shutdown() }
        let active = app.selectedAreaID
        app.toggleDesktopWorld(); app.advanceCircuitTick()
        let before = app.library, simulator = app.simulator, camera = app.desktopCamera
        let proposed = CameraState(worldOrigin: WorldPoint(x: 6, y: -2), pointsPerTile: 64)
        XCTAssertFalse(app.updateSelectedArea(camera: proposed)); XCTAssertEqual(app.library, before)
        app.saveArea(name: "Other view", camera: SavedArea.homeCamera)
        XCTAssertTrue(app.updateSelectedArea(camera: proposed))
        XCTAssertEqual(app.activeWorldID, app.selectedWorldID)
        XCTAssertEqual(app.library.activeAreaID, active); XCTAssertEqual(app.desktopCamera, camera)
        XCTAssertEqual(app.simulator, simulator); XCTAssertTrue(app.isDesktopWorldEnabled)
        XCTAssertEqual(events.callbacks.count, 1); XCTAssertTrue(events.removedTokens.isEmpty)
    }

    @MainActor
    func testFailedUpdateKeepsPreviousBookmarkAndPreparedCameraAndNeverQueuesRetry() {
        let store = AreaUpdateStore(), app = state(store)
        defer { app.shutdown() }
        let before = app.library, camera = app.desktopCamera
        let proposed = CameraState(worldOrigin: WorldPoint(x: 10, y: 4), pointsPerTile: 64)
        store.fails = true
        XCTAssertFalse(app.updateSelectedArea(camera: proposed))
        XCTAssertEqual(app.library, before); XCTAssertEqual(app.desktopCamera, camera)
        store.fails = false; app.saveWorldNow()
        XCTAssertEqual(store.document, before)
        XCTAssertTrue(app.updateSelectedArea(camera: proposed)); XCTAssertEqual(store.document?.activeArea?.camera, proposed)
    }

    @MainActor
    func testPendingSaveFailurePreservesCameraAndInvalidPreviewAndScaleUpdatesAreRejected() {
        let store = AreaUpdateStore(), app = state(store), editor = EditorSession()
        defer { app.shutdown() }
        app.saveArea(name: "Pending", camera: SavedArea.homeCamera)
        let before = app.library
        store.fails = true
        XCTAssertFalse(app.updateSelectedArea(camera: CameraState(worldOrigin: WorldPoint(x: 10, y: 0), pointsPerTile: 64)))
        XCTAssertEqual(app.library, before)
        store.fails = false; app.saveWorldNow(); XCTAssertEqual(store.document, before)
        XCTAssertFalse(app.updateSelectedArea(camera: CameraState(worldOrigin: WorldPoint(x: .nan, y: 0), pointsPerTile: 64)))
        XCTAssertFalse(app.updateSelectedArea(camera: CameraState(worldOrigin: .init(x: 0, y: 0), pointsPerTile: 32)))
        editor.seedText = "42"; editor.previewSeed()
        XCTAssertFalse(editor.updateArea(app)); XCTAssertEqual(app.library, before)
    }

    @MainActor
    func testContextRenameTargetsClickedIDsWithoutChangingEditorSelectionOrCamera() {
        let app = state(), editor = EditorSession()
        defer { app.shutdown() }
        app.saveArea(name: "Target", camera: SavedArea.homeCamera)
        let targetArea = app.selectedAreaID, targetWorld = app.selectedWorldID
        app.createWorld(name: "Browsing", generation: WorldGenerationSettings(seed: 42))
        editor.syncSelectedWorld(app); editor.pan(by: CGSize(width: -400, height: 80), size: editor.viewport)
        let selected = app.selectedAreaID, camera = editor.camera
        let request = LibrarySheetRequest(kind: .renameWorld, targetID: targetWorld)
        XCTAssertEqual(request.targetID, targetWorld)
        XCTAssertTrue(app.renameWorld(targetWorld, name: "Clicked world"))
        XCTAssertTrue(app.renameArea(targetArea, name: "Clicked area"))
        XCTAssertEqual(app.library.world(id: targetWorld)?.name, "Clicked world")
        XCTAssertEqual(app.library.areas.first { $0.id == targetArea }?.name, "Clicked area")
        XCTAssertEqual(app.selectedDocument.name, "Browsing")
        XCTAssertEqual(app.selectedAreaID, selected); XCTAssertEqual(editor.camera, camera)
        let sheet = NSHostingView(rootView: LibrarySheetView(kind: request.kind, appState: app, editor: editor, targetID: request.targetID))
        XCTAssertGreaterThanOrEqual(sheet.fittingSize.width, 420)
        app.toggleDesktopWorld()
        XCTAssertFalse(app.renameWorld(targetWorld, name: "Locked active world"))
        XCTAssertTrue(app.renameWorld(app.selectedWorldID, name: "Editable inactive world"))
        XCTAssertFalse(app.renameArea(UUID(), name: "Missing"))
        XCTAssertEqual(app.selectedAreaID, selected)
    }

    @MainActor
    func testMissingDisplayAndLoadBlockedUpdateNeverOverwriteStoredLibrary() throws {
        let unavailable = AppState(screenProviding: { nil })
        let original = unavailable.library
        XCTAssertFalse(unavailable.updateSelectedArea(camera: SavedArea.homeCamera))
        XCTAssertEqual(unavailable.library, original)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.json"), damaged = Data("{broken".utf8)
        try damaged.write(to: file)
        let app = AppState(libraryStore: WorldLibraryStore(fileURL: file, legacyFileURL: folder.appendingPathComponent("world.json")))
        app.saveArea(name: "Temporary", camera: SavedArea.homeCamera)
        let before = app.library
        XCTAssertFalse(app.updateSelectedArea(camera: .init(worldOrigin: .init(x: 1, y: 0), pointsPerTile: 64)))
        app.saveWorldNow(); app.shutdown()
        XCTAssertEqual(app.library, before); XCTAssertEqual(try Data(contentsOf: file), damaged)
    }
}
