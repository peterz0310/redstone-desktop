import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

private final class LibraryMemoryStore: WorldLibraryStoring {
    var document: WorldLibraryDocument?
    var saves: [WorldLibraryDocument] = []
    var fails = false
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw WorldStoreError.invalidDocument("Test write failure") }
        try document.validate()
        self.document = document
        saves.append(document)
    }
}

@MainActor
private final class LibraryItemProvider: DesktopItemProviding {
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] { calls += 1; return [] }
}

final class WorldLibraryTests: XCTestCase {
    private func temporaryStore() -> WorldLibraryStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return WorldLibraryStore(fileURL: directory.appendingPathComponent("library.json"), legacyFileURL: directory.appendingPathComponent("world.json"))
    }

    private func sharedDryCell(_ seeds: [UInt64]) throws -> WorldCoordinate {
        let generators = try seeds.map { try WorldGenerator(settings: WorldGenerationSettings(seed: $0)) }
        return try XCTUnwrap((-64...128).flatMap { y in (32...160).map { WorldCoordinate(x: $0, y: y) } }.first { coordinate in
            generators.allSatisfy { generator in
                let tile = generator.tile(at: coordinate)
                return !tile.terrain.definition.isLiquid && tile.decoration == nil
            }
        })
    }

    func testFormatThreeRoundTripHasNoCameraOrGeneratedTilesAndFreshWorldIsEmpty() throws {
        let document = WorldDocument(name: "  Seed 42  ", generation: WorldGenerationSettings(seed: 42))
        let world = try document.restoredWorld()
        XCTAssertEqual(document.name, "Seed 42")
        XCTAssertEqual(document.formatVersion, 3)
        XCTAssertTrue(world.tiles.isEmpty)
        XCTAssertTrue(world.unspecifiedTiles.isEmpty)
        XCTAssertTrue(world.circuit.components.isEmpty)
        XCTAssertEqual(world.tile(at: DemoCircuit.button), try WorldGenerator(settings: document.generation).tile(at: DemoCircuit.button))
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(WorldDocument.self, from: data), document)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["camera"]); XCTAssertNil(json["tiles"]); XCTAssertNil(json["fixtureVersion"])
    }

    func testMigrateBothLegacyVersionsPreservesSourceBytesAndConfigurationIdempotently() throws {
        for version in [1, 2] {
            let store = temporaryStore()
            var legacy = LegacyWorldDocument()
            legacy.name = "  Owner circuit  "; legacy.generation = WorldGenerationSettings(seed: 42)
            legacy.camera = CameraState(worldOrigin: WorldPoint(x: -42.25, y: 81.5), pointsPerTile: 48)
            let lever = WorldCoordinate(x: 10, y: 7)
            legacy.circuit.components[lever] = CircuitComponent(kind: .lever)
            legacy.activeLevers = [lever]
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
            json["formatVersion"] = version
            if version == 1 { json.removeValue(forKey: "generation") }
            let source = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            try FileManager.default.createDirectory(at: store.legacyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: store.legacyFileURL)
            let library = try XCTUnwrap(store.load()), document = try XCTUnwrap(library.worlds.first)
            XCTAssertEqual(document.id, legacy.id); XCTAssertEqual(document.name, legacy.name)
            XCTAssertEqual(document.generation.seed, version == 1 ? 2026 : 42)
            XCTAssertEqual(document.circuit, legacy.circuit); XCTAssertEqual(document.activeLevers, legacy.activeLevers)
            XCTAssertEqual(document.terrainProfile, .legacyFixtureV1)
            XCTAssertEqual(library.activeArea?.camera, legacy.camera)
            XCTAssertEqual(library.activeArea?.name, "Desktop")
            XCTAssertEqual(try document.restoredWorld().tiles, EditorConstructionArea.makeWorld().tiles)
            XCTAssertEqual(try Data(contentsOf: store.legacyFileURL), source)
            XCTAssertEqual(try store.load(), library)
            XCTAssertEqual(try Data(contentsOf: store.legacyFileURL), source)
        }
    }

    func testExistingLibraryIsAuthoritativeEvenWithMalformedLegacyBackup() throws {
        let store = temporaryStore(), library = WorldLibraryDocument()
        try store.save(library)
        try Data("{invalid backup".utf8).write(to: store.legacyFileURL)
        XCTAssertEqual(try store.load(), library)
        let original = try Data(contentsOf: store.fileURL)
        try Data("{invalid library".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertNotEqual(try Data(contentsOf: store.fileURL), original)
        XCTAssertEqual(try String(contentsOf: store.fileURL, encoding: .utf8), "{invalid library")
    }

    func testMigrationFailurePreservesLegacyAndDoesNotTreatCorruptSourceAsMissing() throws {
        let store = temporaryStore()
        try WorldStore(fileURL: store.legacyFileURL).save(LegacyWorldDocument())
        let source = try Data(contentsOf: store.legacyFileURL)
        // Directory at library.json is an unreadable authoritative destination, not missing.
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.legacyFileURL), source)
        try FileManager.default.removeItem(at: store.fileURL)
        try Data("{broken".utf8).write(to: store.legacyFileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try String(contentsOf: store.legacyFileURL, encoding: .utf8), "{broken")
    }

    func testMigrationWriteFailureFromLibrarySizeLimitPreservesSourceWithoutDestination() throws {
        let store = temporaryStore()
        var legacy = LegacyWorldDocument()
        // Compact legacy fits exactly; the whole pretty-printed library exceeds the bound.
        let overhead = try JSONEncoder().encode(legacy).count - legacy.name.utf8.count
        legacy.name = String(repeating: "a", count: WorldLibraryStore.maximumBytes - overhead)
        let source = try JSONEncoder().encode(legacy)
        XCTAssertEqual(source.count, WorldLibraryStore.maximumBytes)
        try FileManager.default.createDirectory(at: store.legacyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try source.write(to: store.legacyFileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: store.legacyFileURL), source)
    }

    func testLibraryRejectsDuplicateIDsMissingReferencesAndInvalidVersionsOrNames() throws {
        let valid = WorldLibraryDocument()
        try valid.validate()
        var invalid = valid; invalid.worlds.append(invalid.worlds[0]); XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.areas.append(invalid.areas[0]); XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.activeAreaID = UUID(); XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.areas = [SavedArea(name: "Orphan", worldID: UUID(), camera: SavedArea.homeCamera)]; XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.worlds.append(WorldDocument()); XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.worlds = []; XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.formatVersion = 99; XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.worlds[0].formatVersion = 2; XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.worlds[0].name = " \n "; XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.areas[0].name = ""; XCTAssertThrowsError(try invalid.validate())
        invalid = valid; invalid.areas[0].camera.worldOrigin.x = .nan; XCTAssertThrowsError(try invalid.validate())
        for scale in [15.0, 129, .infinity] {
            invalid = valid; invalid.areas[0].camera.pointsPerTile = scale; XCTAssertThrowsError(try invalid.validate())
        }
        var world = WorldDocument(generation: WorldGenerationSettings(generationVersion: 99, seed: 42))
        XCTAssertThrowsError(try world.restoredWorld())
        world = WorldDocument(); world.activeLevers = [DemoCircuit.button]; XCTAssertThrowsError(try world.restoredWorld())
        let data = try JSONEncoder().encode(valid)
        let unknown = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "procedural", with: "unknownProfile")
        XCTAssertThrowsError(try JSONDecoder().decode(WorldLibraryDocument.self, from: Data(unknown.utf8)))
    }

    func testInvalidAndOversizedWritesPreserveExistingLibraryAndReadsRejectOversize() throws {
        let store = temporaryStore(), valid = WorldLibraryDocument()
        XCTAssertNil(try store.load())
        try store.save(valid)
        let original = try Data(contentsOf: store.fileURL)
        var invalid = valid; invalid.activeAreaID = UUID()
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        invalid = valid; invalid.worlds[0].name = String(repeating: "a", count: 2_000_001)
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        try Data(repeating: 32, count: 2_000_001).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }

    @MainActor
    func testApplicationTestHostStartupHasNoOwnerStore() {
        let app = AppStartup.makeState()
        XCTAssertFalse(app.canSaveWorld)
        XCTAssertFalse(app.isDesktopWorldEnabled)
        XCTAssertFalse(app.finderDiagnostics.hasRead)
        app.shutdown()
    }

    @MainActor
    func testNewInstallationSavesEmptyLibraryAndStartsDisabledWithoutFinder() throws {
        let store = temporaryStore(), provider = LibraryItemProvider()
        let app = AppState(finderDiagnostics: FinderDiagnosticsModel(provider: provider), libraryStore: store)
        defer { app.shutdown() }
        XCTAssertEqual(try store.load(), app.library)
        XCTAssertEqual(app.library.worlds.count, 1)
        XCTAssertEqual(app.library.areas[0].name, "Home")
        XCTAssertTrue(app.editorWorld.circuit.components.isEmpty)
        XCTAssertTrue(app.editorWorld.tiles.isEmpty)
        XCTAssertFalse(app.isDesktopWorldEnabled); XCTAssertEqual(provider.calls, 0)
    }

    @MainActor
    func testIndependentSeedsAndDuplicateSeedsKeepEditsAtCoincidentCoordinatesAndCoalesceSave() throws {
        let store = LibraryMemoryStore()
        let app = AppState(libraryStore: store, autosaveDelay: .seconds(60))
        let initialActive = app.activeWorldID, camera = app.desktopCamera
        let coordinate = try sharedDryCell([42, 2026])
        var ids: [UUID] = []
        for (seed, kind) in [(UInt64(42), CircuitComponentKind.dust), (2026, .output), (42, .repeater)] {
            XCTAssertTrue(app.createWorld(name: "Build \(seed)", generation: WorldGenerationSettings(seed: seed)))
            ids.append(app.selectedWorldID)
            XCTAssertTrue(app.editorWorld.circuit.components.isEmpty)
            XCTAssertTrue(app.placeCircuitComponent(CircuitComponent(kind: kind, direction: .west, repeaterDelay: .four), at: coordinate).isAllowed)
        }
        XCTAssertEqual(Set(ids).count, 3)
        for (id, kind) in zip(ids, [CircuitComponentKind.dust, .output, .repeater]) {
            XCTAssertTrue(app.selectWorld(id))
            XCTAssertEqual(app.editorWorld.circuit.components[coordinate]?.kind, kind)
        }
        XCTAssertEqual(app.activeWorldID, initialActive); XCTAssertEqual(app.desktopCamera, camera)
        XCTAssertTrue(app.desktopWorld.circuit.components.isEmpty)
        XCTAssertEqual(store.saves.count, 1) // only initial empty library; edits still coalesced
        app.shutdown()
        XCTAssertEqual(store.saves.count, 2)
        let reopened = AppState(libraryStore: store)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.library, app.library)
        XCTAssertEqual(reopened.selectedWorldID, initialActive)
        XCTAssertFalse(reopened.isDesktopWorldEnabled)
    }

    @MainActor
    func testRenameEraseRepeaterAndDeveloperResetTargetSelectedWorldOnly() throws {
        let app = AppState()
        let original = app.desktopWorld, active = app.activeWorldID
        XCTAssertTrue(app.createWorld(name: "42", generation: WorldGenerationSettings(seed: 42)))
        let id = app.selectedWorldID, cell = try sharedDryCell([42])
        XCTAssertTrue(app.placeDeveloperComponent(CircuitComponent(kind: .repeater), at: cell).isAllowed)
        XCTAssertTrue(app.configureRepeater(at: cell, direction: .south, delay: .three))
        app.resetDeveloperPlacements() // no legacy patch in a procedural world
        XCTAssertEqual(app.editorWorld.circuit.components[cell]?.direction, .south)
        XCTAssertTrue(app.renameSelectedWorld("  Experiments  "))
        XCTAssertEqual(app.selectedDocument.id, id); XCTAssertEqual(app.selectedDocument.name, "Experiments")
        XCTAssertFalse(app.renameSelectedWorld(" \n "))
        XCTAssertTrue(app.eraseCircuitComponent(at: cell))
        XCTAssertEqual(app.desktopWorld, original)
        XCTAssertTrue(app.selectWorld(active))
        XCTAssertEqual(app.editorWorld, original)
    }

    @MainActor
    func testLiveDesktopKeepsOriginalWorldWhileInactiveWorldCanBeEdited() throws {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        let provider = LibraryItemProvider(), events = FakeGlobalMouseEventMonitor(), opener = FixtureItemOpener()
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: events,
            finderDiagnostics: FinderDiagnosticsModel(provider: provider), tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener)
        let active = app.activeWorldID, original = app.desktopWorld
        XCTAssertTrue(app.createWorld(name: "42", generation: WorldGenerationSettings(seed: 42)))
        let selected = app.selectedWorldID
        app.toggleDesktopWorld()
        defer { app.shutdown() }
        XCTAssertTrue(app.isDesktopWorldEnabled)
        XCTAssertEqual(app.simulator.world, original.circuit)
        XCTAssertEqual(app.activeWorldID, active); XCTAssertEqual(app.selectedWorldID, selected)
        XCTAssertTrue(app.renameSelectedWorld("Renamed"))
        XCTAssertTrue(app.placeCircuitComponent(CircuitComponent(kind: .dust), at: try sharedDryCell([42])).isAllowed)
        XCTAssertTrue(app.selectWorld(active))
        XCTAssertFalse(app.renameSelectedWorld("Locked"))
        XCTAssertFalse(app.placeCircuitComponent(CircuitComponent(kind: .dust), at: WorldCoordinate(x: 10, y: 7)).isAllowed)
        XCTAssertTrue(app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 2026)))
        XCTAssertTrue(app.editorPoweredTiles.isEmpty)
        XCTAssertEqual(app.editorOccupancy.state(at: DemoCircuit.output), .unavailable("This world is not active on the desktop."))
        XCTAssertEqual(provider.calls, 0); XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertEqual(events.callbacks.count, 1)
    }

    @MainActor
    func testNewWorldPreviewIsEmptyEvenForSameSeedAndDirectSeedReplacementIsRefused() throws {
        let app = AppState(), editor = EditorSession(), original = app.library
        editor.seedText = "2026"; XCTAssertTrue(editor.previewSeed())
        XCTAssertTrue(editor.isPreviewing(app))
        XCTAssertTrue(editor.browsingWorld(app).circuit.components.isEmpty)
        XCTAssertTrue(editor.browsingWorld(app).tiles.isEmpty)
        editor.tool = .dust
        editor.click(at: CGPoint(x: 420, y: 300), size: CGSize(width: 800, height: 600), appState: app)
        XCTAssertEqual(app.library, original)
        XCTAssertFalse(editor.activateArea(app))
        editor.newWorldName = "Same seed, new build"
        XCTAssertTrue(editor.createWorld(app))
        XCTAssertNotEqual(app.selectedWorldID, app.activeWorldID)
        XCTAssertEqual(app.selectedDocument.generation.seed, 2026)
        XCTAssertTrue(app.editorWorld.circuit.components.isEmpty)
        XCTAssertFalse(editor.isPreviewing(app))
        XCTAssertTrue(editor.selectWorld(app.activeWorldID, appState: app))
        XCTAssertEqual(app.editorWorld.circuit, original.worlds[0].circuit)
    }

    @MainActor
    func testSelectingWorldResetsEditorStateAndShowsSavedAreaWithoutOtherWorldOccupancy() throws {
        let app = AppState(), editor = EditorSession(), renderer = EditorCanvasRenderer()
        let active = app.activeWorldID
        editor.selectedTile = DemoCircuit.button; editor.hoveredTile = DemoCircuit.output
        editor.pan(by: CGSize(width: -400, height: 80), size: editor.viewport)
        editor.seedText = "42"; editor.newWorldName = "42"; XCTAssertTrue(editor.createWorld(app))
        XCTAssertEqual(editor.camera.worldOrigin, SavedArea.homeCamera.worldOrigin)
        XCTAssertNil(editor.selectedTile); XCTAssertNil(editor.hoveredTile)
        let scene = try XCTUnwrap(renderer.update(appState: app, editor: editor, size: CGSize(width: 800, height: 600)))
        XCTAssertNotNil(scene.childNode(withName: "editor-desktop-viewport/current-desktop"))
        XCTAssertEqual((scene.childNode(withName: "editor-desktop-viewport/current-desktop-label") as? SKLabelNode)?.text, "Saved area")
        editor.showDesktopArea(app)
        XCTAssertEqual(app.selectedWorldID, active)
        XCTAssertEqual(editor.camera.worldOrigin, app.desktopCamera.worldOrigin)
        XCTAssertNotNil(renderer.update(appState: app, editor: editor, size: CGSize(width: 800, height: 600))?.childNode(withName: "editor-desktop-viewport/current-desktop"))
        let host = NSHostingView(rootView: EditorView(appState: app))
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900)
        host.layoutSubtreeIfNeeded()
    }

    @MainActor
    func testDamagedAuthoritativeLibraryBlocksAppWritesEvenAfterMultipleWorldEdits() throws {
        let store = temporaryStore()
        try store.save(WorldLibraryDocument())
        try WorldStore(fileURL: store.legacyFileURL).save(LegacyWorldDocument())
        let damaged = Data("{broken library".utf8)
        try damaged.write(to: store.fileURL)
        let legacy = try Data(contentsOf: store.legacyFileURL)
        let app = AppState(libraryStore: store)
        XCTAssertFalse(app.canSaveWorld)
        XCTAssertTrue(app.persistenceStatus.contains("Saved files preserved"))
        app.createWorld(name: "42", generation: WorldGenerationSettings(seed: 42))
        app.placeCircuitComponent(CircuitComponent(kind: .dust), at: try sharedDryCell([42]))
        app.saveWorldNow(); app.shutdown()
        XCTAssertEqual(try Data(contentsOf: store.fileURL), damaged)
        XCTAssertEqual(try Data(contentsOf: store.legacyFileURL), legacy)
    }

    @MainActor
    func testFailedMultiWorldSaveRetainsLatestSnapshotAndRetries() throws {
        let store = LibraryMemoryStore(), app = AppState(libraryStore: store, autosaveDelay: .seconds(60))
        app.createWorld(name: "42", generation: WorldGenerationSettings(seed: 42))
        app.placeCircuitComponent(CircuitComponent(kind: .dust), at: try sharedDryCell([42]))
        app.createWorld(name: "2026", generation: WorldGenerationSettings(seed: 2026))
        store.fails = true; app.saveWorldNow()
        XCTAssertTrue(app.persistenceStatus.contains("Save failed"))
        XCTAssertEqual(store.document?.worlds.count, 1)
        let latest = app.library
        store.fails = false; app.saveWorldNow()
        XCTAssertEqual(store.document, latest)
        XCTAssertEqual(app.persistenceStatus, "Saved.")
        app.shutdown()
    }
}
