import AppKit
import XCTest
@testable import RedstoneDesktop

final class TerrainUpgradeTests: XCTestCase {
    private func store() throws -> WorldLibraryStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TerrainUpgrade-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return WorldLibraryStore(fileURL: root.appendingPathComponent("library.json"), legacyFileURL: root.appendingPathComponent("world.json"))
    }
    private func oldLibrary() -> WorldLibraryDocument {
        var document = WorldDocument(name: "Saved build", generation: WorldGenerationSettings(generationVersion: 1, seed: 94))
        document.circuit.components[WorldCoordinate(x: 23, y: 17)] = CircuitComponent(kind: .dust)
        var library = WorldLibraryDocument(world: document)
        library.areas.append(SavedArea(name: "Elsewhere", worldID: document.id, camera: SavedArea.homeCamera))
        return library
    }
    func testOldCircuitsArePreservedWithExactBackupAndIdempotentUpgrade() throws {
        let store = try store(), original = oldLibrary(), bytes = try JSONEncoder().encode(original)
        XCTAssertThrowsError(try original.validate()) // Real seed/coordinate formerly accepted, now a shrub.
        try bytes.write(to: store.fileURL)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.worlds[0].circuit, original.worlds[0].circuit)
        XCTAssertEqual(restored.areas, original.areas); XCTAssertEqual(restored.activeAreaID, original.activeAreaID)
        XCTAssertEqual(restored.worlds[0].generation.generationVersion, 3)
        XCTAssertEqual(restored.worlds[0].terrainOverrides[WorldCoordinate(x: 23, y: 17)], Tile(terrain: .dryGrass))
        let backups = try FileManager.default.contentsOfDirectory(at: store.fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("library-before-terrain-upgrade-") }
        XCTAssertEqual(backups.count, 1); XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), bytes)
        XCTAssertEqual(try store.load(), restored)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path).count, 2)
    }
    func testOlderExportsReceiveTheSameUpgradeWithoutChangingSource() throws {
        let original = oldLibrary(), bytes = try JSONEncoder().encode(original), source = try store().fileURL
        try bytes.write(to: source)
        let decoded = try LibraryImport.read(from: source)
        XCTAssertEqual(decoded.worlds[0].generation.generationVersion, 3)
        XCTAssertEqual(decoded.worlds[0].circuit, original.worlds[0].circuit)
        XCTAssertEqual(decoded.areas, original.areas)
        XCTAssertEqual(bytes, try Data(contentsOf: source))
        try decoded.validate()
    }

    func testUpgradeDoesNotAcceptPaintedWaterMalformedComponentsOrCurrentInvalidLibrary() throws {
        for failure in 0..<4 {
            let store = try store(); var library = oldLibrary()
            let coordinate = WorldCoordinate(x: 23, y: 17)
            if failure == 0 { library.worlds[0].terrainOverrides[coordinate] = Tile(terrain: .deepWater) }
            if failure == 1 { library.worlds[0].circuit.components[coordinate] = CircuitComponent(kind: .empty) }
            if failure == 2 { library.worlds[0].generation.generationVersion = 3 }
            if failure == 3 { library.worlds[0].activeLevers = [coordinate] }
            let bytes = try JSONEncoder().encode(library); try bytes.write(to: store.fileURL)
            XCTAssertThrowsError(try store.load()); XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path), ["library.json"])
        }
    }
    func testUpgradeClearsLeavesUnderLegacyFixtureOutskirtsAndProtectsPaintedGround() throws {
        var document = WorldDocument(name: "Original build", generation: WorldGenerationSettings(generationVersion: 2, seed: 9000), terrainProfile: .legacyFixtureV1)
        let coordinate = WorldCoordinate(x: 18, y: 5), painted = WorldCoordinate(x: 90, y: 90)
        document.circuit.components[coordinate] = CircuitComponent(kind: .repeater, direction: .west, repeaterDelay: .four)
        document.terrainOverrides[painted] = Tile(terrain: .sand)
        let upgraded = try WorldLibraryDocument(world: document).upgradingTerrain()
        XCTAssertEqual(upgraded.worlds[0].terrainOverrides[coordinate], Tile(terrain: .grass))
        XCTAssertEqual(upgraded.worlds[0].terrainOverrides[painted], Tile(terrain: .sand))
        XCTAssertEqual(upgraded.worlds[0].circuit, document.circuit)
    }
    @MainActor
    func testAfterUpgradeTerrainMouseReleasePersistsAndDesktopAreaSwitchSaves() throws {
        let store = try store(); try JSONEncoder().encode(oldLibrary()).write(to: store.fileURL)
        let screen = ScreenDescriptor(id: "upgrade", frame: CGRect(x: 0, y: 0, width: 800, height: 600), backingScale: 1)
        let app = AppState(screenProviding: { screen }, libraryStore: store, automaticallyRefreshFinder: false)
        defer { app.shutdown() }
        XCTAssertTrue(app.canSaveWorld); XCTAssertFalse(app.isEditorConfigurationLocked)
        let editor = EditorSession(); editor.tool = .terrain; editor.terrainBrush = .lava; editor.terrainBrushSize = 1
        let coordinate = WorldCoordinate(x: 4, y: 4), mapper = try XCTUnwrap(editor.mapper(size: editor.viewport))
        let rect = mapper.screenRect(forTile: coordinate), point = CGPoint(x: rect.midX, y: rect.midY)
        editor.terrainInput(at: point, size: editor.viewport, phase: .begin, appState: app)
        XCTAssertNil(app.selectedDocument.terrainOverrides[coordinate])
        editor.terrainInput(at: point, size: editor.viewport, phase: .end, appState: app)
        XCTAssertEqual(app.selectedDocument.terrainOverrides[coordinate], Tile(terrain: .lava))
        let area = app.library.areas[1]
        XCTAssertTrue(app.selectArea(area.id)); XCTAssertTrue(app.activateSelectedArea())
        XCTAssertEqual(try store.load()?.activeAreaID, area.id)
        XCTAssertEqual(try store.load()?.worlds[0].terrainOverrides[coordinate], Tile(terrain: .lava))
    }
    @MainActor
    func testRecoveryModeDisallowsTerrainPreviewAndExplainsBlockedActivation() throws {
        let store = try store(); try Data("malformed".utf8).write(to: store.fileURL)
        let app = AppState(libraryStore: store); defer { app.shutdown() }
        let editor = EditorSession(); editor.tool = .terrain
        editor.terrainInput(at: CGPoint(x: 100, y: 100), size: editor.viewport, phase: .begin, appState: app)
        XCTAssertNil(editor.terrainStroke); XCTAssertTrue(editor.status.contains("saved library"))
        XCTAssertFalse(app.activateSelectedArea()); XCTAssertTrue(app.areaStatus.contains("saved library"))
        XCTAssertFalse(app.createWorld(name: "Unsaved", generation: WorldGenerationSettings(seed: 1)))
    }
}
