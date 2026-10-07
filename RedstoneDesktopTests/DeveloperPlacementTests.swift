import AppKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class PlacementItemProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] { calls += 1; return items }
}

final class DeveloperPlacementTests: XCTestCase {
    @MainActor
    private func state(provider: PlacementItemProvider, opener: FixtureItemOpener) -> AppState {
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 1280, height: 640), backingScale: 1)
        return AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture Finder desktop") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener,
            finderReferenceProviding: { screen })
    }

    @MainActor
    func testRejectedPlacementsPreserveWorldAndDoNotQueryFinderOrOpenFiles() {
        let provider = PlacementItemProvider(), opener = FixtureItemOpener()
        let state = state(provider: provider, opener: opener)
        let before = state.desktopWorld
        let cases: [(WorldCoordinate, PlacementFailureReason)] = [
            (WorldCoordinate(x: 14, y: 3), .liquid),
            (WorldCoordinate(x: 15, y: 3), .liquid),
            (WorldCoordinate(x: 10, y: 5), .blockedByDecoration(.tree)),
            (WorldCoordinate(x: 14, y: 5), .noSolidSurface),
            (DemoCircuit.button, .circuitOccupied)]
        for (coordinate, reason) in cases {
            let component = CircuitComponent(kind: .dust)
            XCTAssertEqual(state.developerPlacementPreview(component, at: coordinate), .rejected(reason))
            XCTAssertEqual(state.placeDeveloperComponent(component, at: coordinate), .rejected(reason))
            XCTAssertEqual(state.desktopWorld, before)
            XCTAssertEqual(state.developerPlacementStatus, reason.message)
        }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testValidPlacementAndDuplicateRejectionResetOnlyTestPatch() {
        let provider = PlacementItemProvider(), opener = FixtureItemOpener()
        let state = state(provider: provider, opener: opener)
        let before = state.desktopWorld
        let coordinate = WorldCoordinate(x: 10, y: 3)
        let repeater = CircuitComponent(kind: .repeater, direction: .south, repeaterDelay: .three)
        XCTAssertEqual(state.developerPlacementPreview(repeater, at: coordinate), .allowed)
        XCTAssertEqual(state.placeDeveloperComponent(repeater, at: coordinate), .allowed)
        XCTAssertEqual(state.desktopWorld.circuit.components[coordinate], repeater)
        XCTAssertEqual(state.simulator.world, state.desktopWorld.circuit)
        let placed = state.desktopWorld
        XCTAssertEqual(state.placeDeveloperComponent(CircuitComponent(kind: .dust), at: coordinate), .rejected(.circuitOccupied))
        XCTAssertEqual(state.desktopWorld, placed)
        state.resetDeveloperPlacements()
        XCTAssertEqual(state.desktopWorld, before)
        XCTAssertEqual(state.simulator.world, before.circuit)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
    }

    @MainActor
    func testPlacementAndResetAreLockedWhileDesktopWorldIsEnabled() async {
        let provider = PlacementItemProvider(), opener = FixtureItemOpener()
        let state = state(provider: provider, opener: opener)
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.lever)
        await state.activationTask?.value
        state.advanceCircuitTick()
        await state.activationTask?.value
        let world = state.desktopWorld, simulator = state.simulator
        let coordinate = WorldCoordinate(x: 10, y: 3)
        XCTAssertEqual(state.placeDeveloperComponent(CircuitComponent(kind: .dust), at: coordinate), .rejected(.reserved))
        state.resetDeveloperPlacements()
        XCTAssertEqual(state.desktopWorld, world)
        XCTAssertEqual(state.simulator, simulator, "Rejected edits must not interrupt a held circuit")
        XCTAssertTrue(state.developerPlacementStatus.contains("Disable"))
    }

    @MainActor
    func testPlacedCircuitSimulatesAndUsesExistingFreshOccupantActionPath() async {
        let provider = PlacementItemProvider(), opener = FixtureItemOpener()
        let state = state(provider: provider, opener: opener)
        defer { state.shutdown() }
        let lever = WorldCoordinate(x: 10, y: 3), dust = WorldCoordinate(x: 11, y: 3), output = WorldCoordinate(x: 12, y: 3)
        for (coordinate, kind) in [(lever, CircuitComponentKind.lever), (dust, .dust), (output, .output)] {
            XCTAssertEqual(state.placeDeveloperComponent(CircuitComponent(kind: kind), at: coordinate), .allowed)
        }
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        state.handleCircuitClick(lever)
        await state.activationTask?.value
        // Replace occupancy after the input read, before the rising output action.
        let occupant = DesktopItem(id: "fresh", url: URL(fileURLWithPath: "/tmp/placement-fresh"), displayName: "Fresh",
            position: CGPoint(x: 800, y: 416), estimatedIconSize: nil, kind: .folder)
        provider.items = [occupant]
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(state.simulator.power(at: output), .full)
        XCTAssertEqual(opener.urls, [occupant.url])
        for _ in 0..<20 { state.advanceCircuitTick() }
        XCTAssertEqual(opener.urls.count, 1)
        state.shutdown()
        state.toggleDesktopWorld()
        XCTAssertEqual(state.desktopWorld.circuit.components[lever]?.kind, .lever, "Placements survive enable/disable within this session")
        XCTAssertTrue(state.simulator.poweredTiles.isEmpty)
    }

    @MainActor
    func testDeveloperFormCanBeHostedWithoutDesktopOrFinderAccess() {
        let provider = PlacementItemProvider(), opener = FixtureItemOpener()
        let state = state(provider: provider, opener: opener)
        let view = NSHostingView(rootView: DeveloperPlacementView(appState: state))
        XCTAssertGreaterThanOrEqual(view.fittingSize.width, 520)
        XCTAssertGreaterThanOrEqual(view.fittingSize.height, 560)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertFalse(state.isDesktopWorldEnabled)
    }
}
