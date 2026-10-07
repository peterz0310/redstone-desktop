import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

private final class AreaStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    var fails = false
    var didSave: (() -> Void)?
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw WorldStoreError.invalidDocument("Test write failure") }
        try document.validate()
        self.document = document
        didSave?()
    }
}

@MainActor
private final class AreaProvider: DesktopItemProviding {
    var calls = 0
    var wait = false
    var continuation: CheckedContinuation<[DesktopItem], any Error>?
    let item = DesktopItem(id: "area-target", url: URL(fileURLWithPath: "/tmp/area-target"), displayName: "Target", position: CGPoint(x: 480, y: 576), estimatedIconSize: nil, kind: .folder)
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if wait { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return [item]
    }
}

final class SavedAreaTests: XCTestCase {
    @MainActor
    private func state(_ store: AreaStore = AreaStore(), provider: AreaProvider = AreaProvider(), events: FakeGlobalMouseEventMonitor = FakeGlobalMouseEventMonitor(), opener: FixtureItemOpener = FixtureItemOpener()) -> AppState {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: events,
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture desktop") }, tickScheduler: ManualCircuitTickScheduler(),
            itemOpener: opener, libraryStore: store, autosaveDelay: .seconds(3600), finderReferenceProviding: { screen })
    }

    @MainActor
    func testAreasShareWorldBuildAndNamesKeepIDsAndCameras() throws {
        let app = state(), editor = EditorSession()
        defer { app.shutdown() }
        let initial = app.selectedAreaID, active = app.library.activeAreaID
        let cell = WorldCoordinate(x: 10, y: 7)
        XCTAssertTrue(app.placeCircuitComponent(CircuitComponent(kind: .repeater), at: cell).isAllowed)
        editor.areaName = "East"
        editor.pan(by: CGSize(width: -200, height: 0), size: editor.viewport)
        XCTAssertTrue(editor.saveArea(app))
        let east = app.selectedArea, originalCamera = east.camera
        XCTAssertNotEqual(east.id, initial)
        XCTAssertEqual(app.library.activeAreaID, active)
        XCTAssertTrue(app.renameSelectedArea("Workshop"))
        XCTAssertEqual(app.selectedArea.id, east.id)
        XCTAssertEqual(app.selectedArea.camera, originalCamera)
        XCTAssertTrue(editor.selectArea(initial, appState: app))
        XCTAssertEqual(app.editorWorld.circuit.components[cell]?.kind, .repeater)
        XCTAssertTrue(app.configureRepeater(at: cell, direction: .north, delay: .four))
        XCTAssertTrue(editor.selectArea(east.id, appState: app))
        XCTAssertEqual(app.editorWorld.circuit.components[cell]?.direction, .north)
        XCTAssertEqual(editor.camera.worldOrigin, originalCamera.worldOrigin)
        XCTAssertTrue(app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        XCTAssertNil(app.editorWorld.circuit.components[cell])
    }

    @MainActor
    func testInactiveEditingAndBookmarkingLeaveHeldActiveCircuitUntouched() async throws {
        let provider = AreaProvider(), events = FakeGlobalMouseEventMonitor(), app = state(provider: provider, events: events)
        defer { app.shutdown() }
        await app.finderDiagnostics.readItems(); app.toggleDesktopWorld()
        app.handleCircuitClick(DemoCircuit.button); await app.activationTask?.value
        app.advanceCircuitTick()
        let simulator = app.simulator, world = app.desktopWorld, camera = app.desktopCamera
        let active = app.library.activeAreaID, calls = provider.calls
        XCTAssertTrue(app.createWorld(name: "Editable", generation: WorldGenerationSettings(seed: 42)))
        let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: 42))
        let cell = try XCTUnwrap((32..<300).map { WorldCoordinate(x: $0, y: 32) }.first {
            let tile = generator.tile(at: $0)
            return !tile.terrain.definition.isLiquid && tile.decoration == nil
        })
        XCTAssertTrue(app.placeCircuitComponent(CircuitComponent(kind: .repeater), at: cell).isAllowed)
        XCTAssertTrue(app.configureRepeater(at: cell, direction: .south, delay: .four))
        XCTAssertTrue(app.renameSelectedWorld("Edited"))
        XCTAssertTrue(app.saveArea(name: "Bench", camera: SavedArea.homeCamera))
        XCTAssertTrue(app.renameSelectedArea("Bench renamed"))
        XCTAssertTrue(app.eraseCircuitComponent(at: cell))
        app.saveWorldNow()
        XCTAssertEqual(app.simulator, simulator); XCTAssertEqual(app.desktopWorld, world)
        XCTAssertEqual(app.desktopCamera, camera); XCTAssertEqual(app.library.activeAreaID, active)
        XCTAssertEqual(provider.calls, calls); XCTAssertEqual(events.callbacks.count, 1)
        XCTAssertTrue(app.editorPoweredTiles.isEmpty)
        XCTAssertTrue(app.selectArea(active))
        XCTAssertFalse(app.eraseCircuitComponent(at: DemoCircuit.button))
        XCTAssertFalse(app.configureRepeater(at: WorldCoordinate(x: 5, y: 7), direction: .north, delay: .four))
        app.resetDeveloperPlacements()
        XCTAssertEqual(app.desktopWorld, world); XCTAssertEqual(app.simulator, simulator)
    }

    @MainActor
    func testActivationUsesSavedCameraNotPannedDraftAndRestoresDisabledSelection() {
        let store = AreaStore(), app = state(store), editor = EditorSession()
        editor.areaName = "Bookmark"; editor.pan(by: CGSize(width: -400, height: 80), size: editor.viewport)
        XCTAssertTrue(editor.saveArea(app))
        let target = app.selectedArea
        editor.pan(by: CGSize(width: -800, height: 0), size: editor.viewport)
        XCTAssertNotEqual(editor.proposedDesktopCamera(app), target.camera)
        XCTAssertTrue(editor.activateArea(app))
        XCTAssertEqual(app.desktopCamera, target.camera)
        XCTAssertFalse(app.isDesktopWorldEnabled)
        app.shutdown()
        let reopened = state(store)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.selectedAreaID, target.id)
        XCTAssertEqual(reopened.library.activeAreaID, target.id)
        XCTAssertEqual(reopened.desktopCamera, target.camera)
        XCTAssertFalse(reopened.isDesktopWorldEnabled)
        XCTAssertFalse(reopened.finderDiagnostics.hasRead)
    }

    @MainActor
    func testFailedActivationKeepsLiveRuntimeAndDoesNotQueueFailedSelection() {
        let store = AreaStore(), events = FakeGlobalMouseEventMonitor(), app = state(store, events: events)
        defer { app.shutdown() }
        app.toggleDesktopWorld()
        let active = app.library.activeAreaID, world = app.desktopWorld, camera = app.desktopCamera
        XCTAssertTrue(app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        app.saveWorldNow() // Persist configuration separately from activation.
        store.fails = true
        XCTAssertFalse(app.activateSelectedArea())
        XCTAssertEqual(app.library.activeAreaID, active)
        XCTAssertEqual(app.desktopWorld, world); XCTAssertEqual(app.desktopCamera, camera)
        XCTAssertTrue(app.isDesktopWorldEnabled); XCTAssertEqual(events.callbacks.count, 1)
        store.fails = false
        app.saveWorldNow()
        XCTAssertEqual(store.document?.activeAreaID, active)
        XCTAssertTrue(app.activateSelectedArea())
        XCTAssertEqual(app.activeWorldID, app.selectedWorldID)
        XCTAssertTrue(app.isDesktopWorldEnabled); XCTAssertEqual(events.callbacks.count, 2)
    }

    @MainActor
    func testPendingConfigurationSaveFailureAlsoPreservesRuntime() {
        let store = AreaStore(), app = state(store)
        defer { app.shutdown() }
        let active = app.library.activeAreaID
        app.toggleDesktopWorld()
        app.createWorld(name: "Unsaved", generation: WorldGenerationSettings(seed: 42))
        store.fails = true
        XCTAssertFalse(app.activateSelectedArea())
        XCTAssertEqual(app.library.activeAreaID, active); XCTAssertTrue(app.isDesktopWorldEnabled)
        store.fails = false; app.saveWorldNow()
        XCTAssertEqual(store.document?.activeAreaID, active)
        XCTAssertEqual(store.document?.worlds.count, 2)
    }

    @MainActor
    func testIdenticalViewActivationPreservesHeldCircuitAndMonitor() async {
        let provider = AreaProvider(), events = FakeGlobalMouseEventMonitor(), app = state(provider: provider, events: events)
        defer { app.shutdown() }
        await app.finderDiagnostics.readItems(); app.toggleDesktopWorld()
        app.handleCircuitClick(DemoCircuit.button)
        await app.activationTask?.value
        for _ in 0..<3 { app.advanceCircuitTick() }
        XCTAssertGreaterThan(app.simulator.power(at: DemoCircuit.button).rawValue, 0)
        let before = app.simulator
        XCTAssertTrue(app.saveArea(name: "Alias", camera: app.desktopCamera))
        let alias = app.selectedAreaID
        XCTAssertTrue(app.activateSelectedArea())
        XCTAssertEqual(app.library.activeAreaID, alias)
        XCTAssertEqual(app.simulator, before)
        XCTAssertEqual(events.callbacks.count, 1)
    }

    @MainActor
    func testOldWorldInputCompletionCannotPulseNewWorldAtSameCoordinates() async throws {
        let provider = AreaProvider(), app = state(provider: provider), events = app.finderDiagnostics
        defer { app.shutdown() }
        let original = app.selectedWorldID
        // Another independent legacy-profile world with the identical input coordinates.
        let otherStore = AreaStore()
        var second = try WorldDocument(legacy: LegacyWorldDocument())
        second.id = UUID(); second.name = "Other"
        var lib = try XCTUnwrap(otherStore.document)
        lib.worlds.append(second)
        lib.areas.append(SavedArea(name: "Other Home", worldID: second.id, camera: SavedArea.homeCamera))
        otherStore.document = lib
        let secondApp = state(otherStore, provider: provider)
        defer { secondApp.shutdown() }
        XCTAssertNotEqual(original, second.id)
        await secondApp.finderDiagnostics.readItems(); secondApp.toggleDesktopWorld()
        provider.wait = true
        secondApp.handleCircuitClick(DemoCircuit.button)
        let oldTask = secondApp.activationTask
        for _ in 0..<1000 { if provider.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(provider.continuation)
        guard provider.continuation != nil else { return }
        XCTAssertTrue(secondApp.selectWorld(second.id))
        XCTAssertTrue(secondApp.activateSelectedArea())
        XCTAssertNil(secondApp.activationTask)
        provider.wait = false
        provider.continuation?.resume(returning: [provider.item]); provider.continuation = nil
        await oldTask?.value
        for _ in 0..<4 { secondApp.advanceCircuitTick() }
        XCTAssertEqual(secondApp.simulator.power(at: DemoCircuit.button), .off)
        XCTAssertEqual(secondApp.simulator.power(at: DemoCircuit.output), .off)
        XCTAssertFalse(events.hasRead)
        secondApp.handleCircuitClick(DemoCircuit.button)
        await secondApp.activationTask?.value
        secondApp.advanceCircuitTick()
        XCTAssertEqual(secondApp.simulator.power(at: DemoCircuit.button), .full)
    }

    @MainActor
    func testOffscreenComponentsTransmitButOffscreenOutputsNeverReadOrOpen() async throws {
        let store = AreaStore(), provider = AreaProvider(), opener = FixtureItemOpener()
        var lib = try XCTUnwrap(store.document)
        lib.worlds[0].activeLevers = [WorldCoordinate(x: 2, y: 5)]
        // Left of view: lever and part of wire. Visible: output at 7,5.
        lib.areas[0].camera = CameraState(worldOrigin: WorldPoint(x: 5, y: 4), pointsPerTile: 64)
        store.document = lib
        let app = state(store, provider: provider, opener: opener)
        defer { app.shutdown() }
        await app.finderDiagnostics.readItems(); app.toggleDesktopWorld()
        for _ in 0..<12 { app.advanceCircuitTick(); await app.activationTask?.value }
        XCTAssertGreaterThan(app.simulator.power(at: WorldCoordinate(x: 7, y: 5)).rawValue, 0)
        XCTAssertGreaterThan(provider.calls, 1)
        XCTAssertTrue(app.saveArea(name: "Output offscreen", camera: CameraState(worldOrigin: WorldPoint(x: 8, y: 4), pointsPerTile: 64)))
        XCTAssertTrue(app.activateSelectedArea())
        let calls = provider.calls
        for _ in 0..<12 { app.advanceCircuitTick(); await app.activationTask?.value }
        XCTAssertGreaterThan(app.simulator.power(at: WorldCoordinate(x: 7, y: 5)).rawValue, 0)
        XCTAssertEqual(provider.calls, calls)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testOldOutputReadCannotOpenAfterSwitchingToCoincidentTarget() async {
        let provider = AreaProvider(), opener = FixtureItemOpener(), app = state(provider: provider, opener: opener)
        defer { app.shutdown() }
        await app.finderDiagnostics.readItems(); app.toggleDesktopWorld()
        app.handleCircuitClick(DemoCircuit.button)
        await app.activationTask?.value
        provider.wait = true
        for _ in 0..<12 { app.advanceCircuitTick() }
        let oldTask = app.activationTask
        for _ in 0..<1000 { if provider.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(provider.continuation)
        guard provider.continuation != nil else { return }
        // Same world, different view still invalidates the request even though the output remains visible.
        XCTAssertTrue(app.saveArea(name: "Nearby", camera: CameraState(worldOrigin: WorldPoint(x: 1, y: 0), pointsPerTile: 64)))
        XCTAssertTrue(app.activateSelectedArea())
        provider.wait = false
        provider.continuation?.resume(returning: [provider.item]); provider.continuation = nil
        await oldTask?.value
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertEqual(app.simulator.power(at: DemoCircuit.output), .off)
        XCTAssertNil(app.activationTask)
    }

    @MainActor
    func testDisplayPreflightFailurePreservesRuntimeAndPostCommitFailureDisablesIt() {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        var available: ScreenDescriptor? = screen
        let store = AreaStore(), events = FakeGlobalMouseEventMonitor()
        let app = AppState(screenProviding: { available }, clickEventMonitoring: events,
            tickScheduler: ManualCircuitTickScheduler(), libraryStore: store, autosaveDelay: .seconds(3600))
        defer { app.shutdown() }
        app.toggleDesktopWorld()
        let old = app.library.activeAreaID
        app.saveArea(name: "Elsewhere", camera: CameraState(worldOrigin: WorldPoint(x: 10, y: 0), pointsPerTile: 64))
        available = nil
        XCTAssertFalse(app.activateSelectedArea())
        XCTAssertTrue(app.isDesktopWorldEnabled); XCTAssertEqual(app.library.activeAreaID, old)
        XCTAssertEqual(events.callbacks.count, 1)
        available = screen
        app.saveWorldNow()
        store.didSave = { available = nil }
        XCTAssertFalse(app.activateSelectedArea())
        XCTAssertFalse(app.isDesktopWorldEnabled)
        XCTAssertEqual(app.library.activeAreaID, app.selectedAreaID)
        XCTAssertEqual(store.document?.activeAreaID, app.selectedAreaID)
        XCTAssertTrue(app.areaStatus.contains("rendering could not start"))
        XCTAssertEqual(events.removedTokens.count, 1)
    }

    @MainActor
    func testInactiveLeverLabelRetainsPositionWithoutLivePower() throws {
        let store = AreaStore()
        var lib = try XCTUnwrap(store.document)
        lib.worlds[0].activeLevers = [WorldCoordinate(x: 2, y: 5)]
        store.document = lib
        let app = state(store), editor = EditorSession(), renderer = EditorCanvasRenderer()
        defer { app.shutdown() }
        let original = app.selectedAreaID
        app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42))
        XCTAssertTrue(app.activateSelectedArea())
        XCTAssertTrue(editor.selectArea(original, appState: app))
        XCTAssertTrue(app.editorPoweredTiles.isEmpty)
        let scene = try XCTUnwrap(renderer.update(appState: app, editor: editor, size: editor.viewport))
        let label = try XCTUnwrap(scene.childNode(withName: "circuit/state-label:2,5") as? SKLabelNode)
        XCTAssertEqual(label.text, "ON")
        XCTAssertEqual(app.editorPower(at: WorldCoordinate(x: 2, y: 5)), .off)
    }
}
