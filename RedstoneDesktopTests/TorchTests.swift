import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class TorchBuildPresenter: DesktopBuildPresenting {
    func show() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {}
    func close() {}
}

final class TorchTests: XCTestCase {
    private let origin = WorldCoordinate(x: 0, y: 0)

    func testAllOrientationsInvertRearWithExactBothEdgeDelayAndThreeOutputPorts() {
        for direction in Direction.allCases {
            let rear = direction.opposite.neighbor(of: origin)!
            let outputs = Direction.allCases.filter { $0 != direction.opposite }.map { $0.neighbor(of: origin)! }
            var components = [origin: CircuitComponent(kind: .torch, direction: direction), rear: CircuitComponent(kind: .lever)]
            for output in outputs { components[output] = CircuitComponent(kind: .output) }
            var sim = CircuitSimulator(world: CircuitWorld(components: components))
            XCTAssertEqual(sim.advanceTick(), outputs.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map(CircuitEvent.outputActivated))
            XCTAssertEqual(sim.power(at: origin), .full)
            XCTAssertEqual(sim.power(at: rear), .off)
            sim.toggleLever(at: rear)
            for _ in 0..<2 { XCTAssertTrue(sim.advanceTick().isEmpty); XCTAssertEqual(sim.power(at: origin), .full) }
            XCTAssertTrue(sim.advanceTick().isEmpty)
            XCTAssertEqual(sim.power(at: origin), .off)
            for output in outputs { XCTAssertEqual(sim.power(at: output), .off) }
            sim.toggleLever(at: rear)
            for _ in 0..<2 { XCTAssertTrue(sim.advanceTick().isEmpty); XCTAssertEqual(sim.power(at: origin), .off) }
            XCTAssertEqual(sim.advanceTick(), outputs.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map(CircuitEvent.outputActivated))
            for output in outputs { XCTAssertEqual(sim.power(at: output), .full) }
        }
    }

    func testSidePowerDoesNotInhibitAndRearOutputDoesNotReceiveOrSupplyPower() {
        for direction in Direction.allCases {
            let rear = direction.opposite.neighbor(of: origin)!
            let front = direction.neighbor(of: origin)!
            var sim = CircuitSimulator(world: CircuitWorld(components: [origin: CircuitComponent(kind: .torch, direction: direction),
                rear: CircuitComponent(kind: .output), front: CircuitComponent(kind: .lever)]))
            sim.toggleLever(at: front)
            for _ in 0..<10 {
                XCTAssertTrue(sim.advanceTick().isEmpty)
                XCTAssertEqual(sim.power(at: origin), .full)
                XCTAssertEqual(sim.power(at: rear), .off)
            }
        }
    }

    func testTorchPowersDustAndDirectedRepeaterWithAdditionalDelay() {
        for direction in Direction.allCases {
            let dust = direction.neighbor(of: origin)!
            let repeater = direction.neighbor(of: dust)!
            let output = direction.neighbor(of: repeater)!
            var sim = CircuitSimulator(world: CircuitWorld(components: [origin: CircuitComponent(kind: .torch, direction: direction),
                dust: CircuitComponent(kind: .dust), repeater: CircuitComponent(kind: .repeater, direction: direction), output: CircuitComponent(kind: .output)]))
            XCTAssertTrue(sim.advanceTick().isEmpty)
            XCTAssertEqual(sim.power(at: dust), .full)
            XCTAssertTrue(sim.advanceTick().isEmpty)
            XCTAssertEqual(sim.advanceTick(), [.outputActivated(output)])
            XCTAssertEqual(sim.power(at: repeater), .full)
            XCTAssertEqual(sim.power(at: output), .full)
        }
    }

    func testFacingRepeaterControlsTorchButSidePortDoesNot() {
        for facing in [true, false] {
            let rear = WorldCoordinate(x: -1, y: 0), lever = WorldCoordinate(x: -2, y: 0)
            var sim = CircuitSimulator(world: CircuitWorld(components: [origin: CircuitComponent(kind: .torch, direction: .east),
                rear: CircuitComponent(kind: .repeater, direction: facing ? .east : .north), lever: CircuitComponent(kind: .lever)]))
            sim.toggleLever(at: lever)
            for _ in 0..<4 { sim.advanceTick(); XCTAssertEqual(sim.power(at: origin), .full) }
            sim.advanceTick()
            XCTAssertEqual(sim.power(at: origin), facing ? .off : .full)
        }
    }

