import AppKit
import Darwin
import SpriteKit
import XCTest
@testable import RedstoneDesktop

private final class StabilityStore: WorldLibraryStoring {
    var document: WorldLibraryDocument
    var fails = false
    init(_ document: WorldLibraryDocument) { self.document = document }
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        try document.validate(); _ = try WorldLibraryStore.encodedData(document)
        self.document = document
    }
}
@MainActor private final class StabilityBuildPresenter: DesktopBuildPresenting {
    func show() {}
    func close() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {}
}
@MainActor private final class StabilityFinder: DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem] { [] }
}

final class StabilityTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RedstoneStabilityTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func nearLimit(_ document: WorldDocument = WorldDocument(terrainProfile: .legacyFixtureV1)) throws -> WorldLibraryDocument {
        var library = WorldLibraryDocument(world: document)
        let size = try WorldLibraryStore.encodedData(library).count
        library.worlds[0].name += String(repeating: "a", count: WorldLibraryStore.maximumBytes - size)
        XCTAssertEqual(try WorldLibraryStore.encodedData(library).count, WorldLibraryStore.maximumBytes)
        try library.validate()
        return library
    }
    private var screen: ScreenDescriptor {
        ScreenDescriptor(id: "stability", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
    }

    @MainActor
    func testRepeatedBlueprintPastesRejectWholeOversizedEditAndKeepUndoAndDisk() throws {
        let root = try temporaryDirectory()
        let store = WorldLibraryStore(fileURL: root.appendingPathComponent("library.json"), legacyFileURL: root.appendingPathComponent("world.json"))
        var document = WorldDocument()
        for y in 0..<60 { for x in 0..<100 { document.terrainOverrides[WorldCoordinate(x: x, y: y)] = Tile(terrain: .grass) } }
        try store.save(WorldLibraryDocument(world: document))
        let state = AppState(libraryStore: store, autosaveDelay: .seconds(3600))
        defer { state.shutdown() }
        let cells = Dictionary(uniqueKeysWithValues: (0..<3000).map { (WorldCoordinate(x: $0 % 100, y: $0 / 100), CircuitComponent(kind: .button)) })
        let blueprint = try CircuitBlueprint.capture(name: "Large real blueprint", components: cells)
        let first = try BlueprintPlacement.applying(blueprint, at: WorldCoordinate(x: 0, y: 0), to: state.editorWorld)
        XCTAssertTrue(state.replaceEditorCircuit(first.circuit))
        let accepted = state.library, world = state.editorWorld, revision = state.editHistoryRevision
        let second = try BlueprintPlacement.applying(blueprint, at: WorldCoordinate(x: 0, y: 30), to: world)
        XCTAssertFalse(state.replaceEditorCircuit(second.circuit))
        XCTAssertTrue(state.developerPlacementStatus.contains("2 MB"))
        XCTAssertEqual(state.library, accepted); XCTAssertEqual(state.editorWorld, world)
        XCTAssertEqual(state.desktopWorld, world); XCTAssertEqual(state.simulator.world, world.circuit)
        XCTAssertEqual(state.editHistoryRevision, revision)
        XCTAssertTrue(state.saveWorldNow()); XCTAssertEqual(try store.load(), accepted)
        XCTAssertTrue(state.undoCircuit()); XCTAssertTrue(state.selectedDocument.circuit.components.isEmpty)
        XCTAssertTrue(state.undoCircuit(redo: true)); XCTAssertEqual(state.library, accepted)
    }

    @MainActor
    func testRejectedMetadataKeepsSelectionAndShorteningNamesFreesSpace() throws {
        let store = StabilityStore(try nearLimit()), state = AppState(libraryStore: store, autosaveDelay: .seconds(3600))
        defer { state.shutdown() }
        let original = state.library, worldID = state.selectedWorldID, areaID = state.selectedAreaID
        XCTAssertFalse(state.createWorld(name: "Another world", generation: WorldGenerationSettings(seed: 42)))
        XCTAssertFalse(state.saveArea(name: "Another area", camera: state.selectedAreaCamera))
        XCTAssertFalse(state.renameWorld(worldID, name: state.selectedDocument.name + "more"))
        XCTAssertFalse(state.renameArea(areaID, name: String(repeating: "x", count: 2000)))
        var lighting = state.selectedDocument.lighting; lighting.mode = .night
        XCTAssertFalse(state.updateWorldLighting(worldID, settings: lighting))
        XCTAssertEqual(state.library, original)
        XCTAssertEqual(state.selectedWorldID, worldID); XCTAssertEqual(state.selectedAreaID, areaID)
        XCTAssertTrue(state.saveWorldNow()); XCTAssertEqual(store.document, original)
        // Shortening an existing name frees space; ordinary world/area creation works again.
        XCTAssertTrue(state.renameWorld(worldID, name: "Small"))
        XCTAssertTrue(state.createWorld(name: "Another world", generation: WorldGenerationSettings(seed: 42)))
        XCTAssertTrue(state.saveArea(name: "Another area", camera: state.selectedAreaCamera))
        XCTAssertTrue(state.saveWorldNow())
    }

    @MainActor
    func testCircuitLimitIsAggregateAcrossIndependentWorlds() throws {
        var first = WorldDocument(name: "First"), second = WorldDocument(name: "Second")
        for index in 0..<4000 {
            let point = WorldCoordinate(x: index % 100, y: index / 100)
            first.terrainOverrides[point] = Tile(terrain: .grass)
            second.terrainOverrides[point] = Tile(terrain: .grass)
        }
        var library = WorldLibraryDocument(world: first)
        library.worlds.append(second)
        library.areas.append(SavedArea(name: "Second home", worldID: second.id, camera: SavedArea.homeCamera))
        let store = StabilityStore(library), state = AppState(libraryStore: store, autosaveDelay: .seconds(3600))
        defer { state.shutdown() }
        let circuit = CircuitWorld(components: Dictionary(uniqueKeysWithValues: (0..<2000).map {
            (WorldCoordinate(x: $0 % 100, y: $0 / 100), CircuitComponent(kind: .button))
        }))
        XCTAssertTrue(state.replaceEditorCircuit(circuit))
        XCTAssertTrue(state.selectWorld(second.id))
        second.circuit = circuit
        // The second world is valid and fits alone; the complete library does not.
        XCTAssertLessThan(try WorldLibraryStore.encodedData(WorldLibraryDocument(world: second)).count, WorldLibraryStore.maximumBytes)
        let original = state.library, revision = state.editHistoryRevision
        XCTAssertFalse(state.replaceEditorCircuit(circuit))
        XCTAssertEqual(state.library, original); XCTAssertEqual(state.editHistoryRevision, revision)
        XCTAssertTrue(state.editorWorld.circuit.components.isEmpty)
        XCTAssertTrue(state.saveWorldNow()); XCTAssertEqual(store.document, original)
    }

    @MainActor
    func testOrdinaryPlacementAndConfigurationRejectWithoutLeakingPreviewHistoryOrSound() throws {
        var document = WorldDocument(terrainProfile: .legacyFixtureV1)
        let repeater = WorldCoordinate(x: 10, y: 9), output = WorldCoordinate(x: 11, y: 9)
        document.circuit.components[repeater] = CircuitComponent(kind: .repeater, direction: .east)
        document.circuit.components[output] = CircuitComponent(kind: .output, outputAction: .none)
        let store = StabilityStore(try nearLimit(document)), player = RecordingSoundPlayer()
        let state = AppState(libraryStore: store, autosaveDelay: .seconds(3600), soundPlayer: player)
        defer { state.shutdown() }
        let original = state.library, world = state.editorWorld, revision = state.editHistoryRevision
        XCTAssertEqual(state.placeCircuitComponent(CircuitComponent(kind: .dust), at: WorldCoordinate(x: 12, y: 9)), .rejected(.libraryFull))
        XCTAssertFalse(state.configureRepeater(at: repeater, direction: .north, delay: .four))
        XCTAssertFalse(state.configureOutput(at: output, mode: .executeOccupant))
        XCTAssertEqual(state.library, original); XCTAssertEqual(state.editorWorld, world)
        XCTAssertEqual(state.editHistoryRevision, revision); XCTAssertFalse(state.canUndoCircuit)
        XCTAssertEqual(player.sounds, [.invalidPlacement])
        XCTAssertTrue(state.eraseCircuitComponent(at: output))
        XCTAssertTrue(state.undoCircuit()); XCTAssertEqual(state.library, original)
        XCTAssertTrue(state.saveWorldNow())
    }

    @MainActor
    func testDesktopBuildPlacementDustAndTerrainRejectWithoutChangingEitherWorld() throws {
        let store = StabilityStore(try nearLimit()), player = RecordingSoundPlayer(), screen = screen
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), libraryStore: store, autosaveDelay: .seconds(3600), soundPlayer: player,
            buildControllerFactory: { _, _, _ in StabilityBuildPresenter() }, finderReferenceProviding: { screen })
        defer { state.shutdown() }
        XCTAssertTrue(state.enterDesktopBuildMode())
        let session = try XCTUnwrap(state.buildSession), original = state.library, world = state.desktopWorld
        let tile = WorldCoordinate(x: 10, y: 9), rect = session.mapper.screenRect(forTile: tile)
        state.buildClick(at: CGPoint(x: rect.midX, y: rect.midY), sessionID: session.id)
        XCTAssertTrue(session.status.contains("2 MB"))
        var stroke = DustStroke(document: state.selectedDocument)
        try stroke.extend(to: tile)
        XCTAssertFalse(state.applyDustStroke(stroke, buildSessionID: session.id))
        XCTAssertFalse(state.applyTerrain(brush: .sand, tiles: [tile], buildSessionID: session.id))
        XCTAssertEqual(state.library, original); XCTAssertEqual(state.editorWorld, world); XCTAssertEqual(state.desktopWorld, world)
        XCTAssertEqual(state.editHistoryRevision, 0); XCTAssertTrue(player.sounds.isEmpty)
        XCTAssertTrue(state.saveWorldNow()); XCTAssertEqual(store.document, original)
    }

    @MainActor
    func testDesktopLeverRefusesUnsaveableStateBeforePlayingToggleSound() async throws {
        var document = WorldDocument(terrainProfile: .legacyFixtureV1)
        let lever = WorldCoordinate(x: 10, y: 3)
        document.circuit.components[lever] = CircuitComponent(kind: .lever)
        let store = StabilityStore(try nearLimit(document)), player = RecordingSoundPlayer(), screen = screen
        let finder = FinderDiagnosticsModel(provider: StabilityFinder())
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), finderDiagnostics: finder,
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture") },
            tickScheduler: ManualCircuitTickScheduler(), libraryStore: store, autosaveDelay: .seconds(3600), soundPlayer: player,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        await finder.readItems(); state.toggleDesktopWorld()
        let original = state.library, simulator = state.simulator
        state.handleCircuitClick(lever); await state.activationTask?.value
        XCTAssertTrue(state.lastActionResult.contains("2 MB"))
        XCTAssertEqual(state.library, original); XCTAssertEqual(state.simulator, simulator)
        XCTAssertTrue(player.sounds.isEmpty); XCTAssertTrue(state.saveWorldNow())
    }

    func testSparseOversizedLibraryLegacyBlueprintAndImportAreRefusedWithoutModifyingFile() throws {
        let root = try temporaryDirectory(), url = root.appendingPathComponent("oversized.json")
        try Data().write(to: url)
        let writer = try FileHandle(forWritingTo: url)
        try writer.truncate(atOffset: 64 * 1024 * 1024); try writer.close()
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertThrowsError(try WorldLibraryStore(fileURL: url, legacyFileURL: root.appendingPathComponent("missing.json")).load())
        XCTAssertThrowsError(try WorldStore(fileURL: url).load())
        XCTAssertThrowsError(try CircuitBlueprintStore(fileURL: url).load())
        XCTAssertThrowsError(try LibraryImport.read(from: url))
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(before[.size] as? NSNumber, after[.size] as? NSNumber)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
    }

    func testBoundedReaderAcceptsExactLimitAndRejectsDirectoriesAndPipesWithoutBlocking() throws {
        let root = try temporaryDirectory(), url = root.appendingPathComponent("small.json")
        let bytes = Data(repeating: 42, count: 100)
        try bytes.write(to: url)
        XCTAssertEqual(try BoundedFileReader.read(url, maximumBytes: 100), bytes)
        XCTAssertThrowsError(try BoundedFileReader.read(url, maximumBytes: 99))
        XCTAssertThrowsError(try BoundedFileReader.read(root, maximumBytes: 100))
        let pipe = root.appendingPathComponent("not-a-save")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try BoundedFileReader.read(pipe, maximumBytes: 100))
        XCTAssertNil(try WorldStore(fileURL: root.appendingPathComponent("missing.json")).load())
    }

    @MainActor
    func testCancelQuitKeepsFailedSnapshotAndRetrySavesIt() async throws {
        let store = StabilityStore(WorldLibraryDocument()), state = AppState(libraryStore: store, autosaveDelay: .seconds(3600))
        defer { store.fails = false; state.shutdown() }
        XCTAssertTrue(state.renameSelectedWorld("Unsaved changes"))
        let latest = state.library
        store.fails = true
        let coordinator = QuitSaveCoordinator()
        let cancelled = await coordinator.resolve(save: { state.saveWorldNow() }, decide: { .cancel }, saveRecovery: { XCTFail("Cancel must not export"); return false })
        XCTAssertFalse(cancelled); XCTAssertFalse(coordinator.isDeciding)
        XCTAssertEqual(state.library, latest); XCTAssertNotEqual(store.document, latest)
        var prompts = 0
        let retried = await coordinator.resolve(save: { state.saveWorldNow() }, decide: { prompts += 1; store.fails = false; return .retry }, saveRecovery: { XCTFail("Retry must not export"); return false })
        XCTAssertTrue(retried); XCTAssertEqual(prompts, 1); XCTAssertEqual(store.document, latest)
    }

    @MainActor
    func testRecoveryCopyAllowsQuitOnlyAfterVerifiedWriteAndIsImportable() async throws {
        let store = StabilityStore(WorldLibraryDocument()), state = AppState(libraryStore: store, autosaveDelay: .seconds(3600))
        defer { store.fails = false; state.shutdown() }
        XCTAssertTrue(state.renameSelectedWorld("Recovery")); store.fails = true
        let coordinator = QuitSaveCoordinator(), root = try temporaryDirectory(), url = root.appendingPathComponent("recovery.json")
        let failed = await coordinator.resolve(save: { state.saveWorldNow() }, decide: { .recoveryCopy }, saveRecovery: {
            do { try state.saveRecoveryCopy(to: root); return true } catch { return false }
        })
        XCTAssertFalse(failed); XCTAssertNotEqual(store.document, state.library)
        let cancelledPanel = await coordinator.resolve(save: { state.saveWorldNow() }, decide: { .recoveryCopy }, saveRecovery: { false })
        XCTAssertFalse(cancelledPanel)
        let saved = await coordinator.resolve(save: { state.saveWorldNow() }, decide: { .recoveryCopy }, saveRecovery: {
            do { try state.saveRecoveryCopy(to: url); return true } catch { XCTFail("\(error)"); return false }
        })
        XCTAssertTrue(saved); XCTAssertEqual(try LibraryImport.read(from: url), state.library)
        XCTAssertNotEqual(store.document, state.library, "Recovery is independent of the failing destination")
    }

    @MainActor
    func testEmergencyCopyCanPreserveOldOversizedInMemoryLibrary() throws {
        var library = try nearLimit()
        library.worlds[0].name += String(repeating: "x", count: 1000)
        let state = AppState(libraryStore: StabilityStore(library), autosaveDelay: .seconds(3600))
        defer { state.shutdown() }
        let url = try temporaryDirectory().appendingPathComponent("large-recovery.json")
        XCTAssertThrowsError(try LibraryExportDocument(library: library).encodedData())
        try state.saveRecoveryCopy(to: url)
        let restored = try JSONDecoder().decode(WorldLibraryDocument.self, from: BoundedFileReader.read(url, maximumBytes: 16 * 1024 * 1024))
        XCTAssertEqual(restored, library)
        XCTAssertTrue(state.renameSelectedWorld("Repaired")); XCTAssertTrue(state.saveWorldNow())
    }

    @MainActor
    func testQuitWithNoPendingChangesDoesNotAskAndTestHostHasNoOwnerWriter() async {
        let state = AppStartup.makeState(); defer { state.shutdown() }
        let coordinator = QuitSaveCoordinator()
        let result = await coordinator.resolve(save: { state.saveWorldNow() }, decide: { XCTFail("No unsaved data"); return .cancel }, saveRecovery: { XCTFail(); return false })
        XCTAssertTrue(result)
        XCTAssertFalse(state.canSaveWorld, "The app test host is isolated from owner data")
    }

    @MainActor
    func testSceneResizeKeepsOwnedLayersAndEditorOverlaysAttachedOnce() throws {
        let screen = screen, mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: SavedArea.homeCamera)
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let owned = Dictionary(uniqueKeysWithValues: scene.children.compactMap { node in node.name.map { ($0, node) } })
        let overlay = SKNode(); overlay.name = "editor-owned-overlay"; scene.addChild(overlay)
        var settings = DiagnosticOverlaySettings(); settings.chunkBoundaries = true
        scene.setDiagnosticOverlays(settings)
        let view = SKView(frame: screen.frame)
        view.presentScene(scene)
        defer { view.presentScene(nil) }
        for index in 0..<80 {
            let size = CGSize(width: 640 + index % 3 * 8, height: 480 + index % 2 * 8)
            view.frame = CGRect(origin: .zero, size: size)
            scene.size = size
            let viewport = ScreenDescriptor(id: screen.id, frame: CGRect(origin: .zero, size: size), backingScale: 1)
            let camera = CameraState(worldOrigin: WorldPoint(x: Double(index) / 8, y: -Double(index) / 8), pointsPerTile: 64)
            scene.updateViewport(screen: viewport, mapper: try CoordinateMapper(canvasFrame: viewport.frame, camera: camera))
            for (name, node) in owned {
                XCTAssertTrue(scene.childNode(withName: name) === node)
                XCTAssertTrue(node.parent === scene)
                XCTAssertEqual(scene.children.filter { $0.name == name }.count, 1)
            }
            XCTAssertTrue(overlay.parent === scene)
            XCTAssertEqual(scene.childNode(withName: "checker")?.children.count, 2)
            XCTAssertEqual(scene.children.count, 12)
        }
    }
}
