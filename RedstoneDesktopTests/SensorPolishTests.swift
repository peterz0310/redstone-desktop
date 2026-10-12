import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor private final class SensorPolishPresenter: DesktopBuildPresenting {
    func show() {}
    func close() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {}
}

final class SensorPolishTests: XCTestCase {
    private let tile = WorldCoordinate(x: 16, y: 9)
    private let screen = ScreenDescriptor(id: "sensor", frame: CGRect(x: -1280, y: -200, width: 1280, height: 800), backingScale: 2)
    @MainActor private func app() -> AppState {
        AppState(screenProviding: { self.screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            tickScheduler: ManualCircuitTickScheduler(), buildControllerFactory: { _, _, _ in SensorPolishPresenter() })
    }

    func testAnyItemUsesWoodAndBothFiltersUseStoneInBothPowerStates() throws {
        for powered in [false, true] {
            let wood: CircuitTextureID = powered ? .plateOn : .plateOff
            let stone: CircuitTextureID = powered ? .sensorOn : .sensorOff
            XCTAssertEqual(CircuitTextureID.id(for: .pressurePlate, powered: powered), wood)
            XCTAssertEqual(CircuitTextureID.id(for: .fileSensor, powered: powered), wood)
            for match in [FileSensorMatch.fileExtension, .exactName] {
                XCTAssertEqual(CircuitTextureID.id(for: .fileSensor, powered: powered, sensorFilter: FileSensorFilter(match: match, value: "pdf")), stone)
            }
        }
    }

    @MainActor func testChangingAPlateToFilteredDetectionIsUndoableAndPersists() throws {
        let app = app(); defer { app.shutdown() }
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .pressurePlate), at: tile), .allowed)
        let original = try XCTUnwrap(app.editorWorld.circuit.components[tile])
        let filter = FileSensorFilter(match: .fileExtension, value: "pdf")
        XCTAssertTrue(app.configureFileSensor(at: tile, filter: filter))
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.kind, .fileSensor)
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.sensorFilter, filter)
        let reopened = try LibraryImport.decode(JSONEncoder().encode(app.library))
        XCTAssertEqual(reopened.worlds.first?.circuit.components[tile]?.sensorFilter, filter)
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.editorWorld.circuit.components[tile], original)
        XCTAssertTrue(app.undoCircuit(redo: true))
        XCTAssertTrue(app.configureFileSensor(at: tile, filter: FileSensorFilter()))
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.sensorFilter.match, .anyItem)
        let before = app.library
        XCTAssertFalse(app.configureFileSensor(at: tile, filter: FileSensorFilter(match: .exactName)))
        XCTAssertEqual(app.library, before); XCTAssertFalse(app.finderDiagnostics.hasRead)
    }

    @MainActor func testSavingExtensionListsIsUndoableInEditorAndDesktopAndRejectsInvalidLists() throws {
        let app = app(); defer { app.shutdown() }
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .fileSensor), at: tile), .allowed)
        let filter = FileSensorFilter(match: .fileExtension, value: "pdf, .PNG")
        XCTAssertTrue(app.configureFileSensor(at: tile, filter: filter))
        let saved = app.library
        XCTAssertFalse(app.configureFileSensor(at: tile, filter: FileSensorFilter(match: .fileExtension, value: "pdf,")))
        XCTAssertEqual(app.library, saved)
        XCTAssertTrue(app.undoCircuit())
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.sensorFilter, FileSensorFilter())
        XCTAssertTrue(app.undoCircuit(redo: true))
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.sensorFilter, filter)
        XCTAssertTrue(app.enterDesktopBuildMode())
        let desktopFilter = FileSensorFilter(match: .fileExtension, value: "txt, md")
        app.configureBuildFileSensor(at: tile, filter: desktopFilter)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.sensorFilter, desktopFilter)
        XCTAssertEqual(app.selectedDocument.circuit.components[tile]?.sensorFilter, desktopFilter)
        let desktopSaved = app.library
        app.configureBuildFileSensor(at: tile, filter: FileSensorFilter(match: .fileExtension, value: "txt,,md"))
        XCTAssertEqual(app.library, desktopSaved)
        let reopened = try LibraryImport.decode(JSONEncoder().encode(app.library))
        XCTAssertEqual(reopened.worlds.first?.circuit.components[tile]?.sensorFilter, desktopFilter)
        app.exitDesktopBuildMode()
        XCTAssertTrue(app.undoCircuit())
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.sensorFilter, filter)
        XCTAssertNil(app.activationTask); XCTAssertFalse(app.finderDiagnostics.hasRead)
    }

    @MainActor func testContextShortcutsOpenCorrectDraftAndAnyItemSavesWithoutActions() throws {
        let app = app(), editor = EditorSession(); defer { app.shutdown() }
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .pressurePlate), at: tile), .allowed)
        editor.prepareContext(at: tile, appState: app)
        let original = app.library
        for match in [FileSensorMatch.fileExtension, .exactName] {
            XCTAssertTrue(editor.contextOptions(at: tile, appState: app).contains { $0.action == .sensorSource(match) && $0.enabled })
            editor.performContext(.sensorSource(match), at: tile, worldID: app.selectedWorldID, appState: app)
            XCTAssertEqual(editor.sidebarTab, .inspector)
            XCTAssertEqual(editor.sensorEditRequest?.match, match)
            XCTAssertEqual(editor.sensorEditRequest?.tile, tile)
            XCTAssertEqual(app.library, original, "An unfinished filter is never saved")
        }
        XCTAssertTrue(app.configureFileSensor(at: tile, filter: FileSensorFilter(match: .exactName, value: "Inbox")))
        editor.performContext(.sensorSource(.anyItem), at: tile, worldID: app.selectedWorldID, appState: app)
        XCTAssertEqual(app.editorWorld.circuit.components[tile]?.sensorFilter, FileSensorFilter())
        XCTAssertNil(app.activationTask); XCTAssertFalse(app.finderDiagnostics.hasRead)
        editor.selectedTile = WorldCoordinate(x: 17, y: 9); XCTAssertNil(editor.sensorEditRequest)
        editor.startTesting(app)
        XCTAssertFalse(editor.contextOptions(at: tile, appState: app).contains { $0.action == .sensorSource(.anyItem) && $0.enabled })
        editor.stopTesting()
    }

    @MainActor func testDesktopNativeSensorMenuSupportsSourceChangesAndRejectsStaleSession() throws {
        let app = app(); defer { app.shutdown() }
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .pressurePlate), at: tile), .allowed)
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession)
        let controller = DesktopBuildController(session: session, screen: screen, appState: app)
        defer { controller.close() }
        let rect = session.mapper.sceneRect(forTile: tile, on: screen)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: CGPoint(x: rect.midX, y: rect.midY), modifierFlags: [], timestamp: 0, windowNumber: controller.inputWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let before = app.library
        let menu = try XCTUnwrap(controller.surface.menu(for: event))
        XCTAssertEqual(menu.items.map(\.title), ["Detect: Any item", "Detect: File extension…", "Detect: Item name…", "", "Delete Component"])
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(menu.items[1].action), to: menu.items[1].target, from: menu.items[1]))
        XCTAssertEqual(session.sensorEditRequest?.match, .fileExtension)
        XCTAssertEqual(app.library, before)
        app.configureBuildFileSensor(at: tile, filter: FileSensorFilter(match: .fileExtension, value: "pdf"))
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.kind, .fileSensor)
        XCTAssertEqual(app.selectedDocument.circuit.components[tile]?.sensorFilter.value, "pdf")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(menu.items[0].action), to: menu.items[0].target, from: menu.items[0]))
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.sensorFilter.match, .anyItem)
        app.exitDesktopBuildMode()
        let after = app.library
        NSApp.sendAction(try XCTUnwrap(menu.items[4].action), to: menu.items[4].target, from: menu.items[4])
        XCTAssertEqual(app.library, after, "Old menu actions cannot modify a later session")
        XCTAssertNil(app.activationTask); XCTAssertFalse(app.finderDiagnostics.hasRead)
    }

    @MainActor func testRendererAndBlueprintPreviewFollowSavedFilterAndExportPlateArtwork() throws {
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let renderer = CircuitRenderer(), layer = SKNode()
        var circuit = CircuitWorld()
        circuit.components[tile] = CircuitComponent(kind: .fileSensor)
        circuit.components[WorldCoordinate(x: 17, y: 9)] = CircuitComponent(kind: .fileSensor, sensorFilter: FileSensorFilter(match: .fileExtension, value: "pdf"))
        renderer.render(circuit, poweredTiles: [], occupancy: .unavailable("fixture"), mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), into: layer)
        XCTAssertEqual(renderer.textures.cachedTextureCount, 2, "Any item and filtered sensors choose different material textures")
        var blueprint = try CircuitBlueprint.capture(name: "Sensor", components: [tile: CircuitComponent(kind: .fileSensor)])
        let wood = try XCTUnwrap(BlueprintPreviewImage.image(for: blueprint).tiffRepresentation)
        blueprint.circuit.components[WorldCoordinate(x: 0, y: 0)]?.sensorFilter = FileSensorFilter(match: .exactName, value: "Inbox")
        let stone = try XCTUnwrap(BlueprintPreviewImage.image(for: blueprint).tiffRepresentation)
        XCTAssertNotEqual(wood, stone)
        let art: [CircuitTextureID] = [.plateOff, .plateOn, .sensorOff, .sensorOn]
        let sheet = NSImage(size: CGSize(width: 256, height: 64), flipped: false) { _ in
            NSColor.darkGray.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 256, height: 64)).fill()
            for (index, id) in art.enumerated() { CircuitTextures.image(for: id).draw(in: CGRect(x: index * 64, y: 0, width: 64, height: 64)) }
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(sheet.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/redstone-sensor-art.png"))
    }

    func testJavaPlatesUseOakAndStoneMaterialsWithDistinctPressedStates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SensorArt-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("source/assets/minecraft/textures/block")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, color) in [("oak_planks", [UInt8(180), 120, 60, 255]), ("stone", [UInt8(140), 140, 140, 255])] {
            try RasterAsset(width: 16, height: 16, pixels: Array(repeating: color, count: 256).flatMap { $0 }).pngData().write(to: folder.appendingPathComponent(name + ".png"))
        }
        let imported = try JavaTextureImporter.importTextures(from: root.appendingPathComponent("source"), cacheRoot: root.appendingPathComponent("cache"))
        for (off, on) in [(TextureAssetID.redstonePlateOff, TextureAssetID.redstonePlateOn), (.redstoneSensorOff, .redstoneSensorOn)] {
            XCTAssertNotEqual(try XCTUnwrap(imported.pack.textures[off]).pixels, try XCTUnwrap(imported.pack.textures[on]).pixels)
        }
        XCTAssertEqual(imported.record.mappings["redstonePlateOff"], "assets/minecraft/textures/block/oak_planks.png")
        XCTAssertEqual(imported.record.mappings["redstoneSensorOff"], "assets/minecraft/textures/block/stone.png")
    }
}
