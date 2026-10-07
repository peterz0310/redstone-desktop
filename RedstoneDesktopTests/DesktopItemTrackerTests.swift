import AppKit
import Combine
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class TrackerFixtureProvider: DesktopItemProviding {
    var operation: @MainActor () async throws -> [DesktopItem] = { [] }
    private(set) var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        return try await operation()
    }
}

final class DesktopItemTrackerTests: XCTestCase {
    @MainActor
    func testProvisionalFinderConversionAndMarkersUseLogicalPoints() throws {
        let screen = ScreenDescriptor(id: "negative", frame: CGRect(x: -1280, y: -200, width: 1280, height: 800), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: camera)
        let item = item(id: "file", x: 100, y: 200)
        let mapping = mapper.provisionalFinderMapping(for: item, referenceScreen: screen)
        XCTAssertEqual(mapping.provisionalCenter, CGPoint(x: -1180, y: 400))
        XCTAssertEqual(mapping.tile, WorldCoordinate(x: 1, y: 9))
        let nonRetina = ScreenDescriptor(id: "negative", frame: screen.frame, backingScale: 1)
        XCTAssertEqual(mapping, mapper.provisionalFinderMapping(for: item, referenceScreen: nonRetina))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        scene.updateFinderMarkers([mapping])
        let markers = try XCTUnwrap(scene.childNode(withName: "finder-markers"))
        XCTAssertEqual(markers.children.count, 1)
        XCTAssertEqual(markers.children[0].position, CGPoint(x: 100, y: 600))
        scene.updateFinderMarkers([mapping])
        XCTAssertEqual(markers.children.count, 1)
        scene.size = CGSize(width: 800, height: 600)
        XCTAssertEqual(markers.children.count, 1)
        scene.updateFinderMarkers([])
        XCTAssertTrue(markers.children.isEmpty)
    }

    @MainActor
    func testFinderReferenceIsIndependentOfRendererCanvas() throws {
        let primary = ScreenDescriptor(id: "primary", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), backingScale: 2)
        let canvas = CGRect(x: -1280, y: -200, width: 1280, height: 800)
        let mapper = try CoordinateMapper(canvasFrame: canvas, camera: camera)
        let mapping = mapper.provisionalFinderMapping(for: item(id: "file", x: 120, y: 80), referenceScreen: primary)
        XCTAssertEqual(mapping.provisionalCenter, CGPoint(x: 120, y: 1000))
        let scene = DesktopScene(screen: ScreenDescriptor(id: "active", frame: canvas, backingScale: 1), mapper: mapper)
        scene.updateFinderMarkers([mapping])
        XCTAssertTrue(try XCTUnwrap(scene.childNode(withName: "finder-markers")).children.isEmpty)
    }

    @MainActor
    func testIdenticalPollsDoNotPublishButMovementRenameAddAndRemoveDo() async {
        let provider = TrackerFixtureProvider()
        let model = FinderDiagnosticsModel(provider: provider)
        var publications = 0
        let subscription = model.$items.sink { _ in publications += 1 }
        defer { subscription.cancel() }
        provider.operation = { [self.item(id: "one", x: 10, y: 20)] }
        await model.readItems()
        XCTAssertEqual(publications, 2) // initial snapshot plus added item
        await model.readItems()
        XCTAssertEqual(publications, 2)
        provider.operation = { [self.item(id: "one", x: 11, y: 20)] }
        await model.readItems()
        XCTAssertEqual(publications, 3)
        provider.operation = { [self.item(id: "one", x: 11, y: 20, name: "Renamed")] }
        await model.readItems()
        XCTAssertEqual(publications, 4)
        provider.operation = { [self.item(id: "one", x: 11, y: 20, name: "Renamed"), self.item(id: "two", x: 1, y: 2)] }
        await model.readItems()
        XCTAssertEqual(publications, 5)
        provider.operation = { [] }
        await model.readItems()
        XCTAssertEqual(publications, 6)
    }

    @MainActor
    func testSuspendedPollDoesNotPileUpAndStoppedResultsAreIgnored() async {
        let provider = TrackerFixtureProvider()
        let started = expectation(description: "Poll started")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let model = FinderDiagnosticsModel(provider: provider)
        let tracker = DesktopItemTracker(diagnostics: model)
        let finished = expectation(description: "Cancelled poll finished")
        var wasReading = false
        let subscription = model.$isReading.sink { reading in
            if wasReading && !reading { finished.fulfill() }
            wasReading = reading
        }
        defer { subscription.cancel() }
        defer { tracker.stop() }
        tracker.start()
        tracker.start()
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(result, .completed)
        for _ in 0..<10 { tracker.requestPoll() }
        await model.readItems()
        XCTAssertEqual(provider.calls, 1)
        tracker.stop()
        tracker.start()
        tracker.requestPoll()
        XCTAssertEqual(provider.calls, 1, "Restart must not overlap a provider that ignores cancellation")
        tracker.stop()
        continuation?.resume(returning: [item(id: "stale", x: 1, y: 2)])
        let finishResult = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(finishResult, .completed)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(tracker.isPolling)
    }

    @MainActor
    func testPollingPausesOnErrorAndRequiresExplicitRestart() async {
        let provider = TrackerFixtureProvider()
        let model = FinderDiagnosticsModel(provider: provider)
        let tracker = DesktopItemTracker(diagnostics: model)
        let paused = expectation(description: "Paused on denial")
        var wasPolling = false
        let subscription = tracker.$isPolling.sink { polling in
            if wasPolling && !polling { paused.fulfill() }
            wasPolling = polling
        }
        defer { subscription.cancel(); tracker.stop() }
        provider.operation = { throw FinderReadError.permissionDenied }
        tracker.start()
        let result = await XCTWaiter.fulfillment(of: [paused], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(model.permission, .denied)
        for _ in 0..<10 { tracker.requestPoll() }
        XCTAssertEqual(provider.calls, 1)
    }

    @MainActor
    func testAppUsesSharedSnapshotAndStopsTrackerOnDisable() async {
        let provider = TrackerFixtureProvider()
        let model = FinderDiagnosticsModel(provider: provider)
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 2)
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), finderDiagnostics: model, finderReferenceProviding: { screen })
        defer { state.shutdown() }
        provider.operation = { [self.item(id: "one", x: 100, y: 100)] }
        await model.readItems()
        state.toggleDesktopWorld()
        XCTAssertEqual(state.finderMappings.first?.provisionalCenter, CGPoint(x: 100, y: 380))
        provider.operation = { [self.item(id: "one", x: 200, y: 200)] }
        await model.readItems()
        XCTAssertEqual(state.finderMappings.first?.provisionalCenter, CGPoint(x: 200, y: 280))
        state.desktopItemTracker.start()
        state.toggleDesktopWorld()
        XCTAssertFalse(state.desktopItemTracker.isPolling)
        XCTAssertTrue(state.finderMappings.isEmpty)
    }

    private var camera: CameraState {
        CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    }

    private func item(id: String, x: Double, y: Double, name: String = "Fixture") -> DesktopItem {
        DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(name)-\(id)"), displayName: name, position: CGPoint(x: x, y: y), estimatedIconSize: nil, kind: .file)
    }
}
