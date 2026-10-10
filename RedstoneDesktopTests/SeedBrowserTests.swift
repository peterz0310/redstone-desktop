import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

private final class SeedBrowserStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws { self.document = document }
}

final class SeedBrowserTests: XCTestCase {
    @MainActor
    private func state(_ store: SeedBrowserStore = SeedBrowserStore()) -> AppState {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: -640, y: -200, width: 1280, height: 800), backingScale: 2)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), libraryStore: store, finderReferenceProviding: { screen })
    }

    @MainActor
    private func apply(_ camera: CameraState, to state: AppState) -> Bool {
        state.saveArea(name: "Test Area", camera: camera) && state.activateSelectedArea()
    }

    @MainActor
    func testSeedParsingSupportsFullUnsignedRangeAndRejectsInvalidDrafts() {
        let editor = EditorSession()
        for text in ["0", "42", "18446744073709551615", " 2026 "] {
            editor.seedText = text
            XCTAssertTrue(editor.previewSeed())
        }
        let before = editor.previewGeneration
        for text in ["", "-1", "+1", "1.5", "abc", "18446744073709551616"] {
            editor.seedText = text
            XCTAssertFalse(editor.previewSeed())
            XCTAssertEqual(editor.previewGeneration, before)
        }
        editor.randomSeed()
        XCTAssertNotNil(UInt64(editor.seedText))
        XCTAssertEqual(editor.previewGeneration?.seed, UInt64(editor.seedText))
    }

    @MainActor
    func testBrowsingPreviewPanZoomAndCancelDoNotChangeWorldCameraOrSave() throws {
        let store = SeedBrowserStore(), state = state(store), editor = EditorSession()
        defer { state.shutdown() }
        let world = state.desktopWorld, camera = state.desktopCamera, saved = store.document
        editor.seedText = "42"; XCTAssertTrue(editor.previewSeed())
        editor.pan(by: CGSize(width: 500, height: -300), size: CGSize(width: 800, height: 600))
        editor.zoom(by: 0.5)
        XCTAssertEqual(editor.browsingWorld(state).generation?.seed, 42)
        XCTAssertEqual(state.desktopWorld, world)
        XCTAssertEqual(state.desktopCamera, camera)
        state.saveWorldNow()
        XCTAssertEqual(store.document, saved)
        editor.cancelPreview(state)
        XCTAssertEqual(editor.browsingWorld(state), world)
        XCTAssertFalse(editor.isPreviewing(state))
    }

    @MainActor
    func testSeedPreviewBlocksCanvasEditingUntilCreatedOrCancelled() throws {
        let state = state(), editor = EditorSession(), size = CGSize(width: 800, height: 600)
        defer { state.shutdown() }
        editor.seedText = "42"; editor.previewSeed(); editor.tool = .dust
        editor.click(at: CGPoint(x: 420, y: 300), size: size, appState: state)
        XCTAssertNil(state.desktopWorld.circuit.components[WorldCoordinate(x: 10, y: 7)])
        editor.cancelPreview(state)
        editor.click(at: CGPoint(x: 420, y: 300), size: size, appState: state)
        XCTAssertEqual(state.desktopWorld.circuit.components[WorldCoordinate(x: 10, y: 7)]?.kind, .dust)
    }

    @MainActor
    func testUseAreaSavesCameraWithFixedSeedAndRestoresOnReopen() throws {
        let store = SeedBrowserStore(), state = state(store), editor = EditorSession()
        let circuit = state.desktopWorld.circuit
        editor.pan(by: CGSize(width: -1600, height: 800), size: CGSize(width: 800, height: 600))
        editor.cancelPreview(state)
        let proposed = editor.proposedDesktopCamera(state)
        XCTAssertEqual(proposed.worldOrigin, WorldPoint(x: 40, y: -20))
        XCTAssertEqual(proposed.pointsPerTile, 64)
        XCTAssertTrue(editor.saveArea(state))
        XCTAssertTrue(editor.activateArea(state))
        XCTAssertEqual(state.desktopCamera, proposed)
        XCTAssertEqual(state.desktopWorld.generation?.seed, 2026)
        XCTAssertEqual(state.desktopWorld.circuit, circuit)
        state.shutdown()
        let reopened = self.state(store)
        defer { reopened.shutdown() }
        XCTAssertEqual(reopened.desktopCamera, proposed)
        XCTAssertEqual(reopened.desktopWorld.generation?.seed, 2026)
        XCTAssertFalse(reopened.isDesktopWorldEnabled)
    }

    @MainActor
    func testExistingWorldSeedReplacementIsRefusedAtomically() throws {
        let state = state(), editor = EditorSession()
        defer { state.shutdown() }
        let current = try WorldGenerator(settings: WorldGenerationSettings(seed: 2026))
        let candidate = try WorldGenerator(settings: WorldGenerationSettings(seed: 42))
        let coordinate = try XCTUnwrap((32..<128).map { WorldCoordinate(x: $0, y: 32) }.first {
            let a = current.tile(at: $0), b = candidate.tile(at: $0)
            return !a.terrain.definition.isLiquid && a.decoration == nil && (b.terrain.definition.isLiquid || b.decoration != nil)
        })
        XCTAssertTrue(state.placeCircuitComponent(CircuitComponent(kind: .output), at: coordinate).isAllowed)
        let before = state.desktopWorld, camera = state.desktopCamera
        editor.seedText = "42"; editor.previewSeed()
        XCTAssertFalse(editor.activateArea(state))
        XCTAssertEqual(state.desktopWorld, before)
        XCTAssertEqual(state.desktopCamera, camera)
        XCTAssertTrue(editor.isPreviewing(state))
    }

    @MainActor
    func testApplyingWhileRunningRebuildsMapperAndOccupancyAndKeepsOneMonitor() throws {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        let events = FakeGlobalMouseEventMonitor()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: events, tickScheduler: ManualCircuitTickScheduler(), libraryStore: SeedBrowserStore(), finderReferenceProviding: { screen })
        defer { state.shutdown() }
        state.toggleDesktopWorld()
        XCTAssertTrue(state.isDesktopWorldEnabled)
        let camera = CameraState(worldOrigin: WorldPoint(x: 50, y: -30), pointsPerTile: 64)
        XCTAssertTrue(apply(camera, to: state))
        XCTAssertTrue(state.isDesktopWorldEnabled)
        XCTAssertEqual(state.desktopCamera, camera)
        if let pointer = state.pointer, let worldPoint = pointer.worldPoint {
            let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: camera)
            XCTAssertEqual(worldPoint, mapper.worldPoint(fromScreen: pointer.screenPoint))
        }
        XCTAssertTrue(state.finderMappings.isEmpty)
        XCTAssertEqual(state.desktopWorld.circuit, DemoCircuit.makeWorld().circuit)
        XCTAssertEqual(events.callbacks.count, 2)
        XCTAssertEqual(events.removedTokens.count, 1)
        events.callbacks[0](CGPoint(x: 32, y: 32))
        XCTAssertEqual(state.observedClickCount, 0)
        events.callbacks[1](CGPoint(x: 32, y: 32))
        XCTAssertEqual(state.lastClick?.tile, WorldCoordinate(x: 50, y: -30))
    }

    @MainActor
    func testApplyingCameraRemapsRealItemSnapshotInsteadOfKeepingOldTile() async {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        let provider = SeedBrowserItemProvider()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider), tickScheduler: ManualCircuitTickScheduler(),
            libraryStore: SeedBrowserStore(), finderReferenceProviding: { screen })
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        XCTAssertEqual(state.desktopOccupancy.state(at: WorldCoordinate(x: 7, y: 3)), .occupied(provider.item))
        XCTAssertTrue(apply(CameraState(worldOrigin: WorldPoint(x: 10, y: -5), pointsPerTile: 64), to: state))
        XCTAssertEqual(state.desktopOccupancy.state(at: WorldCoordinate(x: 7, y: 3)), .empty)
        XCTAssertEqual(state.desktopOccupancy.state(at: WorldCoordinate(x: 17, y: -2)), .occupied(provider.item))
    }

    @MainActor
    func testCoincidentZoneLabelsShareHeightWithoutOverlapping() throws {
        let state = state(), editor = EditorSession(), renderer = EditorCanvasRenderer()
        defer { state.shutdown() }
        let scene = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: CGSize(width: 800, height: 600)))
        let desktop = try XCTUnwrap(scene.childNode(withName: "editor-desktop-viewport/current-desktop-label") as? SKLabelNode)
        let current = try XCTUnwrap(scene.childNode(withName: "editor-desktop-viewport/chosen-desktop-label") as? SKLabelNode)
        XCTAssertEqual(desktop.position.y, current.position.y)
        XCTAssertGreaterThan(current.calculateAccumulatedFrame().minX, desktop.calculateAccumulatedFrame().maxX)
    }

    @MainActor
    func testPhysicalViewportOutlineUsesDisplaySizeAndMapperAtNegativeOrigin() throws {
        let state = state(), editor = EditorSession(), renderer = EditorCanvasRenderer()
        defer { state.shutdown() }
        let size = CGSize(width: 800, height: 600)
        editor.pan(by: CGSize(width: 400, height: -200), size: size)
        let scene = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: size))
        let layer = try XCTUnwrap(scene.childNode(withName: "editor-desktop-viewport"))
        XCTAssertEqual(layer.children.compactMap { $0 as? SKShapeNode }.count, 2)
        XCTAssertEqual((layer.childNode(withName: "current-desktop-label") as? SKLabelNode)?.text, "Desktop area")
        XCTAssertEqual((layer.childNode(withName: "chosen-desktop-label") as? SKLabelNode)?.text, "Current view")
        let chosen = try XCTUnwrap(layer.childNode(withName: "chosen-desktop") as? SKShapeNode)
        let current = try XCTUnwrap(layer.childNode(withName: "current-desktop") as? SKShapeNode)
        XCTAssertEqual(chosen.path?.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 800, height: 500))
        XCTAssertEqual(current.path?.boundingBoxOfPath, CGRect(x: 400, y: -200, width: 800, height: 500))
        for name in ["current-desktop", "chosen-desktop"] {
            let outline = try XCTUnwrap(layer.childNode(withName: name) as? SKShapeNode)
            let rect = try XCTUnwrap(outline.path?.boundingBoxOfPath)
            let label = try XCTUnwrap(layer.childNode(withName: name + "-label") as? SKLabelNode)
            XCTAssertEqual(label.position.x, rect.minX + 8)
            XCTAssertGreaterThan(label.calculateAccumulatedFrame().minY, rect.maxY)
        }
        editor.pan(by: CGSize(width: -1600, height: 1400), size: size)
        _ = renderer.update(appState: state, editor: editor, size: size)
        let offscreen = try XCTUnwrap(scene.childNode(withName: "editor-desktop-viewport/current-desktop-label") as? SKLabelNode)
        XCTAssertLessThan(offscreen.position.x, 0)
        XCTAssertGreaterThan(offscreen.position.y, size.height)
        XCTAssertEqual(state.desktopCamera.worldOrigin, WorldPoint(x: 0, y: 0))
    }

    @MainActor
    func testMissingDisplayAndInvalidCameraRefuseAreaWithoutChanges() {
        let state = AppState(screenProviding: { nil }), before = state.desktopWorld
        XCTAssertFalse(state.activateSelectedArea())
        XCTAssertEqual(state.desktopWorld, before)
        let valid = self.state()
        defer { valid.shutdown() }
        XCTAssertFalse(valid.saveArea(name: "Invalid", camera: CameraState(worldOrigin: WorldPoint(x: .nan, y: 0), pointsPerTile: 64)))
        XCTAssertFalse(valid.createWorld(name: "Unsupported", generation: WorldGenerationSettings(generationVersion: 99, seed: 42)))
    }
}

@MainActor
private final class SeedBrowserItemProvider: DesktopItemProviding {
    let item = DesktopItem(id: "test", url: URL(fileURLWithPath: "/tmp/seed-browser-target"), displayName: "Target", position: CGPoint(x: 480, y: 576), estimatedIconSize: nil, kind: .folder)
    func currentDesktopItems() async throws -> [DesktopItem] { [item] }
}
