import AppKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class ScaleProvider: DesktopItemProviding {
    var size: Double = 64
    var items: [DesktopItem] = []
    var fails = false
    var reportsSize = true
    var hold = false
    var gate: CheckedContinuation<Void, Never>?
    func currentDesktopItems() async throws -> [DesktopItem] { items }
    func currentDesktopSnapshot() async throws -> FinderDesktopSnapshot {
        if hold { await withCheckedContinuation { gate = $0 } }
        if fails { throw FinderReadError.scriptFailure(code: -1712, message: "Fixture timeout") }
        return FinderDesktopSnapshot(items: items, viewSettings: reportsSize ? FinderViewSettings(iconSize: size) : nil)
    }
}

final class FinderScaleTests: XCTestCase {
    let frame = CGRect(x: -1000, y: 200, width: 1280, height: 800)
    let saved = CameraState(worldOrigin: WorldPoint(x: -10, y: 20), pointsPerTile: 64)

    func testIndependentNeverNeedsMetadataOrChangesCamera() {
        XCTAssertEqual(FinderScale().camera(saved: saved, current: nil, frame: .zero), saved)
    }
    func testRatioPreservesCenterOnNegativeOriginDisplay() throws {
        let camera = try XCTUnwrap(FinderScale(enabled: true, baselineIconSize: 64).camera(
            saved: saved, current: FinderViewSettings(iconSize: 96), frame: frame))
        XCTAssertEqual(camera.pointsPerTile, 96)
        let before = try CoordinateMapper(canvasFrame: frame, camera: saved)
        let after = try CoordinateMapper(canvasFrame: frame, camera: camera)
        XCTAssertEqual(before.worldPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY)),
                       after.worldPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY)))
    }
    func testBoundsAndRepeatedRatiosNeverAccumulateDrift() throws {
        let mode = FinderScale(enabled: true, baselineIconSize: 64)
        XCTAssertEqual(mode.camera(saved: saved, current: FinderViewSettings(iconSize: 4096), frame: frame)?.pointsPerTile, 128)
        XCTAssertEqual(mode.camera(saved: saved, current: FinderViewSettings(iconSize: 1), frame: frame)?.pointsPerTile, 16)
        XCTAssertEqual(mode.camera(saved: saved, current: FinderViewSettings(iconSize: 64), frame: frame), saved)
        XCTAssertNil(mode.camera(saved: saved, current: nil, frame: frame))
        XCTAssertNil(mode.camera(saved: saved, current: FinderViewSettings(iconSize: 64), frame: .zero))
        XCTAssertNil(FinderScale(enabled: true, baselineIconSize: 0).camera(saved: saved, current: FinderViewSettings(iconSize: 64), frame: frame))
    }
    @MainActor
    func testDefaultAndMissingSettingsDoNotOptIn() {
        let app = AppState()
        defer { app.shutdown() }
        app.setFinderScaleEnabled(true)
        XCTAssertFalse(app.finderScale.enabled)
        XCTAssertTrue(app.finderScaleStatus.contains("Read Finder"))
    }
    @MainActor
    func testLiveRefreshRebuildsMappingWithoutChangingWorldOrReplayingPower() async throws {
        let provider = ScaleProvider()
        provider.items = [DesktopItem(id: "test", url: URL(fileURLWithPath: "/tmp/scale"), displayName: "Test",
            position: CGPoint(x: 900, y: 300), estimatedIconSize: nil, kind: .folder)]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .milliseconds(1))
        let screen = ScreenDescriptor(id: "test", frame: frame, backingScale: 2)
        let ticks = ManualCircuitTickScheduler(), opener = FixtureItemOpener()
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: model, tickScheduler: ticks, itemOpener: opener,
            displayNotificationCenter: NotificationCenter(), finderReferenceProviding: { screen })
        defer { app.shutdown() }
        await model.readItems(); app.toggleDesktopWorld()
        let library = app.library, original = app.desktopCamera
        app.setFinderScaleEnabled(true)
        let oldController = app.desktopController
        let oldTile = app.finderMappings.first?.tile
        provider.size = 128
        await model.readItems()
        XCTAssertEqual(app.desktopCamera.pointsPerTile, 128)
        XCTAssertFalse(app.desktopController === oldController)
        XCTAssertNotEqual(app.finderMappings.first?.tile, oldTile)
        XCTAssertEqual(app.library, library)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(app.simulator.poweredTiles.isEmpty)
        let synchronizedController = app.desktopController
        XCTAssertTrue(app.activateSelectedArea())
        XCTAssertTrue(app.desktopController === synchronizedController, "Reactivating the same saved camera never restarts a synchronized runtime")
        app.setFinderScaleEnabled(false)
        XCTAssertEqual(app.desktopCamera, original)
        XCTAssertEqual(app.library, library)
        provider.size = 32; await model.readItems()
        XCTAssertEqual(app.desktopCamera, original)
    }
    @MainActor
    func testConnectedFinderWithUnavailableSizeHasSpecificFeedback() async {
        let provider = ScaleProvider(); provider.reportsSize = false
        let model = FinderDiagnosticsModel(provider: provider)
        let state = AppState(finderDiagnostics: model)
        defer { state.shutdown() }
        await model.readItems()
        XCTAssertTrue(model.hasRead)
        state.setFinderScaleEnabled(true)
        XCTAssertFalse(state.finderScale.enabled)
        XCTAssertTrue(state.finderScaleStatus.contains("items are connected"))
        XCTAssertTrue(state.finderScaleStatus.contains("icon size is unavailable"))
    }
    @MainActor
    func testOrdinaryBackgroundPollDoesNotBlockEnablingFromStableCachedMetadata() async {
        let provider = ScaleProvider()
        let model = FinderDiagnosticsModel(provider: provider)
        let state = AppState(finderDiagnostics: model)
        defer { state.shutdown() }
        await model.readItems()
        provider.hold = true
        let poll = Task { await model.readItems() }
        while provider.gate == nil { await Task.yield() }
        XCTAssertTrue(model.isReading)
        state.setFinderScaleEnabled(true)
        XCTAssertTrue(state.finderScale.enabled)
        XCTAssertEqual(state.finderScale.baselineIconSize, 64)
        provider.gate?.resume()
        await poll.value
    }
    @MainActor
    func testFailedRefreshCannotOptInUsingOldMetadata() async {
        let provider = ScaleProvider()
        let failingModel = FinderDiagnosticsModel(provider: provider)
        let app = AppState(finderDiagnostics: failingModel)
        defer { app.shutdown() }
        await failingModel.readItems()
        provider.fails = true
        await failingModel.readItems()
        app.setFinderScaleEnabled(true)
        XCTAssertFalse(app.finderScale.enabled)
        XCTAssertEqual(failingModel.viewSettings?.iconSize, 64, "Failure deliberately retains last known metadata")
    }
    @MainActor
    func testPreferencesAreIsolatedAndRestoreModeWithoutReadingFinder() async throws {
        let suite = "RedstoneDesktopTests.scale.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = ScaleProvider(), model = FinderDiagnosticsModel(provider: ScaleProvider())
        let app = AppState(finderDiagnostics: model, preferences: defaults)
        await model.readItems(); app.setFinderScaleEnabled(true)
        let restored = AppState(finderDiagnostics: FinderDiagnosticsModel(provider: provider), preferences: defaults)
        defer { app.shutdown(); restored.shutdown() }
        XCTAssertTrue(restored.finderScale.enabled)
        XCTAssertEqual(restored.finderScale.baselineIconSize, 64)
        XCTAssertFalse(restored.finderDiagnostics.hasRead)
        XCTAssertFalse(restored.isDesktopWorldEnabled)
        XCTAssertEqual(restored.desktopCamera.pointsPerTile, 64)
    }
}
