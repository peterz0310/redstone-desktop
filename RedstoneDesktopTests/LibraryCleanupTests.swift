import AppKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

private final class CleanupStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    var fails = false
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw WorldStoreError.invalidDocument("Test failure") }
        try document.validate(); self.document = document
    }
}

final class LibraryCleanupTests: XCTestCase {
    @MainActor
    private func state(_ store: CleanupStore = CleanupStore()) -> AppState {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), libraryStore: store, autosaveDelay: .seconds(3600))
    }

    func testPureDeletionGuardsActiveLastAndUnknownIDsWithoutMutatingSource() throws {
        var library = try WorldLibraryDocument(legacy: LegacyWorldDocument())
        let initial = library
        XCTAssertThrowsError(try library.deletingWorld(library.worlds[0].id))
        XCTAssertThrowsError(try library.deletingArea(library.activeAreaID))
        XCTAssertThrowsError(try library.deletingArea(UUID()))
        XCTAssertThrowsError(try library.deletingWorld(UUID()))
        XCTAssertEqual(library, initial)
        let other = WorldDocument(name: "Other", generation: WorldGenerationSettings(seed: 42))
        let home = SavedArea(name: "Home", worldID: other.id, camera: SavedArea.homeCamera)
        library.worlds.append(other); library.areas.append(home)
        XCTAssertThrowsError(try library.deletingArea(home.id))
        XCTAssertThrowsError(try library.deletingWorld(initial.worlds[0].id))
        let removed = try library.deletingWorld(other.id)
        XCTAssertEqual(removed, initial)
        XCTAssertEqual(library.worlds.count, 2)
    }

    @MainActor
    func testDeletingBookmarkPreservesSharedBuildActiveSelectionAndRestart() throws {
        let store = CleanupStore(), app = state(store), editor = EditorSession()
        let active = app.selectedAreaID, world = app.editorWorld
        XCTAssertTrue(app.saveArea(name: "Extra", camera: SavedArea.homeCamera))
        let extra = app.selectedAreaID
        XCTAssertTrue(app.deleteArea(extra))
        editor.syncSelectedWorld(app)
        XCTAssertEqual(app.editorWorld, world)
        XCTAssertEqual(app.selectedAreaID, active)
        XCTAssertEqual(app.library.activeAreaID, active)
        XCTAssertEqual(app.library.areas.count, 1)
        app.shutdown()
        let reopened = state(store)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.library, app.library)
        XCTAssertEqual(reopened.editorWorld, world)
    }

    @MainActor
    func testDeletingInactiveWorldRemovesAllAreasAndFallsBackToActiveWithoutRestart() {
        let store = CleanupStore(), app = state(store), editor = EditorSession()
        defer { app.shutdown() }
        app.toggleDesktopWorld()
        let world = app.desktopWorld, sim = app.simulator, camera = app.desktopCamera, active = app.library.activeAreaID
        XCTAssertTrue(app.createWorld(name: "Disposable", generation: WorldGenerationSettings(seed: 42)))
        let disposable = app.selectedWorldID
        XCTAssertTrue(app.saveArea(name: "Extra", camera: SavedArea.homeCamera))
        XCTAssertTrue(app.deleteWorld(disposable)); editor.syncSelectedWorld(app)
        XCTAssertTrue(app.isDesktopWorldEnabled)
        XCTAssertEqual(app.desktopWorld, world); XCTAssertEqual(app.simulator, sim); XCTAssertEqual(app.desktopCamera, camera)
        XCTAssertEqual(app.selectedAreaID, active); XCTAssertEqual(app.library.activeAreaID, active)
        XCTAssertFalse(app.library.areas.contains { $0.worldID == disposable })
        XCTAssertFalse(app.library.worlds.contains { $0.id == disposable })
        XCTAssertEqual(store.document, app.library)
    }

    @MainActor
    func testFailedDeletionAndLaterSaveNeverDeleteOrChangeSelection() {
        let store = CleanupStore(), app = state(store)
        defer { app.shutdown() }
        app.createWorld(name: "Keep me", generation: WorldGenerationSettings(seed: 42)); app.saveWorldNow()
        let id = app.selectedWorldID, before = app.library, selected = app.selectedAreaID
        store.fails = true
        XCTAssertFalse(app.deleteWorld(id))
        XCTAssertEqual(app.library, before); XCTAssertEqual(app.selectedAreaID, selected)
        store.fails = false; app.saveWorldNow()
        XCTAssertEqual(store.document, before)
        XCTAssertTrue(app.deleteWorld(id))
        XCTAssertNil(app.library.world(id: id))
    }

    @MainActor
    func testDeletionFlushFailureRetainsPendingConfigurationButNeverQueuesDeletion() {
        let store = CleanupStore(), app = state(store)
        defer { app.shutdown() }
        app.createWorld(name: "Pending", generation: WorldGenerationSettings(seed: 42))
        let before = app.library
        store.fails = true
        XCTAssertFalse(app.deleteWorld(app.selectedWorldID))
        XCTAssertEqual(app.library, before)
        store.fails = false; app.saveWorldNow()
        XCTAssertEqual(store.document, before)
    }

    @MainActor
    func testDeletingUnselectedBookmarkKeepsBrowsingAndDisabledActiveRecordsAreProtected() {
        let app = state()
        defer { app.shutdown() }
        let active = app.library.activeAreaID
        app.saveArea(name: "One", camera: SavedArea.homeCamera)
        let one = app.selectedAreaID
        app.saveArea(name: "Two", camera: SavedArea.homeCamera)
        let two = app.selectedAreaID
        XCTAssertTrue(app.deleteArea(one))
        XCTAssertEqual(app.selectedAreaID, two)
        XCTAssertFalse(app.deleteArea(active)); XCTAssertFalse(app.deleteWorld(app.activeWorldID))
        XCTAssertEqual(app.selectedAreaID, two)
        XCTAssertEqual(app.library.activeAreaID, active)
    }

    @MainActor
    func testLoadBlockedDeletionPreservesDamagedLibraryFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json"), damaged = Data("{broken".utf8)
        try damaged.write(to: url)
        let store = WorldLibraryStore(fileURL: url, legacyFileURL: folder.appendingPathComponent("world.json"))
        let app = AppState(libraryStore: store)
        app.createWorld(name: "Unsaved", generation: WorldGenerationSettings(seed: 42))
        let before = app.library
        XCTAssertFalse(app.deleteWorld(app.selectedWorldID))
        app.saveWorldNow(); app.shutdown()
        XCTAssertEqual(app.library, before)
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    @MainActor
    func testPreviewUsesSavedCameraCircuitsAndBoundedDisplayAspectWithoutSideEffects() throws {
        let app = state()
        defer { app.shutdown() }
        let document = app.selectedDocument, initial = app.library, sim = app.simulator
        let a = AreaPreviewSnapshot(document: document, camera: SavedArea.homeCamera, displaySize: CGSize(width: 1440, height: 900))
        let image = try XCTUnwrap(AreaPreviewRenderer.image(for: a))
        XCTAssertLessThanOrEqual(image.size.width, 144); XCTAssertLessThanOrEqual(image.size.height, 88)
        XCTAssertEqual(image.size.width / image.size.height, 1.6, accuracy: 0.001)
        let far = AreaPreviewSnapshot(document: document, camera: CameraState(worldOrigin: WorldPoint(x: -100, y: 300), pointsPerTile: 64), displaySize: a.displaySize)
        XCTAssertNotEqual(image.tiffRepresentation, AreaPreviewRenderer.image(for: far)?.tiffRepresentation)
        var empty = document; empty.circuit.components = [:]
        let emptyImage = try XCTUnwrap(AreaPreviewRenderer.image(for: AreaPreviewSnapshot(document: empty, camera: a.camera, displaySize: a.displaySize)))
        XCTAssertNotEqual(image.tiffRepresentation, emptyImage.tiffRepresentation)
        let tall = try XCTUnwrap(AreaPreviewRenderer.image(for: AreaPreviewSnapshot(document: document, camera: a.camera, displaySize: CGSize(width: 900, height: 1600))))
        XCTAssertEqual(tall.size.height, 88); XCTAssertEqual(tall.size.width, 49.5)
        XCTAssertNil(AreaPreviewRenderer.image(for: AreaPreviewSnapshot(document: document, camera: a.camera, displaySize: .zero)))
        XCTAssertEqual(app.library, initial); XCTAssertEqual(app.simulator, sim)
        XCTAssertFalse(app.finderDiagnostics.hasRead); XCTAssertFalse(app.isDesktopWorldEnabled)
    }

    @MainActor
    func testReorganizedEditorAndFocusedSheetsHostWithoutDesktopOrFinder() async throws {
        let app = state(), editor = EditorSession()
        defer { app.shutdown() }
        let host = NSHostingView(rootView: EditorView(appState: app).environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 850)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        for kind in [LibrarySheet.newWorld, .saveArea, .renameWorld, .renameArea, .deleteWorld, .deleteArea] {
            let sheet = NSHostingView(rootView: LibrarySheetView(kind: kind, appState: app, editor: editor))
            XCTAssertGreaterThanOrEqual(sheet.fittingSize.width, 420)
        }
        for _ in 0..<10 { await Task.yield() }
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/redstone-editor19c.png"))
        }
        XCTAssertFalse(app.isDesktopWorldEnabled); XCTAssertFalse(app.finderDiagnostics.hasRead)
    }
}
