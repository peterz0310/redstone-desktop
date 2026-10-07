import AppKit
import Combine
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class AutomaticFinderProvider: DesktopItemProviding {
    var calls = 0
    var fails = false
    var items: [DesktopItem] = []
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if fails { throw FinderReadError.permissionDenied }
        return items
    }
}

final class AutomaticFinderTests: XCTestCase {
    @MainActor
    private func state(_ provider: AutomaticFinderProvider, opener: FixtureItemOpener = FixtureItemOpener()) -> AppState {
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture desktop") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener,
            automaticallyRefreshFinder: true, finderReferenceProviding: { screen })
    }

    @MainActor
    func testEnableAutomaticallyReadsFinderAndDisableStopsPolling() async {
        let provider = AutomaticFinderProvider(), state = state(provider)
        defer { state.shutdown() }
        XCTAssertEqual(provider.calls, 0)
        let read = expectation(description: "Automatic initial read")
        let observer = state.finderDiagnostics.$hasRead.dropFirst().filter { $0 }.prefix(1).sink { _ in read.fulfill() }
        defer { observer.cancel() }
        state.toggleDesktopWorld()
        XCTAssertTrue(state.desktopItemTracker.isPolling)
        let result = await XCTWaiter.fulfillment(of: [read], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(state.finderDiagnostics.hasRead)
        XCTAssertEqual(provider.calls, 1)
        state.shutdown()
        XCTAssertFalse(state.desktopItemTracker.isPolling)
    }

    @MainActor
    func testCircuitOpensFreshOccupantWithoutExplicitDiagnosticRead() async {
        let provider = AutomaticFinderProvider(), opener = FixtureItemOpener()
        let url = URL(fileURLWithPath: "/tmp/automatic-finder-folder")
        provider.items = [DesktopItem(id: "target", url: url, displayName: "Target", position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .folder)]
        let state = state(provider, opener: opener)
        defer { state.shutdown() }
        let read = expectation(description: "Automatic read")
        let observer = state.finderDiagnostics.$hasRead.dropFirst().filter { $0 }.prefix(1).sink { _ in read.fulfill() }
        defer { observer.cancel() }
        state.toggleDesktopWorld()
        let result = await XCTWaiter.fulfillment(of: [read], timeout: 2)
        XCTAssertEqual(result, .completed)
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(opener.urls, [url])
        XCTAssertGreaterThanOrEqual(provider.calls, 3)
    }

    @MainActor
    func testDeniedAutomaticReadPausesAndReenableDoesNotRepeatDeniedRequest() async {
        let provider = AutomaticFinderProvider(); provider.fails = true
        let state = state(provider)
        defer { state.shutdown() }
        let denied = expectation(description: "Read denied")
        let observer = state.finderDiagnostics.$permission.filter { $0 == .denied }.prefix(1).sink { _ in denied.fulfill() }
        defer { observer.cancel() }
        state.toggleDesktopWorld()
        let result = await XCTWaiter.fulfillment(of: [denied], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(state.desktopItemTracker.isPolling)
        state.shutdown(); state.toggleDesktopWorld()
        await Task.yield()
        XCTAssertFalse(state.desktopItemTracker.isPolling)
        XCTAssertEqual(provider.calls, 1)
    }
}
