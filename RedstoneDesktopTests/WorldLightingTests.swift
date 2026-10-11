import SpriteKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

final class WorldLightingTests: XCTestCase {
    func testCycleWrapsAtPersistedAnchorAndDayNightRemainFixed() throws {
        let settings = WorldLightingSettings(mode: .cycle, cycleMinutes: 2, startPhase: 0.25, anchorTime: 100)
        try settings.validate()
        XCTAssertEqual(settings.daylight(at: 100), 1)
        XCTAssertEqual(settings.daylight(at: 160), 0.22)
        XCTAssertEqual(settings.phase(at: 220), 0.25, accuracy: 0.0001)
        XCTAssertEqual(settings.phase(at: -20), 0.25, accuracy: 0.0001)
        XCTAssertEqual(settings.phase(at: .infinity), 0.25)
        XCTAssertEqual(WorldLightingSettings(mode: .day).daylight(at: 160), 1)
        XCTAssertEqual(WorldLightingSettings(mode: .night).daylight(at: 100), 0.22)
        XCTAssertEqual(try JSONDecoder().decode(WorldLightingSettings.self, from: JSONEncoder().encode(settings)), settings)
        for invalid in [WorldLightingSettings(cycleMinutes: 1), WorldLightingSettings(startPhase: 2), WorldLightingSettings(anchorTime: .nan)] {
            XCTAssertThrowsError(try invalid.validate())
        }
    }
    func testFixedTimeUsesCycleLightingButNeverAdvancesAndSurvivesReopening() throws {
        for phase in [0.0, 0.125, 0.25, 0.5, 0.525, 0.75, 1.0] {
            let fixed = WorldLightingSettings(mode: .fixed, startPhase: phase, anchorTime: 100)
            let cycle = WorldLightingSettings(mode: .cycle, startPhase: phase, anchorTime: 100)
            XCTAssertEqual(fixed.daylight(at: 100), cycle.daylight(at: 100), accuracy: 0.000001)
            for time in [-1000000.0, 100, 500, 1000000] {
                XCTAssertEqual(fixed.phase(at: time), phase)
                XCTAssertEqual(fixed.daylight(at: time), fixed.daylight(at: 100))
            }
            var document = WorldDocument(); document.lighting = fixed
            let library = WorldLibraryDocument(world: document)
            let reopened = try LibraryImport.decode(JSONEncoder().encode(library))
            XCTAssertEqual(reopened.worlds[0].lighting, fixed)
            XCTAssertEqual(try reopened.worlds[0].restoredWorld().lighting, fixed)
        }
    }

