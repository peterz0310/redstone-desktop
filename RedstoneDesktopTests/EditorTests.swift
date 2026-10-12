import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class EditorItemProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] { calls += 1; return items }
}

final class EditorTests: XCTestCase {
    private let size = CGSize(width: 800, height: 600)
    private func cell(_ x: Int, _ y: Int = 7) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    @MainActor
    private func state(_ provider: EditorItemProvider, _ opener: FixtureItemOpener) -> AppState {
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 2)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture desktop") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener,
            finderReferenceProviding: { screen })
    }
    @MainActor
    private func point(_ coordinate: WorldCoordinate, editor: EditorSession) throws -> CGPoint {
        let rect = try XCTUnwrap(editor.mapper(size: size)).screenRect(forTile: coordinate)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func testMapperPanMovesContentWithPointerAndZoomPreservesAnchor() throws {
        let frame = CGRect(x: -640, y: -100, width: 800, height: 600)
        let mapper = try CoordinateMapper(canvasFrame: frame, camera: CameraState(worldOrigin: WorldPoint(x: -2.5, y: 3.25), pointsPerTile: 40))
        let world = WorldPoint(x: 5, y: 7)
        let before = mapper.screenPoint(fromWorld: world)
        let panned = try CoordinateMapper(canvasFrame: frame, camera: try XCTUnwrap(mapper.camera(pannedByScreenDelta: CGSize(width: 120, height: -80))))
        let after = panned.screenPoint(fromWorld: world)
        XCTAssertEqual(after.x - before.x, 120, accuracy: 0.00001)
        XCTAssertEqual(after.y - before.y, -80, accuracy: 0.00001)
        let anchor = CGPoint(x: -300, y: 200)
        let zoomed = try CoordinateMapper(canvasFrame: frame, camera: try XCTUnwrap(mapper.camera(zoomedTo: 96, aroundScreen: anchor)))
        XCTAssertEqual(zoomed.worldPoint(fromScreen: anchor).x, mapper.worldPoint(fromScreen: anchor).x, accuracy: 0.00001)
        XCTAssertEqual(zoomed.worldPoint(fromScreen: anchor).y, mapper.worldPoint(fromScreen: anchor).y, accuracy: 0.00001)
        XCTAssertNil(mapper.camera(pannedByScreenDelta: CGSize(width: CGFloat.infinity, height: 0)))
        XCTAssertNil(mapper.camera(zoomedTo: 0, aroundScreen: anchor))
    }

    @MainActor
    func testNavigationIsIndependentClampedAndDoesNotEditWorldOrQueryFinder() {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener)
        let world = state.desktopWorld, desktopCamera = state.desktopCamera
        editor.pan(by: CGSize(width: 120, height: -80), size: size)
        XCTAssertEqual(editor.camera.worldOrigin, WorldPoint(x: -3, y: 2))
        editor.zoom(by: 1000, size: size)
        XCTAssertEqual(editor.camera.pointsPerTile, 128)
        editor.zoom(by: 0.0001, size: size)
        XCTAssertEqual(editor.camera.pointsPerTile, 16)
        let camera = editor.camera
        editor.pan(by: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 0), size: size)
        editor.zoom(by: .nan, size: size)
        XCTAssertEqual(editor.camera, camera)
        editor.resetCamera()
        XCTAssertEqual(editor.camera.pointsPerTile, 40)
        XCTAssertEqual(state.desktopCamera, desktopCamera)
        XCTAssertEqual(state.desktopWorld, world)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testAllPlacementToolsWorkThroughMapperAfterPanAndZoom() throws {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener)
        editor.pan(by: CGSize(width: -80, height: -40), size: size)
        editor.zoom(by: 1.25, size: size)
        editor.direction = .east
        editor.delay = .four
        for (index, tool) in [EditorSession.Tool.dust, .button, .lever, .repeater, .output, .torch].enumerated() {
            let coordinate = cell(10 + index)
            editor.tool = tool
            editor.click(at: try point(coordinate, editor: editor), size: size, appState: state)
            XCTAssertEqual(state.desktopWorld.circuit.components[coordinate]?.kind, tool.componentKind)
            XCTAssertEqual(editor.selectedTile, coordinate)
        }
        XCTAssertEqual(state.desktopWorld.circuit.components[cell(13)]?.direction, .east)
        XCTAssertEqual(state.desktopWorld.circuit.components[cell(13)]?.repeaterDelay, .four)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testInvalidPlacementAndDuplicateDoNotOverwriteAndErasePreservesTerrain() throws {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener)
        let before = state.desktopWorld
        editor.tool = .dust
        for tile in [cell(14, 3), cell(10, 5), cell(14, 5)] {
            editor.click(at: try point(tile, editor: editor), size: size, appState: state)
            XCTAssertEqual(state.desktopWorld, before)
            XCTAssertFalse(editor.status.isEmpty)
        }
        let target = cell(10)
        editor.click(at: try point(target, editor: editor), size: size, appState: state)
        editor.tool = .output
        editor.click(at: try point(target, editor: editor), size: size, appState: state)
        XCTAssertEqual(state.desktopWorld.circuit.components[target]?.kind, .dust)
        XCTAssertTrue(editor.status.contains("already contains"))
        let tiles = state.desktopWorld.tiles
        editor.tool = .erase
        editor.click(at: try point(target, editor: editor), size: size, appState: state)
        XCTAssertNil(state.desktopWorld.circuit.components[target])
        XCTAssertEqual(state.desktopWorld.tiles, tiles)
        editor.click(at: try point(target, editor: editor), size: size, appState: state)
        XCTAssertTrue(editor.status.contains("No component"))
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testSelectionLoadsRepeaterConfigurationAndInspectorUpdateIsLockedWhenRunning() throws {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener)
        let target = cell(10)
        state.placeCircuitComponent(CircuitComponent(kind: .repeater, direction: .south, repeaterDelay: .three), at: target)
        editor.click(at: try point(target, editor: editor), size: size, appState: state)
        XCTAssertEqual(editor.direction, .south)
        XCTAssertEqual(editor.delay, .three)
        XCTAssertTrue(state.configureRepeater(at: target, direction: .east, delay: .four))
        XCTAssertEqual(state.desktopWorld.circuit.components[target]?.direction, .east)
        XCTAssertEqual(state.desktopWorld.circuit.components[target]?.repeaterDelay, .four)
        XCTAssertFalse(state.configureRepeater(at: DemoCircuit.button, direction: .west, delay: .one))
        state.toggleDesktopWorld()
        defer { state.shutdown() }
        let world = state.desktopWorld, simulator = state.simulator
        XCTAssertFalse(state.configureRepeater(at: target, direction: .west, delay: .one))
        XCTAssertFalse(state.eraseCircuitComponent(at: target))
        editor.tool = .dust
        editor.click(at: try point(cell(11), editor: editor), size: size, appState: state)
        XCTAssertEqual(state.desktopWorld, world)
        XCTAssertEqual(state.simulator, simulator)
    }

    @MainActor
    func testOutOfCanvasClicksAndHoverAreIgnored() {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener)
        let before = state.desktopWorld
        editor.tool = .button
        for point in [CGPoint(x: -1, y: 20), CGPoint(x: 900, y: 20), CGPoint(x: 20, y: -1)] {
            editor.click(at: point, size: size, appState: state)
            editor.hover(at: point, size: size)
            XCTAssertNil(editor.selectedTile)
            XCTAssertNil(editor.hoveredTile)
        }
        XCTAssertEqual(state.desktopWorld, before)
    }

    @MainActor
    func testCanvasRendererPreviewChangesBetweenValidAndInvalidAndRemainsBounded() throws {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener), renderer = EditorCanvasRenderer()
        editor.tool = .dust
        for (tile, green) in [(cell(10), true), (cell(14, 3), false)] {
            editor.hover(at: try point(tile, editor: editor), size: size)
            let scene = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: size))
            let preview = try XCTUnwrap(scene.childNode(withName: "editor-preview"))
            XCTAssertEqual(preview.children.count, 2)
            let outline = try XCTUnwrap(preview.children.last as? SKShapeNode)
            let actual = try XCTUnwrap(outline.strokeColor.usingColorSpace(.sRGB))
            let expected = try XCTUnwrap((green ? NSColor.systemGreen : .systemRed).usingColorSpace(.sRGB))
            XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.00001)
            XCTAssertEqual(outline.path?.boundingBoxOfPath, scene.mapper.sceneRect(forTile: tile, on: scene.screen).insetBy(dx: 1, dy: 1))
            for _ in 0..<30 { _ = renderer.update(appState: state, editor: editor, size: size) }
            XCTAssertEqual(scene.children.count, 13)
            XCTAssertEqual(preview.children.count, 2)
        }
        editor.selectedTile = cell(10)
        editor.tool = .select
        let oldScene = try XCTUnwrap(renderer.scene)
        editor.zoom(by: 1.25, size: size)
        let resized = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: CGSize(width: 900, height: 600)))
        XCTAssertTrue(resized === oldScene)
        XCTAssertEqual(resized.childNode(withName: "editor-selection")?.children.count, 1)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testHiddenFinderProjectionDoesNotBorrowLiveOccupancyOrReadFinder() async throws {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener), renderer = EditorCanvasRenderer()
        defer { state.shutdown() }
        let target = cell(14)
        state.placeCircuitComponent(CircuitComponent(kind: .output), at: target)
        provider.items = [DesktopItem(id: "cached", url: URL(fileURLWithPath: "/tmp/cached-editor"), displayName: "Cached",
            position: CGPoint(x: 928, y: 420), estimatedIconSize: nil, kind: .folder)]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        for _ in 0..<3 {
            let scene = try XCTUnwrap(renderer.update(appState: state, editor: editor, size: size))
            let badge = scene.childNode(withName: "circuit")?.children.compactMap {
                $0.childNode(withName: "output-occupancy:14,7") as? SKShapeNode
            }.first
            let color = try XCTUnwrap(badge?.strokeColor.usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, 0.5, accuracy: 0.01)
            XCTAssertEqual(color.greenComponent, color.redComponent, accuracy: 0.001)
            XCTAssertEqual(color.blueComponent, color.redComponent, accuracy: 0.001)
            editor.zoom(by: 1.05, size: size)
        }
        XCTAssertEqual(provider.calls, 1, "The editor consumes a snapshot; it never starts Finder reads")
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testNativeCanvasClickAndPanUseLocalUpwardCoordinates() throws {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        let view = EditorCanvasSurface(frame: CGRect(origin: .zero, size: size))
        window.isReleasedWhenClosed = false // Swift owns this test window through teardown.
        window.contentView = view
        view.editor = editor; view.appState = state
        defer { window.close() }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        XCTAssertFalse(view.isFlipped)
        let target = cell(10)
        editor.tool = .dust
        let center = try point(target, editor: editor)
        view.mouseDown(with: try event(.leftMouseDown, center))
        view.mouseUp(with: try event(.leftMouseUp, center))
        XCTAssertEqual(state.desktopWorld.circuit.components[target]?.kind, .dust)
        let world = state.desktopWorld
        editor.tool = .select
        editor.selectedTile = nil
        view.mouseDown(with: try event(.leftMouseDown, center))
        view.mouseUp(with: try event(.leftMouseUp, center))
        XCTAssertEqual(editor.selectedTile, target, "Navigate clicks select; drags pan without editing")
        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 300, y: 300)))
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 380, y: 260)))
        view.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 380, y: 260)))
        XCTAssertEqual(editor.camera.worldOrigin, WorldPoint(x: -2, y: 1))
        XCTAssertEqual(state.desktopWorld, world)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testUsefulCircuitAuthoredThroughToolsRunsOnDesktopWithFreshOccupant() async throws {
        let provider = EditorItemProvider(), opener = FixtureItemOpener(), editor = EditorSession()
        let state = state(provider, opener)
        defer { state.shutdown() }
        editor.direction = .east; editor.delay = .two
        for (x, tool) in [(10, EditorSession.Tool.button), (11, .dust), (12, .repeater), (13, .dust), (14, .output)] {
            editor.tool = tool
            editor.click(at: try point(cell(x), editor: editor), size: size, appState: state)
        }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(cell(10))
        await state.activationTask?.value
        for _ in 0..<4 { state.advanceCircuitTick(); XCTAssertTrue(opener.urls.isEmpty) }
        let item = DesktopItem(id: "editor-target", url: URL(fileURLWithPath: "/tmp/editor-target"), displayName: "Editor target",
            position: CGPoint(x: 928, y: 420), estimatedIconSize: nil, kind: .folder)
        provider.items = [item]
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [item.url])
        XCTAssertEqual(state.simulator.power(at: cell(14)), .full)
        for _ in 0..<30 { state.advanceCircuitTick() }
        XCTAssertEqual(opener.urls.count, 1)
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
    }

    @MainActor
    func testMainEditorCanBeHostedWithoutDesktopOrFinderAccess() {
        let provider = EditorItemProvider(), opener = FixtureItemOpener()
        let state = state(provider, opener)
        let view = NSHostingView(rootView: EditorView(appState: state))
        XCTAssertGreaterThanOrEqual(view.fittingSize.width, 900)
        XCTAssertGreaterThanOrEqual(view.fittingSize.height, 640)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertEqual(provider.calls, 0)
        view.frame = CGRect(x: 0, y: 0, width: 1200, height: 760)
        view.layoutSubtreeIfNeeded()

    }

    func testConstructionAreaIsExplicitAndPreservesAllEarlierFixtures() {
        let before = DeveloperPlacementFixture.makeWorld(), world = EditorConstructionArea.makeWorld()
        XCTAssertEqual(world.circuit, before.circuit)
        for (tile, value) in before.tiles { XCTAssertEqual(world.tiles[tile], value) }
        XCTAssertEqual(world.tiles.count, before.tiles.count + 80)
        XCTAssertNil(world.tiles[cell(26)])
        XCTAssertEqual(world.tiles[cell(10)], Tile(terrain: .grass))
    }
}
