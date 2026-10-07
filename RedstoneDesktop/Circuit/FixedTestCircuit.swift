/// Slice 9 feasibility circuit only; the general circuit engine is a later slice.
struct FixedTestCircuit: Equatable, Sendable {
    static let button = WorldCoordinate(x: 2, y: 3)
    static let dust = (3...6).map { WorldCoordinate(x: $0, y: 3) }
    static let output = WorldCoordinate(x: 7, y: 3)
    static let pulseTicks = 20
    private(set) var remainingTicks = 0
    var isPowered: Bool { remainingTicks > 0 }

    var poweredTiles: Set<WorldCoordinate> {
        isPowered ? Set([Self.button] + Self.dust + [Self.output]) : []
    }

    /// Keeps the feasibility fixture out of the renderer; this is not generated terrain.
    static func makeWorld() -> World {
        var components = Dictionary(uniqueKeysWithValues: dust.map { ($0, CircuitComponent(kind: .dust)) })
        components[button] = CircuitComponent(kind: .button)
        components[output] = CircuitComponent(kind: .output)
        return World(tiles: Dictionary(uniqueKeysWithValues: components.keys.map { ($0, Tile(terrain: .grass)) }),
                     circuit: CircuitWorld(components: components))
    }

    enum Event: Equatable, Sendable {
        case outputActivated(WorldCoordinate)
    }

    mutating func press(at tile: WorldCoordinate) -> [Event] {
        guard tile == Self.button else { return [] }
        let wasPowered = isPowered
        remainingTicks = Self.pulseTicks
        return wasPowered ? [] : [.outputActivated(Self.output)]
    }

    mutating func advanceTick() {
        if remainingTicks > 0 { remainingTicks -= 1 }
    }
}
