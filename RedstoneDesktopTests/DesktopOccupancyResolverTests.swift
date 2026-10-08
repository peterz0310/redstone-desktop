import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class OccupancyFixtureProvider: DesktopItemProviding {
    var items: [DesktopItem] = []
    var fails = false
    var onRead: (() -> Void)?
    func currentDesktopItems() async throws -> [DesktopItem] {
        onRead?()
        if fails { throw FinderReadError.permissionDenied }
        return items
    }
}

final class DesktopOccupancyResolverTests: XCTestCase {
    private let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 2)
    private let tile = WorldCoordinate(x: 1, y: 1)
    private func item(_ id: String, x: Double = 100, y: Double = 380) -> DesktopItem {
        DesktopItem(id: id, url: URL(fileURLWithPath: "/tmp/\(id)"), displayName: "Same name", position: CGPoint(x: x, y: y), estimatedIconSize: nil, kind: .file)
    }
    private func mapper(origin: WorldPoint = WorldPoint(x: 0, y: 0)) throws -> CoordinateMapper {
        try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: origin, pointsPerTile: 64))
    }
    private func resolve(_ items: [DesktopItem]) throws -> DesktopOccupancySnapshot {
        DesktopOccupancyResolver().resolve(items: items, mapper: try mapper(), finderReference: screen, activeScreen: screen)
    }

    func testEmptyAndUnavailableAreDistinct() throws {
        XCTAssertEqual(try resolve([]).state(at: tile), .empty)
        XCTAssertEqual(DesktopOccupancySnapshot.unavailable("Denied").state(at: tile), .unavailable("Denied"))
    }

    func testCenterCrossingExactBoundaryMovesOccupancy() throws {
        let before = item("moving", x: 63.999)
        let after = item("moving", x: 64)
        let oldTile = WorldCoordinate(x: 0, y: 1)
        XCTAssertEqual(try resolve([before]).state(at: oldTile), .occupied(before))
        XCTAssertEqual(try resolve([before]).state(at: tile), .empty)
        XCTAssertEqual(try resolve([after]).state(at: oldTile), .empty)
        XCTAssertEqual(try resolve([after]).state(at: tile), .occupied(after))
        let below = item("vertical", y: 416.001)
        let above = item("vertical", y: 416)
        XCTAssertEqual(try resolve([below]).state(at: WorldCoordinate(x: 1, y: 0)), .occupied(below))
        XCTAssertEqual(try resolve([above]).state(at: tile), .occupied(above))
    }

    func testAmbiguityPreservesEveryItemAndIsOrderIndependent() throws {
        let a = item("a"), b = item("b")
        let snapshot = try resolve([b, a])
        XCTAssertEqual(snapshot.state(at: tile), .ambiguous([a, b]))
        XCTAssertEqual(snapshot, try resolve([a, b]))
        XCTAssertEqual(snapshot.ambiguousTiles.map(\.items), [[a, b]])
        XCTAssertEqual(try resolve([b]).state(at: tile), .occupied(b))
        XCTAssertEqual(try resolve([]).state(at: tile), .empty)
    }

    func testActiveDisplayUsesHalfOpenCenterBounds() throws {
        let inside = item("inside", x: 0, y: 480)
        XCTAssertEqual(try resolve([inside]).state(at: WorldCoordinate(x: 0, y: 0)), .occupied(inside))
        XCTAssertEqual(try resolve([item("right", x: 640), item("top", y: 0), item("left", x: -1)]), .available([:]))
    }

    func testNegativeOriginsAndScaleDoNotChangeCenterRule() throws {
        let negative = ScreenDescriptor(id: "left", frame: CGRect(x: -640, y: -100, width: 640, height: 480), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: negative.frame, camera: CameraState(worldOrigin: WorldPoint(x: -2, y: -2), pointsPerTile: 64))
        let fixture = item("negative")
        let resolver = DesktopOccupancyResolver()
        let snapshot = resolver.resolve(items: [fixture], mapper: mapper, finderReference: negative, activeScreen: negative)
        XCTAssertEqual(snapshot.state(at: WorldCoordinate(x: -1, y: -1)), .occupied(fixture))
        let scaleOne = ScreenDescriptor(id: "left", frame: negative.frame, backingScale: 1)
        XCTAssertEqual(snapshot, resolver.resolve(items: [fixture], mapper: mapper, finderReference: scaleOne, activeScreen: scaleOne))
    }

    func testUnrepresentableTileFailsClosed() throws {
        let snapshot = DesktopOccupancyResolver().resolve(items: [item("overflow")], mapper: try mapper(origin: WorldPoint(x: Double(Int.max), y: 0)), finderReference: screen, activeScreen: screen)
        guard case .unavailable = snapshot else { return XCTFail("Invalid geometry must be unavailable") }
    }

    @MainActor
    private func assertColor(_ actual: NSColor, matches expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let a = actual.usingColorSpace(.sRGB), let b = expected.usingColorSpace(.sRGB) else {
            return XCTFail("Could not resolve colors", file: file, line: line)
        }
        XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(a.greenComponent, b.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.001, file: file, line: line)
    }

    @MainActor
    func testRendererReplacesOccupancyAndClearsUnavailable() throws {
        let mapper = try mapper()
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let layer = try XCTUnwrap(scene.childNode(withName: "desktop-occupancy"))
        scene.updateOccupancy(try resolve([item("a")]))
        XCTAssertTrue(layer.children.isEmpty, "Finder occupancy no longer adds desktop tile boxes")
        scene.updateOccupancy(try resolve([item("a"), item("b")]))
        XCTAssertTrue(layer.children.isEmpty)
        scene.size = CGSize(width: 600, height: 400)
        XCTAssertTrue(layer.children.isEmpty)
        scene.updateOccupancy(.unavailable("Denied"))
        XCTAssertTrue(layer.children.isEmpty)
    }

    @MainActor
    func testAppUpdatesAvailabilityMovementAndFailure() async throws {
        let provider = OccupancyFixtureProvider()
        let model = FinderDiagnosticsModel(provider: provider)
        let state = AppState(screenProviding: { self.screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), finderDiagnostics: model, finderReferenceProviding: { self.screen })
        defer { state.shutdown() }
        state.toggleDesktopWorld()
        guard case .unavailable = state.desktopOccupancy else { return XCTFail("Unread Finder must be unavailable") }
        await model.readItems() // empty first read must change availability without item publication
        XCTAssertEqual(state.desktopOccupancy, .available([:]))
        provider.items = [item("a")]
        await model.readItems()
        XCTAssertEqual(state.desktopOccupancy.state(at: tile), .occupied(item("a")))
        provider.items = [item("a", x: 200)]
        await model.readItems()
        XCTAssertEqual(state.desktopOccupancy.state(at: tile), .empty)
        XCTAssertEqual(state.desktopOccupancy.state(at: WorldCoordinate(x: 3, y: 1)), .occupied(item("a", x: 200)))
        provider.fails = true
        await model.readItems()
        guard case .unavailable = state.desktopOccupancy else { return XCTFail("Failed Finder read must be unavailable") }
        provider.fails = false
        provider.onRead = {
            guard case .unavailable = state.desktopOccupancy else {
                return XCTFail("Retry must remain unavailable until it succeeds")
            }
        }
        await model.readItems()
        XCTAssertEqual(state.desktopOccupancy.state(at: WorldCoordinate(x: 3, y: 1)), .occupied(item("a", x: 200)))
        state.shutdown()
        guard case .unavailable = state.desktopOccupancy else { return XCTFail("Disabled desktop must be unavailable") }
    }
}
