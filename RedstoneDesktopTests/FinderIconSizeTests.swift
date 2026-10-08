import AppKit
import Combine
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class IconSnapshotProvider: DesktopItemProviding {
    var responses: [FinderDesktopSnapshot] = []
    var last = FinderDesktopSnapshot(items: [])
    var failAt: Int?
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] { try await currentDesktopSnapshot().items }
    func currentDesktopSnapshot() async throws -> FinderDesktopSnapshot {
        calls += 1
        if calls == failAt { throw FinderReadError.scriptFailure(code: -1712, message: "Fixture timeout") }
        if !responses.isEmpty { last = responses.removeFirst() }
        return last
    }
}

final class FinderIconSizeTests: XCTestCase {
    private func settings(_ size: Double) -> FinderViewSettings? { FinderViewSettings(iconSize: size) }
    private func item(_ x: CGFloat = 480) -> DesktopItem {
        DesktopItem(id: "folder", url: URL(fileURLWithPath: "/tmp/icon-size-folder"), displayName: "Folder",
            position: CGPoint(x: x, y: 576), estimatedIconSize: nil, kind: .folder)
    }
    private func snapshot(_ size: Double, x: CGFloat = 480, stable: Bool = true) -> FinderDesktopSnapshot {
        FinderDesktopSnapshot(items: [item(x)], viewSettings: settings(size), layoutIsStable: stable)
    }
    @MainActor
    private func list(_ values: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let result = NSAppleEventDescriptor.list()
        for (i, value) in values.enumerated() { result.insert(value, at: i + 1) }
        return result
    }

    func testRawSettingValidationDoesNotBecomeWorldScale() {
        XCTAssertEqual(settings(64)?.iconSize, 64)
        for invalid in [0, -1, 48.5, .infinity, .nan, 100000] { XCTAssertNil(settings(invalid)) }
    }

    @MainActor
    func testNativeSnapshotScriptCompilesWithoutQueryingFinder() throws {
        // Compile the public dictionary terms; do not execute or request Automation in tests.
        let script = try XCTUnwrap(NSAppleScript(source: FinderScriptRunner.desktopSnapshotQuery))
        var error: NSDictionary?
        XCTAssertTrue(script.compileAndReturnError(&error), "\(String(describing: error))")
        XCTAssertNil(error)
        let fixture = try FinderScriptRunner.execute(source: "return {64, 64, {}}")
        XCTAssertEqual(try FinderDesktopItemProvider.parseSnapshot(fixture).viewSettings, settings(64))
    }

    @MainActor
    func testSnapshotParserPreservesCentersAndDetectsChangingSize() throws {
        let rows = list([list([.init(string: "Folder"), .init(string: "/tmp/icon-size-folder"), .init(int32: 480), .init(int32: 576)])])
        let stable = try FinderDesktopItemProvider.parseSnapshot(list([.init(int32: 64), .init(int32: 64), rows]))
        XCTAssertEqual(stable.viewSettings, settings(64))
        XCTAssertTrue(stable.layoutIsStable)
        XCTAssertEqual(stable.items.first?.position, CGPoint(x: 480, y: 576))
        XCTAssertNil(stable.items.first?.estimatedIconSize, "Raw size never biases center mapping")
        let changing = try FinderDesktopItemProvider.parseSnapshot(list([.init(int32: 64), .init(int32: 128), rows]))
        XCTAssertFalse(changing.layoutIsStable)
        XCTAssertEqual(changing.viewSettings, settings(128))
        XCTAssertThrowsError(try FinderDesktopItemProvider.parseSnapshot(list([])))
    }