    func testTorchRearSamplesOnlyAnotherTorchEmittingPort() {
        let rear = WorldCoordinate(x: -1, y: 0)
        for direction in Direction.allCases {
            var sim = CircuitSimulator(world: CircuitWorld(components: [origin: CircuitComponent(kind: .torch, direction: .east),
                rear: CircuitComponent(kind: .torch, direction: direction)]))
            sim.advanceTick(); sim.advanceTick(); sim.advanceTick()
            XCTAssertEqual(sim.power(at: origin), direction == .west ? .full : .off)
        }
    }

    func testFeedbackIsBoundedDeterministicAndInsertionOrderIndependent() {
        let entries: [(WorldCoordinate, CircuitComponent)] = [
            (origin, CircuitComponent(kind: .dust)),
            (WorldCoordinate(x: 1, y: 0), CircuitComponent(kind: .torch, direction: .east)),
            (WorldCoordinate(x: 1, y: 1), CircuitComponent(kind: .dust)),
            (WorldCoordinate(x: 0, y: 1), CircuitComponent(kind: .dust)),
            (WorldCoordinate(x: 2, y: 0), CircuitComponent(kind: .output))]
        var first = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries)))
        var second = CircuitSimulator(world: CircuitWorld(components: Dictionary(uniqueKeysWithValues: entries.reversed())))
        var edges = 0, states = Set<Bool>()
        for _ in 0..<300 {
            let events = first.advanceTick()
            XCTAssertEqual(events, second.advanceTick())
            XCTAssertEqual(first.power, second.power)
            XCTAssertLessThanOrEqual(first.power.count, entries.count)
            states.insert(first.power(at: WorldCoordinate(x: 1, y: 0)) > .off)
            edges += events.count
        }
        XCTAssertEqual(states, [true, false])
        XCTAssertGreaterThan(edges, 1)
        XCTAssertLessThan(edges, 150)
    }

    func testTorchAdjacencyAtIntegerLimitsDoesNotOverflow() {
        for coordinate in [WorldCoordinate(x: .min, y: .max), WorldCoordinate(x: .max, y: .min)] {
            for direction in Direction.allCases {
                var sim = CircuitSimulator(world: CircuitWorld(components: [coordinate: CircuitComponent(kind: .torch, direction: direction)]))
                for _ in 0..<10 { XCTAssertTrue(sim.advanceTick().isEmpty); XCTAssertEqual(sim.power(at: coordinate), .full) }
            }
        }
    }

    func testOldComponentDefaultsAndTorchWorldRoundTripPreserveConfigurationOnly() throws {
        let old = try JSONDecoder().decode(CircuitComponent.self, from: Data(#"{"kind":"repeater","direction":"east"}"#.utf8))
        XCTAssertEqual(old.repeaterDelay, .one)
        XCTAssertEqual(old.outputAction, .openOccupant)
        var document = WorldDocument(name: "Torch", terrainProfile: .legacyFixtureV1)
        let tile = WorldCoordinate(x: 10, y: 7)
        document.circuit.components[tile] = CircuitComponent(kind: .torch, direction: .west)
        let decoded = try JSONDecoder().decode(WorldDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded, document)
        let restored = try decoded.restoredWorld()
        XCTAssertEqual(restored.circuit.components[tile]?.direction, .west)
        let fresh = CircuitSimulator(world: restored.circuit)
        XCTAssertTrue(fresh.power.isEmpty)
        XCTAssertTrue(fresh.activeLevers.isEmpty)
    }

    @MainActor
    func testEditorAndBuildTorchDirectionEraseAndFixedDelay() throws {
        let screen = ScreenDescriptor(id: "torch", frame: CGRect(x: -100, y: -200, width: 1280, height: 800), backingScale: 2)
        let app = AppState(screenProviding: { screen }, tickScheduler: ManualCircuitTickScheduler(),
            buildControllerFactory: { _, _, _ in TorchBuildPresenter() })
        defer { app.shutdown() }
        let tile = WorldCoordinate(x: 10, y: 7)
        XCTAssertEqual(app.placeCircuitComponent(CircuitComponent(kind: .torch, direction: .east), at: tile), .allowed)
        XCTAssertTrue(app.configureTorch(at: tile, direction: .north))
        XCTAssertTrue(app.enterDesktopBuildMode())
        let session = try XCTUnwrap(app.buildSession)
        session.hoveredTile = tile
        app.editHoveredBuildRepeater(at: tile, rotate: true)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.direction, .east)
        let before = app.desktopWorld.circuit.components[tile]
        app.editHoveredBuildRepeater(at: tile, rotate: false)
        app.setBuildRepeaterDelay(.four)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile], before)
        let rect = session.mapper.screenRect(forTile: tile)
        app.buildClick(at: CGPoint(x: rect.midX, y: rect.midY), erase: true, sessionID: session.id)
        XCTAssertNil(app.desktopWorld.circuit.components[tile])
        session.tool = .torch
        session.direction = .south
        app.buildClick(at: CGPoint(x: rect.midX, y: rect.midY), sessionID: session.id)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.kind, .torch)
        XCTAssertEqual(app.desktopWorld.circuit.components[tile]?.direction, .south)
        app.exitDesktopBuildMode()
        XCTAssertEqual(app.editorWorld.circuit.components[tile], app.desktopWorld.circuit.components[tile])
    }

    @MainActor
    func testRepeaterTracesMatchTorchEmissionAndRearInputPorts() throws {
        let screen = ScreenDescriptor(id: "ports", frame: CGRect(x: 0, y: 0, width: 640, height: 640), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let repeater = WorldCoordinate(x: 3, y: 3)
        for direction in Direction.allCases {
            for torchDirection in Direction.allCases {
                let front = direction.neighbor(of: repeater)!, rear = direction.opposite.neighbor(of: repeater)!
                let world = World(circuit: CircuitWorld(components: [repeater: CircuitComponent(kind: .repeater, direction: direction),
                    front: CircuitComponent(kind: .torch, direction: torchDirection), rear: CircuitComponent(kind: .torch, direction: torchDirection)]))
                let scene = DesktopScene(screen: screen, mapper: mapper)
                scene.updateWorld(world)
                let frontTrace = scene.childNode(withName: "//repeater-port:3,3:\(direction.rawValue)")
                let rearTrace = scene.childNode(withName: "//repeater-port:3,3:\(direction.opposite.rawValue)")
                XCTAssertEqual(frontTrace != nil, torchDirection == direction)
                XCTAssertEqual(rearTrace != nil, torchDirection != direction.opposite)
            }
        }
    }

    @MainActor
    func testTorchRendererStatesDirectionAndOptionalSoundArePresentationOnly() throws {
        let screen = ScreenDescriptor(id: "torch", frame: CGRect(x: 0, y: 0, width: 640, height: 640), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let tile = WorldCoordinate(x: 2, y: 2)
        let world = World(circuit: CircuitWorld(components: [tile: CircuitComponent(kind: .torch, direction: .west)]))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        scene.updateWorld(world)
        let icon = try XCTUnwrap(scene.childNode(withName: "//component-icon:2,2") as? SKSpriteNode)
        let offTexture = icon.texture
        scene.updateWorld(world, poweredTiles: [tile])
        let onIcon = try XCTUnwrap(scene.childNode(withName: "//component-icon:2,2") as? SKSpriteNode)
        XCTAssertFalse(offTexture === onIcon.texture)
        let label = try XCTUnwrap(scene.childNode(withName: "//state-label:2,2") as? SKLabelNode)
        XCTAssertEqual(label.text, "← NOT")
        var after = CircuitSimulator(world: world.circuit)
        let before = after
        after.advanceTick()
        let sounds = CircuitSounds.transitions(before: before, after: after)
        XCTAssertEqual(sounds.map(\.0), [.torchToggle])
        XCTAssertEqual(sounds.map(\.1), [tile])
        XCTAssertEqual(CircuitTextureID.torchOff.assetID, .redstoneTorchOff)
        XCTAssertEqual(CircuitTextureID.torchOn.assetID, .redstoneTorchOn)
    }
}
