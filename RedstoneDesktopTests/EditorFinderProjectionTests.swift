import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class ProjectionProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var calls = 0
    var denied = false
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if denied { throw FinderReadError.permissionDenied }
        return items
    }
}

final class EditorFinderProjectionTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "test", frame: CGRect(x: -640, y: -100, width: 640, height: 480), backingScale: 2)
    private let camera = CameraState(worldOrigin: WorldPoint(x: -5.5, y: 2.25), pointsPerTile: 64)
    private func item(_ id: String = "folder", x: CGFloat = 130, y: CGFloat = 348) -> DesktopItem {
        DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), displayName: id,
                    position: CGPoint(x: x, y: y), estimatedIconSize: nil, kind: .folder)
    }
    private func projection(_ items: [DesktopItem], worldID: UUID = UUID()) -> EditorFinderProjection {
        EditorFinderProjection(worldID: worldID, camera: camera,
            snapshot: FinderReadSnapshot(items: items, hasRead: true), screen: screen, reference: screen, enabled: true)
    }

    func testNegativeDisplayRetinaFractionalOriginAndWorldScope() throws {
        let id = UUID(), p = projection([item()], worldID: id)
        XCTAssertEqual(p.worldID, id)
        XCTAssertEqual(p.markers.first?.tile, WorldCoordinate(x: -4, y: 4))
        let center = try XCTUnwrap(p.markers.first?.worldCenter)
        XCTAssertEqual(center.x, -3.46875)
        XCTAssertEqual(center.y, 4.3125)
        XCTAssertEqual(p.occupancy.state(at: WorldCoordinate(x: -4, y: 4)), .occupied(item()))
        let editor = try CoordinateMapper(canvasFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            camera: CameraState(worldOrigin: camera.worldOrigin, pointsPerTile: 40))
        XCTAssertEqual(editor.screenPoint(fromWorld: center), CGPoint(x: 81.25, y: 82.5))
        let other = projection([item()], worldID: UUID())
        XCTAssertNotEqual(other.worldID, p.worldID)
    }

    func testOutsideDisplayExcludedAndAmbiguityIsPreserved() {
        let a = item("a"), b = item("b", x: 131)
        let p = projection([b, item("outside", x: 700), a])
        XCTAssertEqual(p.markers.count, 2)
        XCTAssertEqual(p.occupancy.state(at: WorldCoordinate(x: -4, y: 4)), .ambiguous([a, b]))
        XCTAssertEqual(p.occupancy.state(at: WorldCoordinate(x: 0, y: 0)), .empty)
    }

    func testUnavailableHiddenUnreadAndInvalidGeometryHaveNoMarkers() {
        for (enabled, snapshot, display) in [
            (false, FinderReadSnapshot(items: [item()], hasRead: true), Optional(screen)),
            (true, FinderReadSnapshot(), Optional(screen)),
            (true, FinderReadSnapshot(items: [item()], error: "Denied", hasRead: true), Optional(screen)),
            (true, FinderReadSnapshot(items: [item()], hasRead: true), nil)
        ] {
            let p = EditorFinderProjection(worldID: UUID(), camera: camera, snapshot: snapshot,
                screen: display, reference: screen, enabled: enabled)
            XCTAssertTrue(p.markers.isEmpty)
            guard case .unavailable = p.occupancy else { return XCTFail("Expected unavailable") }
        }
    }

    func testSnapCrossesTileEdgeAndUsesEditorPointsWithoutGuessingTies() throws {
        let mapper = try CoordinateMapper(canvasFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            camera: CameraState(worldOrigin: camera.worldOrigin, pointsPerTile: 40))
        let p = projection([item()])
        let point = CGPoint(x: 59, y: 82.5) // Ordinary hit is tile -5; marker lies in -4.
        XCTAssertEqual(p.snappedTile(near: point, mapper: mapper), WorldCoordinate(x: -4, y: 4))
        let across = CGPoint(x: 55, y: 82.5)
        XCTAssertNil(p.snappedTile(near: across, mapper: mapper)) // More than 24 logical points away.
        let two = projection([item("a", x: 144), item("b", x: 176)])
        let mid = CGPoint(x: 100, y: 82.5)
        XCTAssertNil(two.snappedTile(near: mid, mapper: mapper), "Equal-distance centers in different tiles are not guessed")
        XCTAssertNil(p.snappedTile(near: CGPoint(x: -1, y: 0), mapper: mapper))
    }

    @MainActor
    private func state(_ provider: ProjectionProvider, opener: FixtureItemOpener = FixtureItemOpener(), automatic: Bool = false) -> AppState {
        AppState(screenProviding: { self.screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider), tickScheduler: ManualCircuitTickScheduler(),
            itemOpener: opener, automaticallyRefreshFinder: automatic, finderReferenceProviding: { self.screen })
    }

    @MainActor
    func testExplicitEditorTrackingPublishesMovementWhileDesktopStoppedAndStopsOnClose() async {
        let provider = ProjectionProvider(), state = state(provider)
        defer { state.shutdown() }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertFalse(state.editorFinderItemsVisible)
        state.setEditorFinderItemsVisible(true)
        XCTAssertTrue(state.desktopItemTracker.isPolling)
        // Use the same model read slot; wait for the initial tracker read before changing its fixture.
        for _ in 0..<100 where !state.finderReadSnapshot.hasRead { await Task.yield() }
        provider.items = [item()]
        await state.finderDiagnostics.readItems()
        XCTAssertEqual(state.finderReadSnapshot.items, provider.items)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertTrue(state.finderMappings.isEmpty)
        XCTAssertEqual(state.desktopOccupancy, .unavailable("Enable Desktop World to resolve occupancy."))
        provider.items = [item(x: 210)]
        await state.finderDiagnostics.readItems()
        XCTAssertEqual(state.finderReadSnapshot.items.first?.position.x, 210)
        state.setEditorFinderItemsVisible(false)
        XCTAssertFalse(state.desktopItemTracker.isPolling)
    }

    @MainActor
    func testDesktopStopKeepsOptedInEditorTrackerAndFullShutdownStopsIt() {
        let state = state(ProjectionProvider(), automatic: true)
        state.setEditorFinderItemsVisible(true)
        state.toggleDesktopWorld()
        state.setEditorFinderItemsVisible(false)
        XCTAssertTrue(state.desktopItemTracker.isPolling, "Desktop still owns the shared tracker")
        state.setEditorFinderItemsVisible(true)
        state.toggleDesktopWorld()
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertTrue(state.desktopItemTracker.isPolling, "Editor still owns the shared tracker")
        state.shutdown()
        XCTAssertFalse(state.desktopItemTracker.isPolling)
        XCTAssertFalse(state.editorFinderItemsVisible)
    }

    @MainActor
    func testOutputClickAndHoverSnapFreshProjectionWithoutOpeningOrMovingComponents() async throws {
        let provider = ProjectionProvider(), opener = FixtureItemOpener()
        let editor = EditorSession(), size = CGSize(width: 800, height: 600)
        // Legacy fixture's grass tile (10,7), with icon center just inside its left edge.
        let wide = ScreenDescriptor(id: "wide", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 2)
        let wideState = AppState(screenProviding: { wide }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider), tickScheduler: ManualCircuitTickScheduler(),
            itemOpener: opener, finderReferenceProviding: { wide })
        defer { wideState.shutdown() }
        provider.items = [item(x: 640.64, y: 420)]
        await wideState.finderDiagnostics.readItems()
        wideState.setEditorFinderItemsVisible(true)
        editor.tool = .output
        let click = CGPoint(x: 395, y: 300)
        XCTAssertEqual(try XCTUnwrap(editor.mapper(size: size)).tile(atScreen: click), WorldCoordinate(x: 9, y: 7))
        editor.hover(at: click, size: size, appState: wideState)
        XCTAssertEqual(editor.hoveredTile, WorldCoordinate(x: 10, y: 7))
        editor.click(at: click, size: size, appState: wideState)
        XCTAssertEqual(wideState.editorWorld.circuit.components[WorldCoordinate(x: 10, y: 7)]?.kind, .output)
        XCTAssertNil(wideState.editorWorld.circuit.components[WorldCoordinate(x: 9, y: 7)])
        let before = wideState.editorWorld
        provider.items = [item(x: 960, y: 420)]
        await wideState.finderDiagnostics.readItems()
        XCTAssertEqual(wideState.editorWorld, before, "Moving Finder icons never moves placed components")
        editor.click(at: click, size: size, appState: wideState)
        XCTAssertEqual(editor.selectedTile, WorldCoordinate(x: 9, y: 7), "Click recomputes after an icon moves rather than reusing hover")
        XCTAssertEqual(wideState.editorWorld.circuit.components[WorldCoordinate(x: 10, y: 7)], before.circuit.components[WorldCoordinate(x: 10, y: 7)])
        XCTAssertEqual(wideState.editorWorld.circuit.components[WorldCoordinate(x: 9, y: 7)]?.kind, .output)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(wideState.simulator.poweredTiles.isEmpty)
    }

    @MainActor
    func testInactiveWorldAndDraftCameraProjectionLeaveLiveAssignmentUntouched() async {
        let provider = ProjectionProvider(), state = state(provider), editor = EditorSession()
        defer { state.shutdown() }
        provider.items = [item()]
        await state.finderDiagnostics.readItems()
        state.setEditorFinderItemsVisible(true)
        state.toggleDesktopWorld()
        let activeID = state.activeWorldID, liveCamera = state.desktopCamera, occupancy = state.desktopOccupancy
        let world = state.desktopWorld, simulator = state.simulator
        XCTAssertTrue(state.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 42)))
        editor.syncSelectedWorld(state)
        editor.pan(by: CGSize(width: 120, height: -80), size: CGSize(width: 800, height: 600))
        let projected = editor.finderProjection(state)
        XCTAssertEqual(projected.worldID, state.selectedWorldID)
        XCTAssertNotEqual(projected.worldID, activeID)
        XCTAssertEqual(projected.camera, editor.proposedDesktopCamera(state))
        XCTAssertEqual(state.activeWorldID, activeID)
        XCTAssertEqual(state.desktopCamera, liveCamera)
        XCTAssertEqual(state.desktopOccupancy, occupancy)
        XCTAssertEqual(state.desktopWorld, world)
        XCTAssertEqual(state.simulator, simulator)
        XCTAssertEqual(state.editorOccupancy, .unavailable("This world is not active on the desktop."))
        editor.seedText = "123"; XCTAssertTrue(editor.previewSeed())
        XCTAssertTrue(editor.finderProjection(state).markers.isEmpty)
    }

    @MainActor
    func testSnappingRetainsPlacementAndLiveEditingGuards() async {
        let provider = ProjectionProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let wide = ScreenDescriptor(id: "wide", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 1)
        let state = AppState(screenProviding: { wide }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider), tickScheduler: ManualCircuitTickScheduler(),
            itemOpener: opener, finderReferenceProviding: { wide })
        defer { state.shutdown() }
        provider.items = [item(x: 896.64, y: 676)]
        await state.finderDiagnostics.readItems()
        state.setEditorFinderItemsVisible(true)
        editor.tool = .output
        let before = state.editorWorld, size = CGSize(width: 800, height: 600)
        editor.click(at: CGPoint(x: 555, y: 140), size: size, appState: state)
        XCTAssertEqual(editor.selectedTile, WorldCoordinate(x: 14, y: 3))
        XCTAssertEqual(state.editorWorld, before, "Snapping cannot bypass blocked terrain")
        provider.items = [item(x: 640.64, y: 420)]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        editor.click(at: CGPoint(x: 395, y: 300), size: size, appState: state)
        XCTAssertEqual(state.editorWorld, before, "Running active-world configuration remains locked")
        state.toggleDesktopWorld()
        editor.seedText = "42"; XCTAssertTrue(editor.previewSeed())
        editor.click(at: CGPoint(x: 395, y: 300), size: size, appState: state)
        XCTAssertEqual(state.editorWorld, before)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testDeniedEditorReadDoesNotRepeatedlyPromptAndClearsGhosts() async {
        let provider = ProjectionProvider(), state = state(provider)
        defer { state.shutdown() }
        provider.denied = true
        await state.finderDiagnostics.readItems()
        state.setEditorFinderItemsVisible(true)
        XCTAssertFalse(state.desktopItemTracker.isPolling)
        XCTAssertTrue(state.editorFinderProjection(camera: camera).markers.isEmpty)
        XCTAssertEqual(provider.calls, 1)
        state.setEditorFinderItemsVisible(false)
        state.setEditorFinderItemsVisible(true)
        await Task.yield()
        XCTAssertEqual(provider.calls, 1)
    }

    @MainActor
    func testOutputGlowUsesProposedCameraInsteadOfLiveOccupancy() async throws {
        let provider = ProjectionProvider(), editor = EditorSession(), opener = FixtureItemOpener()
        let wide = ScreenDescriptor(id: "wide", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 2)
        let state = AppState(screenProviding: { wide }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider), tickScheduler: ManualCircuitTickScheduler(),
            itemOpener: opener, finderReferenceProviding: { wide })
        defer { state.shutdown() }
        let output = WorldCoordinate(x: 10, y: 7)
        state.placeCircuitComponent(CircuitComponent(kind: .output), at: output)
        provider.items = [item(x: 928, y: 420)]
        await state.finderDiagnostics.readItems()
        state.setEditorFinderItemsVisible(true)
        state.toggleDesktopWorld()
        XCTAssertEqual(state.desktopOccupancy.state(at: output), .empty)
        let size = CGSize(width: 800, height: 600)
        editor.pan(by: CGSize(width: 160, height: 0), size: size)
        let renderer = EditorCanvasRenderer()
        let scene = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: size))
        let badge = scene.childNode(withName: "circuit")?.children.compactMap {
            $0.childNode(withName: "output-occupancy:10,7") as? SKShapeNode
        }.first
        let color = try XCTUnwrap(badge?.strokeColor.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.greenComponent, color.redComponent)
        XCTAssertEqual(try XCTUnwrap(badge).alpha, 0.55, accuracy: 0.001)
        XCTAssertEqual(state.desktopOccupancy.state(at: output), .empty)
        XCTAssertEqual(provider.calls, 1, "Rendering consumes cached data only")
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testRendererUsesProposedOccupancyAndRefreshesMarkersWithoutAccumulation() async throws {
        let provider = ProjectionProvider(), state = state(provider), editor = EditorSession()
        defer { state.shutdown() }
        provider.items = [item(x: 130, y: 348)]
        await state.finderDiagnostics.readItems()
        state.setEditorFinderItemsVisible(true)
        let renderer = EditorCanvasRenderer(), size = CGSize(width: 800, height: 600)
        for _ in 0..<20 { _ = renderer.update(appState: state, editor: editor, size: size) }
        let scene = try XCTUnwrap(renderer.scene)
        XCTAssertEqual(scene.childNode(withName: "editor-finder")?.children.count, 1)
        let node = try XCTUnwrap(scene.childNode(withName: "editor-finder")?.children.first)
        XCTAssertEqual(node.position, CGPoint(x: 81.25, y: 82.5))
        provider.items = []
        await state.finderDiagnostics.readItems()
        _ = renderer.update(appState: state, editor: editor, size: size)
        XCTAssertEqual(scene.childNode(withName: "editor-finder")?.children.count, 0)
        state.setEditorFinderItemsVisible(false)
        _ = renderer.update(appState: state, editor: editor, size: size)
        XCTAssertNil(scene.childNode(withName: "editor-finder"))
    }
}