    @MainActor
    func testUnavailableOptionalSettingsRetainEmptyOrPopulatedItemReads() throws {
        for value in [NSAppleEventDescriptor.null(), .init(string: "unknown"), .init(double: .infinity), .init(int32: -1)] {
            let result = try FinderDesktopItemProvider.parseSnapshot(list([value, value, list([])]))
            XCTAssertTrue(result.items.isEmpty)
            XCTAssertNil(result.viewSettings)
            XCTAssertTrue(result.layoutIsStable)
        }
        XCTAssertThrowsError(try FinderDesktopItemProvider.parseSnapshot(list([.null(), .null(), .init(string: "bad rows")])))
    }

    @MainActor
    func testChangedSizeWaitsThenPublishesFreshPositionsAndSessionBaseline() async {
        let provider = IconSnapshotProvider()
        provider.responses = [snapshot(64), snapshot(128, x: 600), snapshot(128, x: 960)]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .milliseconds(1))
        XCTAssertEqual(provider.calls, 0)
        await model.readItems()
        let generation = model.layoutGeneration
        XCTAssertEqual(model.baselineViewSettings, settings(64))
        var sawSettling = false, published: [CGFloat] = []
        let state = model.$isLayoutSettling.sink { sawSettling = sawSettling || $0 }
        let items = model.$items.sink { published += $0.map(\.position.x) }
        defer { state.cancel(); items.cancel() }
        let success = await model.readItems()
        XCTAssertTrue(success)
        XCTAssertTrue(sawSettling)
        XCTAssertFalse(model.isLayoutSettling)
        XCTAssertNotEqual(model.layoutGeneration, generation)
        XCTAssertEqual(model.viewSettings, settings(128))
        XCTAssertEqual(model.baselineViewSettings, settings(64))
        XCTAssertEqual(model.items.first?.position.x, 960)
        XCTAssertFalse(published.contains(600), "Do not publish the intermediate layout")
        XCTAssertEqual(provider.calls, 3)
    }

    @MainActor
    func testSizeChangesDuringFirstReadAndContinuousChangesWaitUntilStable() async {
        let provider = IconSnapshotProvider()
        provider.responses = [snapshot(80, x: 500, stable: false), snapshot(96, x: 600), snapshot(128, x: 700), snapshot(128, x: 800)]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .milliseconds(1))
        await model.readItems()
        XCTAssertEqual(provider.calls, 4)
        XCTAssertEqual(model.items.first?.position.x, 800)
        XCTAssertEqual(model.baselineViewSettings, settings(128))
        XCTAssertFalse(model.isReading)
    }

    @MainActor
    func testIdenticalSettingsDoNotWaitOrChangeLayoutIdentityButMovementStillPublishes() async {
        let provider = IconSnapshotProvider()
        provider.responses = [snapshot(64), snapshot(64, x: 960)]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .seconds(60))
        await model.readItems()
        let generation = model.layoutGeneration
        await model.readItems()
        XCTAssertEqual(provider.calls, 2)
        XCTAssertEqual(model.layoutGeneration, generation)
        XCTAssertEqual(model.items.first?.position.x, 960)
    }

    @MainActor
    func testProvidersWithoutSettingsKeepTrackingWithoutDelayOrBaseline() async {
        let provider = IconSnapshotProvider()
        provider.responses = [FinderDesktopSnapshot(items: [item()]), FinderDesktopSnapshot(items: [item(960)])]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .seconds(60))
        await model.readItems(); await model.readItems()
        XCTAssertTrue(model.hasRead)
        XCTAssertEqual(provider.calls, 2)
        XCTAssertNil(model.baselineViewSettings)
        XCTAssertNil(model.viewSettings)
        XCTAssertEqual(model.items.first?.position.x, 960)
    }

    @MainActor
    func testFailureDuringSettleClearsPositionsAndRecoveryPreservesBaseline() async {
        let provider = IconSnapshotProvider()
        provider.responses = [snapshot(64), snapshot(128), snapshot(128)]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .milliseconds(1))
        await model.readItems()
        provider.failAt = 3
        let success = await model.readItems()
        XCTAssertFalse(success)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.hasRead)
        XCTAssertFalse(model.isReading)
        XCTAssertFalse(model.isLayoutSettling)
        XCTAssertNotNil(model.error)
        provider.failAt = nil
        await model.readItems()
        XCTAssertEqual(model.viewSettings, settings(128))
        XCTAssertEqual(model.baselineViewSettings, settings(64))
        XCTAssertNil(model.error)
    }

    @MainActor
    func testCancelOrDisplayInvalidationDuringSettleCannotPublishIntermediateSnapshot() async {
        for invalidate in [false, true] {
            let provider = IconSnapshotProvider()
            provider.responses = [snapshot(64), snapshot(128)]
            let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .milliseconds(20))
            await model.readItems()
            let waiting = expectation(description: "Layout waiting")
            let observer = model.$isLayoutSettling.filter { $0 }.prefix(1).sink { _ in waiting.fulfill() }
            let task = Task { await model.readItems() }
            let result = await XCTWaiter.fulfillment(of: [waiting], timeout: 2)
            XCTAssertEqual(result, .completed)
            if invalidate { model.invalidateDisplayPositions() } else { task.cancel() }
            let success = await task.value
            observer.cancel()
            XCTAssertFalse(success)
            XCTAssertTrue(model.items.isEmpty)
            XCTAssertFalse(model.hasRead)
            XCTAssertFalse(model.isReading)
            XCTAssertEqual(provider.calls, 2)
        }
    }

    @MainActor
    func testInputReadDetectingResizeCannotPressCircuitAndFreshRetryWorks() async {
        let provider = IconSnapshotProvider()
        provider.responses = [snapshot(64)]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .milliseconds(1))
        let app = state(model)
        defer { app.shutdown() }
        await model.readItems(); app.toggleDesktopWorld()
        let camera = app.desktopCamera, library = app.library
        provider.responses = [snapshot(128), snapshot(128)]
        app.handleCircuitClick(DemoCircuit.button)
        await app.activationTask?.value
        app.advanceCircuitTick()
        XCTAssertTrue(app.simulator.poweredTiles.isEmpty)
        XCTAssertTrue(app.lastActionResult.contains("old activations"))
        XCTAssertEqual(app.desktopCamera, camera)
        XCTAssertEqual(app.library, library)
        app.handleCircuitClick(DemoCircuit.button)
        await app.activationTask?.value
        app.advanceCircuitTick()
        await app.activationTask?.value
        XCTAssertGreaterThan(app.simulator.power(at: DemoCircuit.output), .off)
    }

    @MainActor
    func testOutputReadDetectingResizeSkipsOldActivationAndFuturePulseOpensFreshOccupant() async {
        let provider = IconSnapshotProvider(), opener = FixtureItemOpener()
        provider.responses = [snapshot(64)]
        let model = FinderDiagnosticsModel(provider: provider, layoutSettleDelay: .milliseconds(1))
        let app = state(model, opener: opener)
        defer { app.shutdown() }
        await model.readItems(); app.toggleDesktopWorld()
        app.handleCircuitClick(DemoCircuit.button); await app.activationTask?.value
        provider.responses = [snapshot(128, x: 800), snapshot(128)]
        app.advanceCircuitTick(); await app.activationTask?.value
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertEqual(app.desktopOccupancy.state(at: DemoCircuit.output), .occupied(item()))
        for _ in 0..<21 { app.advanceCircuitTick() }
        XCTAssertTrue(opener.urls.isEmpty, "Settling never replays a held output")
        app.handleCircuitClick(DemoCircuit.button); await app.activationTask?.value
        app.advanceCircuitTick(); await app.activationTask?.value
        XCTAssertEqual(opener.urls, [item().url])
    }

    @MainActor
    private func state(_ model: FinderDiagnosticsModel, opener: FixtureItemOpener = FixtureItemOpener()) -> AppState {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 2)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: model, desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture desktop") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, displayNotificationCenter: NotificationCenter(), finderReferenceProviding: { screen })
    }
}
