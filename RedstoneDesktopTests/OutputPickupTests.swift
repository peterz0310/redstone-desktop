import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class OutputPickupTests: XCTestCase {
    private let origin = WorldCoordinate(x: 0, y: 0)
    private func chain(_ direction: Direction, _ delay: RepeaterDelay) -> (CircuitWorld, [WorldCoordinate]) {
        var tiles = [origin]
        for _ in 0..<4 { tiles.append(direction.neighbor(of: tiles.last!)!) }
        return (CircuitWorld(components: [tiles[0]: CircuitComponent(kind: .lever), tiles[1]: CircuitComponent(kind: .dust),
            tiles[2]: CircuitComponent(kind: .output), tiles[3]: CircuitComponent(kind: .repeater, direction: direction, repeaterDelay: delay),
            tiles[4]: CircuitComponent(kind: .output)]), tiles)
    }

    func testEveryOrientationAndDelayRestoresSignalAndDelaysBothEdges() {
        for direction in Direction.allCases {
            for delay in RepeaterDelay.allCases {
                let (world, tiles) = chain(direction, delay)
                var sim = CircuitSimulator(world: world)
                sim.toggleLever(at: tiles[0])
                XCTAssertEqual(sim.advanceTick(), [.outputActivated(tiles[2])])
                for _ in 1..<delay.simulationTicks { XCTAssertTrue(sim.advanceTick().isEmpty); XCTAssertEqual(sim.power(at: tiles[4]), .off) }
                XCTAssertEqual(sim.advanceTick(), [.outputActivated(tiles[4])])
                XCTAssertEqual(sim.power(at: tiles[3]), .full)
                for _ in 0..<20 { XCTAssertTrue(sim.advanceTick().isEmpty) }
                sim.toggleLever(at: tiles[0])
                sim.advanceTick()
                XCTAssertEqual(sim.power(at: tiles[2]), .off)
                for _ in 1..<delay.simulationTicks { sim.advanceTick(); XCTAssertEqual(sim.power(at: tiles[4]), .full) }
                sim.advanceTick()
                XCTAssertTrue(sim.power.isEmpty)
            }
        }
    }

    func testWeakestPositiveDustSignalIsRestoredAndActionModeIsIrrelevant() {
        for mode in OutputActionMode.allCases {
            var components = [origin: CircuitComponent(kind: .lever)]
            for x in 1...15 { components[WorldCoordinate(x: x, y: 0)] = CircuitComponent(kind: .dust) }
            let a = WorldCoordinate(x: 16, y: 0), repeater = WorldCoordinate(x: 17, y: 0), b = WorldCoordinate(x: 18, y: 0)
            components[a] = CircuitComponent(kind: .output, outputAction: mode)
            components[repeater] = CircuitComponent(kind: .repeater, direction: .east)
            components[b] = CircuitComponent(kind: .output, outputAction: mode)
            var sim = CircuitSimulator(world: CircuitWorld(components: components))
            sim.toggleLever(at: origin)
            XCTAssertEqual(sim.advanceTick(), [.outputActivated(a)])
            XCTAssertEqual(sim.power(at: a), PowerLevel(1))
            sim.advanceTick()
            XCTAssertEqual(sim.advanceTick(), [.outputActivated(b)])
            XCTAssertEqual(sim.power(at: repeater), .full)
            XCTAssertEqual(sim.power(at: b), .full)
        }
    }

    func testOutputInputTableMergesSupportedStrongAndWeakSources() {
        let source = WorldCoordinate(x: -1, y: 0)
        for kind in [CircuitComponentKind.button, .lever, .dust, .repeater, .torch] {
            var components = [origin: CircuitComponent(kind: .output), source: CircuitComponent(kind: kind, direction: .east)]
            let rear = WorldCoordinate(x: -2, y: 0)
            if [.dust, .repeater].contains(kind) { components[rear] = CircuitComponent(kind: .lever) }
            var sim = CircuitSimulator(world: CircuitWorld(components: components))
            if kind == .button { sim.pressButton(at: source) }
            if kind == .lever { sim.toggleLever(at: source) }
            if [.dust, .repeater].contains(kind) { sim.toggleLever(at: rear) }
            for _ in 0..<3 { sim.advanceTick() }
            XCTAssertEqual(sim.power(at: origin), .full, "Valid input from \(kind)")
        }
    }

    func testReversedAndSidewaysRepeatersCannotPickUpAndOutputNeverBroadcasts() {
        let a = WorldCoordinate(x: 1, y: 0), rearTorch = WorldCoordinate(x: 2, y: 0)
        for direction in [Direction.west, .north, .south] {
            var sim = CircuitSimulator(world: CircuitWorld(components: [origin: CircuitComponent(kind: .lever), a: CircuitComponent(kind: .output),
                rearTorch: CircuitComponent(kind: .repeater, direction: direction), WorldCoordinate(x: 3, y: 0): CircuitComponent(kind: .output)]))
            sim.toggleLever(at: origin)
            for _ in 0..<20 { sim.advanceTick(); XCTAssertEqual(sim.power(at: rearTorch), .off) }
        }
        for targetKind in [CircuitComponentKind.output, .dust, .torch] {
            var sim = CircuitSimulator(world: CircuitWorld(components: [origin: CircuitComponent(kind: .lever), a: CircuitComponent(kind: .output),
                rearTorch: CircuitComponent(kind: targetKind, direction: .east)]))
            sim.toggleLever(at: origin)
            for _ in 0..<20 { sim.advanceTick(); XCTAssertEqual(sim.power(at: rearTorch), targetKind == .torch ? .full : .off) }
        }
    }

    func testSerialOutputsAccumulateDelayAndDoNotRetainStalePower() {
        var components = [origin: CircuitComponent(kind: .lever)]
        for x in 1...7 {
            components[WorldCoordinate(x: x, y: 0)] = CircuitComponent(kind: x % 2 == 1 ? .output : .repeater, direction: .east)
        }
        var sim = CircuitSimulator(world: CircuitWorld(components: components))
        sim.toggleLever(at: origin)
        for tick in 1...7 {
            XCTAssertEqual(sim.advanceTick(), tick % 2 == 1 ? [.outputActivated(WorldCoordinate(x: tick, y: 0))] : [])
        }
        sim.toggleLever(at: origin)
        for _ in 0..<7 { XCTAssertTrue(sim.advanceTick().isEmpty) }
        XCTAssertTrue(sim.power.isEmpty, "Open chains must not self-latch from the previous snapshot")
        sim.toggleLever(at: origin)
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(WorldCoordinate(x: 1, y: 0))])
    }

    func testButtonPulseOffEdgeClearsDownstreamAfterDelay() {
        let (original, tiles) = chain(.east, .four)
        var world = original
        world.components[tiles[0]] = CircuitComponent(kind: .button)
        var sim = CircuitSimulator(world: world)
        sim.pressButton(at: tiles[0])
        var events: [CircuitEvent] = []
        for _ in 0..<20 { events += sim.advanceTick() }
        XCTAssertEqual(events, [.outputActivated(tiles[2]), .outputActivated(tiles[4])])
        sim.advanceTick()
        XCTAssertEqual(sim.power(at: tiles[2]), .off)
        XCTAssertEqual(sim.power(at: tiles[4]), .full)
        for _ in 0..<8 { XCTAssertTrue(sim.advanceTick().isEmpty) }
        XCTAssertTrue(sim.power.isEmpty)
    }

    func testTorchOutputRepeaterFeedbackIsBoundedAndInsertionOrderIndependent() {
        let entries: [(WorldCoordinate, CircuitComponent)] = [
            (origin, CircuitComponent(kind: .torch, direction: .north)),
            (WorldCoordinate(x: 1, y: 0), CircuitComponent(kind: .output)),
            (WorldCoordinate(x: 2, y: 0), CircuitComponent(kind: .repeater, direction: .east)),
            (WorldCoordinate(x: 3, y: 0), CircuitComponent(kind: .dust)),
            (WorldCoordinate(x: 3, y: -1), CircuitComponent(kind: .dust)),
            (WorldCoordinate(x: 2, y: -1), CircuitComponent(kind: .dust)),
            (WorldCoordinate(x: 1, y: -1), CircuitComponent(kind: .dust)),
            (WorldCoordinate(x: 0, y: -1), CircuitComponent(kind: .dust))]
        var a = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries)))
        var b = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries.reversed())))
        var states = Set<Bool>()
        for _ in 0..<500 {
            XCTAssertEqual(a.advanceTick(), b.advanceTick())
            XCTAssertEqual(a.power, b.power)
            XCTAssertLessThanOrEqual(a.power.count, entries.count)
            states.insert(a.power(at: origin) > .off)
        }
        XCTAssertEqual(states, [true, false])
    }

    func testPickupAtCoordinateLimitsUsesCheckedAdjacency() {
        let a = WorldCoordinate(x: Int.max - 2, y: Int.min), repeater = WorldCoordinate(x: Int.max - 1, y: Int.min), b = WorldCoordinate(x: Int.max, y: Int.min)
        let lever = WorldCoordinate(x: Int.max - 3, y: Int.min)
        var sim = CircuitSimulator(world: CircuitWorld(components: [lever: CircuitComponent(kind: .lever), a: CircuitComponent(kind: .output),
            repeater: CircuitComponent(kind: .repeater, direction: .east), b: CircuitComponent(kind: .output)]))
        sim.toggleLever(at: lever)
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(a)])
        sim.advanceTick()
        XCTAssertEqual(sim.advanceTick(), [.outputActivated(b)])
        let output = CircuitComponent(kind: .output)
        XCTAssertFalse(output.emitsPower(from: b, to: lever, receiver: CircuitComponent(kind: .repeater, direction: .east)))
    }

    @MainActor
    func testRendererDrawsOnlyRearAndFrontOutputConnectionsForEveryOrientation() throws {
        let screen = ScreenDescriptor(id: "pickup", frame: CGRect(x: 0, y: 0, width: 640, height: 640), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let tile = WorldCoordinate(x: 3, y: 3)
        for direction in Direction.allCases {
            var components = [tile: CircuitComponent(kind: .repeater, direction: direction)]
            for port in Direction.allCases { components[port.neighbor(of: tile)!] = CircuitComponent(kind: .output) }
            let scene = DesktopScene(screen: screen, mapper: mapper)
            scene.updateWorld(World(circuit: CircuitWorld(components: components)))
            let traces = scene.childNode(withName: "circuit")!.children.filter { $0.name?.hasPrefix("repeater-port:") == true }
            XCTAssertEqual(traces.count, 2)
            for port in Direction.allCases {
                XCTAssertEqual(scene.childNode(withName: "//repeater-port:3,3:\(port.rawValue)") != nil, port == direction || port == direction.opposite)
            }
        }
    }
}
