import AppKit
import XCTest
@testable import RedstoneDesktop

private final class MemoryWorldStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    var saves: [WorldLibraryDocument] = []
    var fails = false
    func load() throws -> WorldLibraryDocument? {
        if fails { throw WorldStoreError.invalidDocument("Test read failure") }
        return document
    }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw WorldStoreError.invalidDocument("Test write failure") }
        saves.append(document)
        self.document = document
    }
}

final class PersistenceTests: XCTestCase {
    private func cell(_ x: Int, _ y: Int = 7) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    private func temporaryStore() throws -> WorldStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return WorldStore(fileURL: directory.appendingPathComponent("support/world.json"))
    }

    func testLegacyFixtureMigratesWithoutChangingIdentityCircuitOrProtectedTerrain() throws {
        let original = LegacyWorldDocument()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["formatVersion"] = 1
        json.removeValue(forKey: "generation")
        let migrated = try JSONDecoder().decode(LegacyWorldDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.formatVersion, 2)
        XCTAssertEqual(migrated.id, original.id)
        XCTAssertEqual(migrated.circuit, original.circuit)
        XCTAssertEqual(migrated.camera, original.camera)
        let world = try migrated.restoredWorld()
        XCTAssertEqual(world.tiles, EditorConstructionArea.makeWorld().tiles)
        XCTAssertEqual(world.generation, WorldGenerationSettings(seed: 2026))
        XCTAssertNil(world.tile(at: WorldCoordinate(x: 14, y: 5)))
    }

    func testGeneratedPlacementsSaveAndRestoreWithoutPersistingBaseTiles() throws {
        var document = LegacyWorldDocument()
        let generator = try WorldGenerator(settings: document.generation)
        let target = try XCTUnwrap((32..<128).map { WorldCoordinate(x: $0, y: 32) }.first {
            let tile = generator.tile(at: $0)
            return !tile.terrain.definition.isLiquid && tile.decoration == nil
        })
        document.circuit.components[target] = CircuitComponent(kind: .output)
        let store = try temporaryStore()
        try store.save(document)
        XCTAssertEqual(try store.load(), document)
        XCTAssertEqual(try document.restoredWorld().tile(at: target), generator.tile(at: target))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        XCTAssertNil(json["tiles"])
        XCTAssertNotNil(json["generation"])
        document.generation.generationVersion = 99
        XCTAssertThrowsError(try document.restoredWorld())
    }

    func testDocumentRoundTripPreservesIdentityCameraCircuitAndLeverPositions() throws {
        var document = LegacyWorldDocument()
        document.camera.worldOrigin = WorldPoint(x: -42.25, y: 10.75)
        document.circuit.components[cell(10)] = CircuitComponent(kind: .lever)
        document.circuit.components[cell(12)] = CircuitComponent(kind: .repeater, direction: .west, repeaterDelay: .four)
        document.activeLevers = [cell(10)]
        let data = try JSONEncoder().encode(document)
        let restored = try JSONDecoder().decode(LegacyWorldDocument.self, from: data)
        XCTAssertEqual(restored, document)
        XCTAssertEqual(try restored.restoredWorld().tiles, EditorConstructionArea.makeWorld().tiles)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("tiles"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Finder"))
    }

    func testDocumentRejectsFutureFormatFixtureInvalidCameraPlacementAndLeverState() throws {
        var invalid = LegacyWorldDocument()
        invalid.formatVersion = 99
        XCTAssertThrowsError(try invalid.restoredWorld())
        invalid = LegacyWorldDocument(); invalid.fixtureVersion = 99
        XCTAssertThrowsError(try invalid.restoredWorld())
        for scale in [0, -1, Double.infinity, Double.nan, 129] {
            invalid = LegacyWorldDocument(); invalid.camera.pointsPerTile = scale
            XCTAssertThrowsError(try invalid.restoredWorld())
        }
        invalid = LegacyWorldDocument(); invalid.camera.worldOrigin.x = .nan
        XCTAssertThrowsError(try invalid.restoredWorld())
        invalid = LegacyWorldDocument(); invalid.circuit.components[cell(14, 3)] = CircuitComponent(kind: .dust)
        XCTAssertThrowsError(try invalid.restoredWorld())
        invalid = LegacyWorldDocument(); invalid.circuit.components[cell(10, 5)] = CircuitComponent(kind: .output)
        XCTAssertThrowsError(try invalid.restoredWorld())
        invalid = LegacyWorldDocument(); invalid.activeLevers = [DemoCircuit.button]
        XCTAssertThrowsError(try invalid.restoredWorld())
    }

    func testStoreCreatesSupportDirectoryAndAtomicallyReplacesWholeDocument() throws {
        let store = try temporaryStore()
        XCTAssertNil(try store.load())
        var document = LegacyWorldDocument()
        try store.save(document)
        document.circuit.components.removeAll()
        try store.save(document)
        XCTAssertEqual(try store.load(), document)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path)
        XCTAssertEqual(files, ["world.json"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        XCTAssertEqual(object["formatVersion"] as? Int, 2)
    }

    func testFailedValidationPreservesExistingFile() throws {
        let store = try temporaryStore()
        try store.save(LegacyWorldDocument())
        let before = try Data(contentsOf: store.fileURL)
        var invalid = LegacyWorldDocument(); invalid.formatVersion = 99
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
    }

    func testMalformedTruncatedAndFutureJSONAreNotTreatedAsMissing() throws {
        let store = try temporaryStore()
        try store.save(LegacyWorldDocument())
        for text in ["{", "null", "{}", "garbage"] {
            try Data(text.utf8).write(to: store.fileURL)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try String(contentsOf: store.fileURL, encoding: .utf8), text)
        }
        var future = LegacyWorldDocument(); future.formatVersion = 99
        try JSONEncoder().encode(future).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }

    func testStoreReportsFileSystemFailureAndPreservesBlockingFile() throws {
        let store = try temporaryStore()
        let parent = store.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("existing file".utf8)
        try original.write(to: parent)
        XCTAssertThrowsError(try store.save(LegacyWorldDocument()))
        XCTAssertEqual(try Data(contentsOf: parent), original)
        XCTAssertThrowsError(try store.load())
    }

    func testStoreRejectsOversizedJSONAndInvalidComponentConfiguration() throws {
        let store = try temporaryStore()
        try store.save(LegacyWorldDocument())
        try Data(repeating: 32, count: 2_000_001).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        var document = LegacyWorldDocument()
        document.circuit = CircuitWorld(components: [cell(10): CircuitComponent(kind: .repeater)])
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        try Data(json.replacingOccurrences(of: "\"repeaterDelay\":1", with: "\"repeaterDelay\":9").utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        try Data(json.replacingOccurrences(of: "\"north\"", with: "\"diagonal\"").utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }

    @MainActor
    func testDebounceCoalescesNewestSnapshotAndFlushCancelsDelayedWrite() async throws {
        let store = MemoryWorldStore()
        var messages: [String] = []
        let saver = WorldAutosaver(store: store, delay: .milliseconds(40)) { messages.append($0) }
        var first = WorldLibraryDocument(); first.worlds[0].name = "first"
        var latest = first; latest.worlds[0].name = "latest"
        saver.schedule(first); saver.schedule(latest)
        XCTAssertTrue(store.saves.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.saves, [latest])
        XCTAssertNil(saver.pending)
        saver.schedule(first); saver.flush()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.saves, [latest, first])
        XCTAssertEqual(messages.last, "Saved.")
    }

    @MainActor
    func testSaveFailureRetainsLatestSnapshotForRetry() {
        let store = MemoryWorldStore()
        var status = ""
        let saver = WorldAutosaver(store: store, delay: .seconds(60)) { status = $0 }
        store.fails = true
        var document = WorldLibraryDocument(); document.worlds[0].name = "latest"
        saver.schedule(document); saver.flush()
        XCTAssertEqual(saver.pending, document)
        XCTAssertTrue(status.contains("Save failed"))
        store.fails = false; saver.flush()
        XCTAssertEqual(store.saves, [document])
        XCTAssertNil(saver.pending)
    }

    @MainActor
    func testAppEditsSaveOnShutdownAndReopenWithoutEnablingDesktop() throws {
        let store = try temporaryStore()
        try store.save(LegacyWorldDocument())
        let legacySource = try Data(contentsOf: store.fileURL)
        let libraryStore = WorldLibraryStore(fileURL: store.fileURL.deletingLastPathComponent().appendingPathComponent("library.json"), legacyFileURL: store.fileURL)
        let app = AppState(libraryStore: libraryStore, autosaveDelay: .seconds(60))
        XCTAssertTrue(app.placeCircuitComponent(CircuitComponent(kind: .repeater, direction: .south, repeaterDelay: .three), at: cell(10)).isAllowed)
        XCTAssertTrue(app.configureRepeater(at: cell(10), direction: .west, delay: .four))
        XCTAssertTrue(app.eraseCircuitComponent(at: DemoCircuit.button))
        app.shutdown() // flush even within debounce window
        XCTAssertEqual(try Data(contentsOf: store.fileURL), legacySource)
        let reopened = AppState(libraryStore: libraryStore)
        XCTAssertEqual(reopened.desktopWorld, app.desktopWorld)
        XCTAssertEqual(reopened.desktopCamera, app.desktopCamera)
        XCTAssertFalse(reopened.isDesktopWorldEnabled)
        XCTAssertTrue(reopened.simulator.poweredTiles.isEmpty)
        XCTAssertFalse(reopened.finderDiagnostics.hasRead)
        XCTAssertEqual(reopened.persistenceStatus, "Library restored. Desktop World starts disabled.")
        reopened.shutdown()
    }

    @MainActor
    func testCorruptLoadUsesFixtureAndBlocksOverwriteEvenAfterEditingAndShutdown() throws {
        let store = try temporaryStore()
        try store.save(LegacyWorldDocument())
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: store.fileURL)
        let app = AppState(libraryStore: WorldLibraryStore(fileURL: store.fileURL.deletingLastPathComponent().appendingPathComponent("library.json"), legacyFileURL: store.fileURL))
        XCTAssertTrue(app.desktopWorld.circuit.components.isEmpty)
        XCTAssertFalse(app.canSaveWorld)
        XCTAssertTrue(app.persistenceStatus.contains("Saved files preserved"))
        app.placeCircuitComponent(CircuitComponent(kind: .dust), at: cell(10))
        app.saveWorldNow(); app.shutdown()
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }

    @MainActor
    func testRejectedPlacementDoesNotScheduleSaveAndPatchResetIsPersisted() {
        let store = MemoryWorldStore()
        let app = AppState(libraryStore: store, autosaveDelay: .seconds(60))
        app.placeCircuitComponent(CircuitComponent(kind: .dust), at: cell(14, 3))
        app.saveWorldNow()
        XCTAssertTrue(store.saves.isEmpty)
        app.placeCircuitComponent(CircuitComponent(kind: .dust), at: cell(10, 3))
        app.placeCircuitComponent(CircuitComponent(kind: .output), at: cell(10))
        app.resetDeveloperPlacements(); app.saveWorldNow()
        XCTAssertNil(store.document?.worlds[0].circuit.components[cell(10, 3)])
        XCTAssertEqual(store.document?.worlds[0].circuit.components[cell(10)]?.kind, .output)
        app.shutdown()
    }

    @MainActor
    func testSavedLeverPositionsResumeOnlyAfterExplicitEnableAndFreshFinderRead() async throws {
        let store = MemoryWorldStore()
        var document = LegacyWorldDocument(); document.activeLevers = [DemoCircuit.lever]
        store.document = try WorldLibraryDocument(legacy: document)
        let provider = PersistenceItemProvider()
        let opener = FixtureItemOpener()
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 1)
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, libraryStore: store,
            finderReferenceProviding: { screen })
        defer { app.shutdown() }
        XCTAssertTrue(app.simulator.activeLevers.isEmpty)
        XCTAssertEqual(provider.calls, 0)
        app.toggleDesktopWorld()
        XCTAssertEqual(app.simulator.activeLevers, [DemoCircuit.lever])
        app.advanceCircuitTick()
        XCTAssertTrue(opener.urls.isEmpty) // no initial read permission
        await app.finderDiagnostics.readItems()
        app.handleCircuitClick(DemoCircuit.lever)
        await app.activationTask?.value
        app.advanceCircuitTick()
        app.saveWorldNow()
        XCTAssertTrue(try XCTUnwrap(store.document).worlds[0].activeLevers.isEmpty)
        app.handleCircuitClick(DemoCircuit.lever)
        await app.activationTask?.value
        app.advanceCircuitTick()
        await app.activationTask?.value
        app.shutdown()
        XCTAssertEqual(try XCTUnwrap(store.document).worlds[0].activeLevers, [DemoCircuit.lever])
        XCTAssertTrue(app.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(app.simulator.activeLevers.isEmpty)
    }
}

@MainActor
private final class PersistenceItemProvider: DesktopItemProviding {
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] { calls += 1; return [] }
}
