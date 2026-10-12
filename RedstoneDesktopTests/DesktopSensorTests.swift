import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor private final class SensorFinderFixture: DesktopItemProviding {
    var items: [DesktopItem] = []
    var fail = false
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if fail { throw FinderReadError.permissionDenied }
        return items
    }
}
@MainActor private final class SensorBuildFixture: DesktopBuildPresenting {
    func show() {}
    func close() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {}
}
final class DesktopSensorTests: XCTestCase {
    private func p(_ x: Int, _ y: Int = 9) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    private func item(_ name: String, x: Int = 16, kind: DesktopItemKind = .file) -> DesktopItem {
        DesktopItem(id: name, url: URL(fileURLWithPath: "/tmp/" + name), displayName: "Finder hides extensions",
            position: CGPoint(x: x * 64 + 32, y: 900 - (9 * 64 + 32)), estimatedIconSize: nil, kind: kind)
    }
    func testFilterMatchesMetadataOnlyAndRejectsIncompleteOrOversizedValues() {
        let pdf = item("Report.PDF")
        XCTAssertTrue(FileSensorFilter(match: .fileExtension, value: " .pdf ").matches(pdf))
        XCTAssertFalse(FileSensorFilter(match: .fileExtension, value: "pdf").matches(item("folder.pdf", kind: .folder)))
        XCTAssertFalse(FileSensorFilter(match: .fileExtension, value: "pdf").matches(item("link.pdf", kind: .alias)))
        XCTAssertTrue(FileSensorFilter(match: .exactName, value: "report.pdf").matches(pdf))
        XCTAssertFalse(FileSensorFilter(match: .exactName, value: "Finder hides extensions").matches(pdf))
        XCTAssertTrue(FileSensorFilter().matches(item("Folder", kind: .folder)))
        for value in ["", ".", "   ", "\n", String(repeating: "a", count: 256)] {
            XCTAssertFalse(FileSensorFilter(match: .fileExtension, value: value).isValid)
        }
        XCTAssertTrue(FileSensorFilter(match: .exactName, value: ".hidden").isValid)
    }
    func testExtensionListsMatchAnyEntryIgnoringCaseSpacesAndLeadingDots() {
        let filter = FileSensorFilter(match: .fileExtension, value: " .PDF, png , .JpG, pdf ")
        XCTAssertTrue(filter.isValid)
        for name in ["Report.pdf", "photo.PNG", "photo.jpg"] { XCTAssertTrue(filter.matches(item(name)), name) }
        for name in ["notes.txt", "pdf", "image.jpeg", "report.pdf.txt"] { XCTAssertFalse(filter.matches(item(name)), name) }
        for kind in [DesktopItemKind.folder, .application, .alias, .unknown] {
            XCTAssertFalse(filter.matches(item("report.pdf", kind: kind)))
        }
    }
    func testExtensionListsRejectEmptyEntriesControlsAndOversizedDrafts() {
        for value in ["", ",", "pdf,", ",png", "pdf,,png", "pdf,  ,png", "pdf,.", "pdf,\n png", "pdf,\t png", String(repeating: "é", count: 128)] {
            let filter = FileSensorFilter(match: .fileExtension, value: value)
            XCTAssertFalse(filter.isValid, value)
            XCTAssertFalse(filter.matches(item("report.pdf")), value)
        }
        let filename = FileSensorFilter(match: .exactName, value: "Report, final.PDF")
        XCTAssertTrue(filename.matches(item("report, FINAL.pdf")), "Item names retain literal commas")
        XCTAssertFalse(filename.matches(item("Report.PDF")))
    }
    func testExtensionListsPersistInWorldsAndBlueprintsAndPreserveSingleExtensionSaves() throws {
        let old = Data(#"{"kind":"fileSensor","direction":"east","sensorFilter":{"match":"fileExtension","value":"pdf"}}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(CircuitComponent.self, from: old).sensorFilter.matches(item("report.PDF")))
        let filter = FileSensorFilter(match: .fileExtension, value: "pdf, .PNG, jpg")
        var document = WorldDocument(name: "Extension list", terrainProfile: .legacyFixtureV1)
        document.circuit.components[p(16)] = CircuitComponent(kind: .fileSensor, sensorFilter: filter)
        let restored = try JSONDecoder().decode(WorldDocument.self, from: JSONEncoder().encode(document)).restoredWorld()
        XCTAssertEqual(restored.circuit.components[p(16)]?.sensorFilter, filter)
        XCTAssertTrue(restored.circuit.components[p(16)]!.sensorFilter.matches(item("image.png")))
        let blueprint = try CircuitBlueprint.capture(name: "Extensions", components: document.circuit.components)
        let decoded = try JSONDecoder().decode(CircuitBlueprint.self, from: JSONEncoder().encode(blueprint)).rotatedClockwise()
        XCTAssertEqual(decoded.circuit.components.values.first?.sensorFilter, filter)
        document.circuit.components[p(16)]?.sensorFilter.value = "pdf,"
        XCTAssertThrowsError(try document.restoredWorld())
    }
    func testExtensionListOccupancyKeepsPowerWhenReplacingWithAnotherMatchingType() {
        let world = CircuitWorld(components: [p(16): CircuitComponent(kind: .fileSensor, sensorFilter: FileSensorFilter(match: .fileExtension, value: "pdf, png")), p(17): CircuitComponent(kind: .dust), p(18): CircuitComponent(kind: .output)])
        var simulator = CircuitSimulator(world: world)
        for (index, names) in [["notes.txt", "report.pdf"], ["image.PNG"], ["notes.txt"], ["image.png"]].enumerated() {
            let occupancy = DesktopOccupancySnapshot.available([p(16): DesktopOccupancy(coordinate: p(16), items: names.map { item($0) })])
            simulator.setDesktopSensors(DesktopSensorInputs.active(in: world, occupancy: occupancy))
            let events = simulator.advanceTick()
            XCTAssertEqual(events, index == 0 || index == 3 ? [.outputActivated(p(18))] : [])
            XCTAssertEqual(simulator.power(at: p(16)), index == 2 ? .off : .full)
        }
    }
    func testMappedOccupancySupportsMultipleItemsAndUnavailableFailsOff() {
        let world = CircuitWorld(components: [p(16): CircuitComponent(kind: .pressurePlate), p(17): CircuitComponent(kind: .fileSensor, sensorFilter: FileSensorFilter(match: .fileExtension, value: "pdf"))])
        let occupancy = DesktopOccupancySnapshot.available([
            p(16): DesktopOccupancy(coordinate: p(16), items: [item("one"), item("two")]),
            p(17): DesktopOccupancy(coordinate: p(17), items: [item("a.txt"), item("b.pdf")])])
        XCTAssertEqual(DesktopSensorInputs.active(in: world, occupancy: occupancy), [p(16), p(17)])
        XCTAssertTrue(DesktopSensorInputs.active(in: world, occupancy: .available([:])).isEmpty)
        XCTAssertTrue(DesktopSensorInputs.active(in: world, occupancy: .unavailable("denied")).isEmpty)
    }
    func testFreshnessBoundaryAndClockChangesFailOff() {
        let date = Date(timeIntervalSince1970: 500)
        XCTAssertFalse(DesktopSensorInputs.isFresh(lastRead: nil, now: date))
        XCTAssertTrue(DesktopSensorInputs.isFresh(lastRead: date, now: date.addingTimeInterval(2)))
        XCTAssertFalse(DesktopSensorInputs.isFresh(lastRead: date, now: date.addingTimeInterval(2.01)))
        XCTAssertFalse(DesktopSensorInputs.isFresh(lastRead: date, now: date.addingTimeInterval(-1)))
    }
    func testBothDetectorsEmitFullPowerAndOnlyNewRisingEdges() {
        for kind in [CircuitComponentKind.pressurePlate, .fileSensor] {
            let world = CircuitWorld(components: [p(16): CircuitComponent(kind: kind), p(17): CircuitComponent(kind: .dust), p(18): CircuitComponent(kind: .output)])
            var simulator = CircuitSimulator(world: world)
            simulator.setDesktopSensors([p(16), p(17)])
            XCTAssertEqual(simulator.activeDesktopSensors, [p(16)])
            XCTAssertEqual(simulator.advanceTick(), [.outputActivated(p(18))])
            XCTAssertEqual(simulator.power(at: p(16)), .full)
            XCTAssertEqual(simulator.power(at: p(17)), .full)
            for _ in 0..<30 { XCTAssertTrue(simulator.advanceTick().isEmpty) }
            simulator.setDesktopSensors([]); XCTAssertTrue(simulator.advanceTick().isEmpty)
            XCTAssertTrue(simulator.poweredTiles.isEmpty)
            simulator.setDesktopSensors([p(16)])
            XCTAssertEqual(simulator.advanceTick(), [.outputActivated(p(18))])
            XCTAssertFalse(simulator.pressButton(at: p(16)))
            XCTAssertFalse(simulator.toggleLever(at: p(16)))
        }
    }
    func testDetectorRearFeedsRepeaterAndInhibitsTorchWithTheirNormalDelays() {
        for kind in [CircuitComponentKind.repeater, .torch] {
            var simulator = CircuitSimulator(world: CircuitWorld(components: [p(16): CircuitComponent(kind: .pressurePlate), p(17): CircuitComponent(kind: kind, direction: .east)]))
            simulator.setDesktopSensors([p(16)])
            _ = simulator.advanceTick(); _ = simulator.advanceTick()
            XCTAssertEqual(simulator.power(at: p(17)), kind == .torch ? .full : .off)
            _ = simulator.advanceTick()
            XCTAssertEqual(simulator.power(at: p(17)), kind == .torch ? .off : .full)
            simulator.setDesktopSensors([])
            _ = simulator.advanceTick(); _ = simulator.advanceTick(); _ = simulator.advanceTick()
            XCTAssertEqual(simulator.power(at: p(17)), kind == .torch ? .full : .off)
        }
    }
    func testEncodingDefaultsAndBlueprintRotationPreserveFilters() throws {
        let old = Data(#"{"kind":"button","direction":"east"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CircuitComponent.self, from: old).sensorFilter, FileSensorFilter())
        let component = CircuitComponent(kind: .fileSensor, sensorFilter: FileSensorFilter(match: .exactName, value: "Notes.txt"))
        XCTAssertEqual(try JSONDecoder().decode(CircuitComponent.self, from: JSONEncoder().encode(component)), component)
        let blueprint = try CircuitBlueprint.capture(name: "Detector", components: [p(16): component])
        XCTAssertEqual(try blueprint.rotatedClockwise().circuit.components.values.first?.sensorFilter, component.sensorFilter)
        var invalid = component; invalid.sensorFilter = FileSensorFilter(match: .fileExtension, value: "")
        XCTAssertThrowsError(try JSONDecoder().decode(CircuitComponent.self, from: JSONEncoder().encode(invalid)))
        XCTAssertThrowsError(try CircuitBlueprint.capture(name: "Invalid", components: [p(16): invalid]))
    }
    func testWorldPersistenceValidatesSensorAndRestoresBothComponents() throws {
        var document = WorldDocument(name: "Sensors", terrainProfile: .legacyFixtureV1)
        let filter = FileSensorFilter(match: .exactName, value: "Inbox")
        document.circuit.components[p(16)] = CircuitComponent(kind: .fileSensor, sensorFilter: filter)
        document.circuit.components[p(17)] = CircuitComponent(kind: .pressurePlate)
        let restored = try JSONDecoder().decode(WorldDocument.self, from: JSONEncoder().encode(document)).restoredWorld()
        XCTAssertEqual(restored.circuit, document.circuit)
        XCTAssertTrue(CircuitSimulator(world: restored.circuit).activeDesktopSensors.isEmpty)
        document.circuit.components[p(16)]?.sensorFilter = FileSensorFilter(match: .exactName, value: "")
        XCTAssertThrowsError(try document.restoredWorld())
    }
    @MainActor private func app(_ provider: SensorFinderFixture, _ opener: FixtureItemOpener = FixtureItemOpener()) -> AppState {
        let screen = ScreenDescriptor(id: "sensors", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider), tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener,
            buildControllerFactory: { _, _, _ in SensorBuildFixture() }, finderReferenceProviding: { screen })
    }
    @MainActor func testRealAdapterUpdatesOnReadsAndHeldReplacementDoesNotReopenOutput() async throws {
        let provider = SensorFinderFixture(), opener = FixtureItemOpener(), app = app(provider, opener)
        defer { app.shutdown() }
        for (x, kind) in [(16, CircuitComponentKind.pressurePlate), (17, .dust), (18, .output)] {
            XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: kind), at: p(x)), .allowed)
        }
        app.toggleDesktopWorld()
        app.advanceCircuitTick(); XCTAssertEqual(app.simulator.power(at: p(16)), .off)
        provider.items = [item("plate.txt"), item("target-old", x: 18, kind: .folder)]
        await app.finderDiagnostics.readItems()
        app.advanceCircuitTick(); await app.activationTask?.value
        XCTAssertEqual(app.simulator.power(at: p(16)), .full)
        XCTAssertEqual(opener.urls, [item("target-old", x: 18).url])
        provider.items = [item("replacement.txt"), item("target-new", x: 18, kind: .folder)]
        await app.finderDiagnostics.readItems()
        app.advanceCircuitTick(); await app.activationTask?.value
        XCTAssertEqual(opener.urls.count, 1)
        provider.items = [item("target-new", x: 18, kind: .folder)]
        await app.finderDiagnostics.readItems(); app.advanceCircuitTick()
        XCTAssertEqual(app.simulator.power(at: p(16)), .off)
        provider.items.append(item("back.txt"))
        await app.finderDiagnostics.readItems(); app.advanceCircuitTick(); await app.activationTask?.value
        XCTAssertEqual(opener.urls.last, item("target-new", x: 18).url)
        XCTAssertEqual(opener.urls.count, 2)
        provider.fail = true
        await app.finderDiagnostics.readItems(); app.advanceCircuitTick()
        XCTAssertEqual(app.simulator.power(at: p(16)), .off)
        XCTAssertEqual(opener.urls.count, 2)
        app.shutdown(); XCTAssertTrue(app.simulator.activeDesktopSensors.isEmpty)
    }
    @MainActor func testSensorFilterEditsUndoAndRuntimePauseAndFailure() async throws {
        let provider = SensorFinderFixture(), app = app(provider)
        defer { app.shutdown() }
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .fileSensor), at: p(16)), .allowed)
        let pdf = FileSensorFilter(match: .fileExtension, value: "pdf")
        XCTAssertTrue(app.configureFileSensor(at: p(16), filter: pdf))
        XCTAssertTrue(app.undoCircuit()); XCTAssertEqual(app.editorWorld.circuit.components[p(16)]?.sensorFilter, FileSensorFilter())
        XCTAssertTrue(app.undoCircuit(redo: true)); XCTAssertEqual(app.editorWorld.circuit.components[p(16)]?.sensorFilter, pdf)
        app.toggleDesktopWorld()
        XCTAssertFalse(app.configureFileSensor(at: p(16), filter: FileSensorFilter()))
        provider.items = [item("note.txt")]; await app.finderDiagnostics.readItems(); app.advanceCircuitTick()
        XCTAssertEqual(app.simulator.power(at: p(16)), .off)
        provider.items = [item("note.PDF")]; await app.finderDiagnostics.readItems(); app.advanceCircuitTick()
        XCTAssertEqual(app.simulator.power(at: p(16)), .full)
        app.setSimulationPaused(true)
        provider.items = []; await app.finderDiagnostics.readItems(); app.advanceCircuitTick()
        XCTAssertEqual(app.simulator.power(at: p(16)), .full)
        app.setSimulationPaused(false); app.advanceCircuitTick()
        XCTAssertEqual(app.simulator.power(at: p(16)), .off)
    }
    @MainActor func testTestModeDetectorToggleResetDoesNotReadFinderOrSaveRuntimeInput() {
        let provider = SensorFinderFixture(), app = app(provider), editor = EditorSession(testScheduler: ManualCircuitTickScheduler())
        defer { editor.stopTesting(); app.shutdown() }
        for (x, kind) in [(16, CircuitComponentKind.pressurePlate), (17, .fileSensor)] { XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: kind), at: p(x)), .allowed) }
        let library = app.library
        editor.startTesting(app); editor.toggleTestPlayback(app)
        for x in [16,17] {
            let rect = editor.mapper(size: editor.viewport)!.screenRect(forTile: p(x))
            editor.click(at: CGPoint(x: rect.midX, y: rect.midY), size: editor.viewport, appState: app)
        }
        editor.stepTest(app)
        XCTAssertEqual(editor.circuitTest?.simulator.activeDesktopSensors, [p(16),p(17)])
        XCTAssertEqual(editor.circuitTest?.simulator.power(at: p(16)), .full)
        XCTAssertEqual(app.library, library); XCTAssertEqual(provider.calls, 0)
        editor.resetTest(app); XCTAssertTrue(editor.circuitTest!.simulator.activeDesktopSensors.isEmpty)
    }
    @MainActor func testBuildModeToolsAndFilterEditsPublishToCorrectWorld() throws {
        let provider = SensorFinderFixture(), app = app(provider)
        defer { app.shutdown() }
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession)
        session.selectTool(number: 8); XCTAssertEqual(session.component?.kind, .pressurePlate)
        session.selectTool(number: 9); XCTAssertEqual(session.component?.kind, .fileSensor)
        let rect = session.mapper.screenRect(forTile: p(16))
        app.buildClick(at: CGPoint(x: rect.midX, y: rect.midY), sessionID: session.id)
        let filter = FileSensorFilter(match: .exactName, value: "Folder")
        app.configureBuildFileSensor(at: p(16), filter: filter)
        XCTAssertEqual(app.desktopWorld.circuit.components[p(16)]?.sensorFilter, filter)
        XCTAssertEqual(app.selectedDocument.circuit.components[p(16)]?.sensorFilter, filter)
        XCTAssertEqual(provider.calls, 0)
    }
    @MainActor func testDetectorArtworkAndRendererUseDistinctPowerStates() throws {
        for kind in [CircuitComponentKind.pressurePlate, .fileSensor] {
            let off = try XCTUnwrap(CircuitTextureID.id(for: kind, powered: false))
            let on = try XCTUnwrap(CircuitTextureID.id(for: kind, powered: true))
            XCTAssertNotEqual(CircuitTextures.image(for: off).tiffRepresentation, CircuitTextures.image(for: on).tiffRepresentation)
            XCTAssertNotNil(BuiltInAssetProvider().texture(for: off.assetID))
        }
    }
}