    func testLightFallsOffSmoothlyAndPowerAttenuatesIt() {
        XCTAssertEqual(WorldLightFalloff.intensity(dx: 0, dy: 0, radius: 5, strength: 1), 1)
        XCTAssertGreaterThan(WorldLightFalloff.intensity(dx: 1, dy: 0, radius: 5, strength: 1), WorldLightFalloff.intensity(dx: 3, dy: 0, radius: 5, strength: 1))
        XCTAssertEqual(WorldLightFalloff.intensity(dx: 5, dy: 0, radius: 5, strength: 1), 0)
        XCTAssertEqual(WorldLightFalloff.intensity(dx: .max, dy: .min, radius: 5, strength: 1), 0)
        XCTAssertEqual(WorldLightFalloff.intensity(dx: 0, dy: 0, radius: 5, strength: 0.2), 0.2)
    }
    func testOldWorldsDefaultToDayAndNewSettingsRoundTripWithImport() throws {
        var document = WorldDocument(); document.lighting = WorldLightingSettings(mode: .cycle, cycleMinutes: 7, anchorTime: 123)
        let bytes = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(WorldDocument.self, from: bytes), document)
        XCTAssertEqual(try document.restoredWorld().lighting, document.lighting)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json["formatVersion"] = 4; json.removeValue(forKey: "lighting")
        XCTAssertEqual(try JSONDecoder().decode(WorldDocument.self, from: JSONSerialization.data(withJSONObject: json)).lighting.mode, .day)
        json["formatVersion"] = 5
        XCTAssertThrowsError(try JSONDecoder().decode(WorldDocument.self, from: JSONSerialization.data(withJSONObject: json)))
        document.lighting.cycleMinutes = 0
        XCTAssertThrowsError(try document.restoredWorld())
    }
    func testLibrarySaveLoadExportImportPreserveClockAndIndependentCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorldLights-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorldLibraryStore(fileURL: root.appendingPathComponent("library.json"), legacyFileURL: root.appendingPathComponent("old.json"))
        var document = WorldDocument(); document.lighting = WorldLightingSettings(mode: .cycle, cycleMinutes: 9, startPhase: 0.75, anchorTime: 999, localLights: false)
        let library = WorldLibraryDocument(world: document)
        try store.save(library)
        XCTAssertEqual(try store.load(), library)
        let incoming = try LibraryImport.read(from: store.fileURL)
        let combined = try LibraryImport.adding(incoming, to: WorldLibraryDocument())
        XCTAssertEqual(combined.worlds.last?.lighting, document.lighting)
        XCTAssertNotEqual(combined.worlds.last?.id, document.id)
        XCTAssertEqual(combined.worlds.first?.lighting.mode, .day)
    }

    @MainActor func testWorldSettingChangesDoNotAffectOtherWorldsOrCircuitState() throws {
        let app = AppState(automaticallyRefreshFinder: false); defer { app.shutdown() }
        let first = app.selectedWorldID, circuit = app.selectedDocument.circuit, tick = app.simulationTick
        XCTAssertTrue(app.updateWorldLighting(first, settings: WorldLightingSettings(mode: .night)))
        XCTAssertEqual(app.editorWorld.lighting?.mode, .night)
        XCTAssertEqual(app.desktopWorld.lighting?.mode, .night)
        XCTAssertEqual(app.selectedDocument.circuit, circuit); XCTAssertEqual(app.simulationTick, tick)
        XCTAssertTrue(app.createWorld(name: "Other", generation: WorldGenerationSettings(seed: 7)))
        XCTAssertEqual(app.selectedDocument.lighting.mode, .day)
        XCTAssertEqual(app.library.world(id: first)?.lighting.mode, .night)
        XCTAssertEqual(app.desktopWorld.lighting?.mode, .night)
    }
    @MainActor func testSceneRetainsLightingLayerAcrossViewportChangesAndDaylightDoesNotRebakeTerrain() throws {
        let screen = ScreenDescriptor(id: "scene", frame: CGRect(x: 0, y: 0, width: 320, height: 320), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 32))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        scene.lightingTimeProviding = { 100 }
        var document = WorldDocument(); document.lighting = WorldLightingSettings(mode: .cycle, cycleMinutes: 2, startPhase: 0.75, anchorTime: 100)
        scene.updateWorld(try document.restoredWorld())
        XCTAssertFalse(try XCTUnwrap(scene.childNode(withName: "world-lighting")).isHidden)
        let builds = scene.terrainMetrics.textureBuilds, masks = scene.lightingTextureBuilds
        for i in 0..<100 { scene.lightingTimeProviding = { Double(i + 100) }; scene.update(Double(i)) }
        XCTAssertEqual(scene.terrainMetrics.textureBuilds, builds); XCTAssertEqual(scene.lightingTextureBuilds, masks)
        scene.updateViewport(screen: screen, mapper: mapper)
        XCTAssertNotNil(scene.childNode(withName: "world-lighting"))
    }

    @MainActor func testRenderedNightLavaPowerAndToggleAndTimeReuseMasks() throws {
        let screen = ScreenDescriptor(id: "lights", frame: CGRect(x: -10, y: -20, width: 640, height: 512), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 16))
        let root = SKNode(), layer = SKNode(), renderer = WorldLightingRenderer()
        let ground = SKSpriteNode(color: .white, size: screen.frame.size); ground.anchorPoint = .zero
        root.addChild(ground); layer.zPosition = 1; root.addChild(layer)
        let source = WorldCoordinate(x: 6, y: 6)
        var world = World(); world.lighting = WorldLightingSettings(mode: .night)
        world.circuit.components[source] = CircuitComponent(kind: .dust)
        let view = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        func color(at tile: WorldCoordinate? = nil) throws -> NSColor {
            let rendered = try XCTUnwrap(view.texture(from: root, crop: CGRect(origin: .zero, size: screen.frame.size)))
            let bitmap = NSBitmapImageRep(cgImage: rendered.cgImage())
            let rect = mapper.sceneRect(forTile: tile ?? source, on: screen)
            return try XCTUnwrap(bitmap.colorAt(x: Int(rect.midX * Double(bitmap.pixelsWide) / screen.frame.width), y: bitmap.pixelsHigh - 1 - Int(rect.midY * Double(bitmap.pixelsHigh) / screen.frame.height))?.usingColorSpace(.deviceRGB))
        }
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, time: 0)
        let dark = try color().redComponent
        XCTAssertLessThan(dark, 0.4)
        renderer.render(world: world, lava: [source], power: [:], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertGreaterThan(try color().redComponent, dark + 0.4)
        renderer.render(world: world, lava: [], power: [source: .full], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertGreaterThan(try color().redComponent, dark + 0.4)
        let seam = WorldCoordinate(x: 31, y: 6)
        world.circuit.components[seam] = CircuitComponent(kind: .dust)
        renderer.render(world: world, lava: [], power: [seam: .full], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertGreaterThan(try color(at: seam).redComponent, dark + 0.4)
        XCTAssertGreaterThan(try color(at: WorldCoordinate(x: 32, y: 6)).redComponent, dark + 0.3)
        let builds = renderer.textureBuilds
        for tick in 0..<1000 { renderer.advance(settings: WorldLightingSettings(mode: .cycle, cycleMinutes: 2), time: Double(tick)) }
        XCTAssertEqual(renderer.textureBuilds, builds)
        world.lighting?.localLights = false
        renderer.render(world: world, lava: [source], power: [source: .full], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertEqual(try color().redComponent, dark, accuracy: 0.03)
        world.lighting?.mode = .day
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, time: 0)
        XCTAssertTrue(layer.isHidden); XCTAssertGreaterThan(try color().redComponent, 0.9)
        world.lighting = WorldLightingSettings(mode: .fixed, startPhase: 0)
        renderer.render(world: world, lava: [], power: [:], mapper: mapper, screen: screen, into: layer, time: 0)
        let dawn = try color().redComponent
        XCTAssertGreaterThan(dawn, dark + 0.15); XCTAssertLessThan(dawn, 0.7)
        let fixedBuilds = renderer.textureBuilds
        renderer.advance(settings: try XCTUnwrap(world.lighting), time: 999999)
        XCTAssertEqual(try color().redComponent, dawn, accuracy: 0.01)
        XCTAssertEqual(renderer.textureBuilds, fixedBuilds)

    }
    func testFullRealDayCyclePersistsAndWrapsWithoutDrifting() throws {
        let clock = WorldLightingSettings(mode: .cycle, cycleMinutes: 1440, startPhase: 0.25, anchorTime: 100)
        try clock.validate()
        XCTAssertEqual(clock.phase(at: 100 + 86400), 0.25, accuracy: 0.000001)
        XCTAssertEqual(clock.daylight(at: 100 + 43200), 0.22, accuracy: 0.000001)
        let restored = try JSONDecoder().decode(WorldLightingSettings.self, from: JSONEncoder().encode(clock))
        XCTAssertEqual(restored.phase(at: 100 + 365 * 86400), 0.25, accuracy: 0.000001)
        XCTAssertThrowsError(try WorldLightingSettings(cycleMinutes: 1441).validate())
        XCTAssertThrowsError(try WorldLightingSettings(cycleMinutes: .infinity).validate())
    }

    func testSystemTimeMatchesLocalHoursAndIgnoresCycleAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let clock = WorldLightingSettings(mode: .systemTime, cycleMinutes: 2, startPhase: 0.123, anchorTime: 999)
        for (hour, expected) in [(0, 0.75), (6, 0.0), (12, 0.25), (18, 0.5), (23, 17.0 / 24)] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: hour)))
            XCTAssertEqual(clock.phase(at: date.timeIntervalSince1970, calendar: calendar), expected, accuracy: 0.000001)
            XCTAssertEqual(clock.daylight(at: date.timeIntervalSince1970, calendar: calendar),
                WorldLightingSettings(mode: .fixed, startPhase: expected).daylight(at: 0), accuracy: 0.000001)
            XCTAssertEqual(clock.phase(at: date.addingTimeInterval(86400 * 7).timeIntervalSince1970, calendar: calendar), expected, accuracy: 0.000001)
        }
        XCTAssertEqual(clock.phase(at: .infinity, calendar: calendar), clock.startPhase)
        XCTAssertEqual(clock.phase(at: .greatestFiniteMagnitude, calendar: calendar), clock.startPhase)
    }

    func testSystemTimeFollowsTimeZoneAndBothDaylightSavingTransitions() throws {
        let clock = WorldLightingSettings(mode: .systemTime)
        let formatter = ISO8601DateFormatter()
        func time(_ iso: String) throws -> Double { try XCTUnwrap(formatter.date(from: iso)).timeIntervalSince1970 }
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        var utc = chicago; utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let winter = try time("2026-01-11T18:00:00Z")
        XCTAssertEqual(clock.phase(at: winter, calendar: chicago), 0.25, accuracy: 0.000001)
        XCTAssertEqual(clock.phase(at: winter, calendar: utc), 0.5, accuracy: 0.000001)
        let beforeSpring = clock.phase(at: try time("2026-03-08T07:59:00Z"), calendar: chicago)
        let afterSpring = clock.phase(at: try time("2026-03-08T08:01:00Z"), calendar: chicago)
        XCTAssertEqual(afterSpring - beforeSpring, 62.0 / 1440, accuracy: 0.000001)
        let beforeFall = clock.phase(at: try time("2026-11-01T06:59:00Z"), calendar: chicago)
        let afterFall = clock.phase(at: try time("2026-11-01T07:01:00Z"), calendar: chicago)
        XCTAssertEqual(afterFall - beforeFall, -58.0 / 1440, accuracy: 0.000001)
    }

    func testSystemTimeSurvivesLibrarySaveReopenExportAndImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SystemTime-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorldLibraryStore(fileURL: root.appendingPathComponent("library.json"), legacyFileURL: root.appendingPathComponent("old.json"))
        var world = WorldDocument(); world.lighting = WorldLightingSettings(mode: .systemTime, localLights: false)
        let library = WorldLibraryDocument(world: world)
        try store.save(library)
        XCTAssertEqual(try store.load(), library)
        let imported = try LibraryImport.adding(LibraryImport.read(from: store.fileURL), to: WorldLibraryDocument())
        XCTAssertEqual(imported.worlds.last?.lighting, world.lighting)
        XCTAssertEqual(imported.worlds.first?.lighting.mode, .day)
    }

    @MainActor func testLightingControlsFitEveryModeIncludingFullRealDayWithoutStartingDesktop() {
        let state = AppState(); defer { state.shutdown() }
        for mode in WorldLightingSettings.Mode.allCases {
            var world = state.selectedDocument
            world.lighting = WorldLightingSettings(mode: mode, cycleMinutes: 1440)
            let host = NSHostingView(rootView: WorldLightingSettingsView(appState: state, world: world))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 450)
            XCTAssertLessThan(host.fittingSize.height, 650)
            XCTAssertEqual(state.finderDiagnostics.readAttempts, 0)
            XCTAssertFalse(state.isDesktopWorldEnabled)
        }
    }

}
