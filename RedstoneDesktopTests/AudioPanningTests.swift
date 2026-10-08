import AVFoundation
import XCTest
@testable import RedstoneDesktop

final class AudioPanningTests: XCTestCase {
    func testLeftCenterRightAndClampingOnOffsetCanvas() {
        let canvas = CGRect(x: -1280, y: 100, width: 1280, height: 800)
        XCTAssertEqual(AudioPanning.pan(screenPoint: CGPoint(x: -1280, y: 100), canvas: canvas), -1)
        XCTAssertEqual(AudioPanning.pan(screenPoint: CGPoint(x: -640, y: 100), canvas: canvas), 0)
        XCTAssertEqual(AudioPanning.pan(screenPoint: CGPoint(x: 0, y: 100), canvas: canvas), 1)
        XCTAssertEqual(AudioPanning.pan(screenPoint: CGPoint(x: -4000, y: 100), canvas: canvas), -1)
        XCTAssertEqual(AudioPanning.pan(screenPoint: CGPoint(x: 4000, y: 100), canvas: canvas), 1)
    }
    func testInvalidInputIsSilent() {
        XCTAssertNil(AudioPanning.pan(screenPoint: CGPoint(x: CGFloat.nan, y: 0), canvas: CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertNil(AudioPanning.pan(screenPoint: .zero, canvas: .zero))
        XCTAssertNil(AudioPanning.pan(screenPoint: .zero, canvas: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)))
    }
    func testWorldTileCentersUseMapperAndDiscardOffscreenInBothAxes() throws {
        let mapper = try CoordinateMapper(canvasFrame: CGRect(x: -400, y: 100, width: 400, height: 400),
            camera: CameraState(worldOrigin: WorldPoint(x: -2, y: -2), pointsPerTile: 40))
        XCTAssertEqual(try XCTUnwrap(AudioPanning.pan(tile: WorldCoordinate(x: -2, y: 0), mapper: mapper)), -0.9, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(AudioPanning.pan(tile: WorldCoordinate(x: 7, y: 0), mapper: mapper)), 0.9, accuracy: 0.00001)
        for tile in [WorldCoordinate(x: -3, y: 0), WorldCoordinate(x: 8, y: 0), WorldCoordinate(x: 0, y: -3), WorldCoordinate(x: 0, y: 8)] {
            XCTAssertNil(AudioPanning.pan(tile: tile, mapper: mapper))
        }
    }
    func testCameraPanAndZoomChangeAudioProjection() throws {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let base = try CoordinateMapper(canvasFrame: frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 40))
        let tile = WorldCoordinate(x: 2, y: 2)
        XCTAssertEqual(AudioPanning.pan(tile: tile, mapper: base), -0.5)
        let shifted = try CoordinateMapper(canvasFrame: frame, camera: CameraState(worldOrigin: WorldPoint(x: -2.5, y: 0), pointsPerTile: 40))
        XCTAssertEqual(AudioPanning.pan(tile: tile, mapper: shifted), 0)
        let zoomed = try CoordinateMapper(canvasFrame: frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 80))
        XCTAssertEqual(AudioPanning.pan(tile: tile, mapper: zoomed), 0)
    }
    @MainActor
    func testActualOfflineStereoChannelsAndFiniteClamp() throws {
        func energy(pan: Float) throws -> (Double, Double) {
            let engine = try AudioEngine(offline: true)
            defer { engine.stop() }
            engine.configure(AudioSettings(volume: 1))
            engine.play(.outputActivate, pan: pan)
            let buffer = try engine.renderOffline(frames: 2048)
            XCTAssertEqual(buffer.format.channelCount, 2)
            let channels = buffer.floatChannelData!
            let count = Int(buffer.frameLength)
            func channel(_ index: Int) -> Double {
                (0..<count).reduce(0) { $0 + Double(channels[index][$1] * channels[index][$1]) }
            }
            return (channel(0), channel(1))
        }
        let left = try energy(pan: -1), right = try energy(pan: 1), center = try energy(pan: 0)
        XCTAssertGreaterThan(left.0, 0.01); XCTAssertLessThan(left.1, left.0 * 0.01)
        XCTAssertGreaterThan(right.1, 0.01); XCTAssertLessThan(right.0, right.1 * 0.01)
        XCTAssertEqual(center.0, center.1, accuracy: 0.00001)
        let clamped = try energy(pan: 100)
        XCTAssertEqual(clamped.1, right.1, accuracy: 0.00001)
        let invalid = try energy(pan: .nan)
        XCTAssertEqual(invalid.0, invalid.1, accuracy: 0.00001)
    }
    @MainActor
    func testEditorDispatchUsesEditorCameraAndOffscreenInspectorRemovalIsSilent() throws {
        let player = RecordingSoundPlayer()
        let state = AppState(soundPlayer: player), editor = EditorSession()
        defer { state.shutdown() }
        let size = CGSize(width: 1280, height: 600)
        editor.tool = .dust
        let mapper = try XCTUnwrap(editor.mapper(size: size))
        for tile in [WorldCoordinate(x: 10, y: 9), WorldCoordinate(x: 20, y: 9)] {
            let rect = mapper.screenRect(forTile: tile)
            editor.click(at: CGPoint(x: rect.midX, y: rect.midY), size: size, appState: state)
        }
        XCTAssertEqual(player.sounds, [.placeCircuit, .placeCircuit])
        XCTAssertLessThan(player.pans[0], 0); XCTAssertGreaterThan(player.pans[1], 0)
        editor.pan(by: CGSize(width: -4000, height: 0), size: size)
        XCTAssertTrue(state.eraseCircuitComponent(at: WorldCoordinate(x: 10, y: 9), audioMapper: editor.mapper(size: size)))
        XCTAssertEqual(player.sounds.count, 2, "Offscreen inspector edits are silent")
    }
    @MainActor
    func testDesktopInputUsesLiveDesktopMapper() async throws {
        let player = RecordingSoundPlayer(), model = FinderDiagnosticsModel(provider: PanningProvider())
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: -1280, y: 100, width: 1280, height: 800), backingScale: 2)
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), finderDiagnostics: model,
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture") },
            tickScheduler: ManualCircuitTickScheduler(), soundPlayer: player, finderReferenceProviding: { screen })
        defer { app.shutdown() }
        await model.readItems(); app.toggleDesktopWorld()
        app.handleCircuitClick(DemoCircuit.button); await app.activationTask?.value
        let expected = try XCTUnwrap(AudioPanning.pan(tile: DemoCircuit.button, mapper: XCTUnwrap(app.desktopController?.scene.mapper)))
        XCTAssertEqual(player.sounds.first, .buttonPress)
        XCTAssertEqual(player.pans.first, expected)
        app.previewSound(.buttonPress, pan: 1)
        XCTAssertEqual(player.pans.last, 1)
    }
}

@MainActor
private final class PanningProvider: DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem] { [] }
}
