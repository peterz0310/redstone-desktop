/// Slice 9 feasibility circuit only; the general circuit engine is a later slice.
struct FixedTestCircuit: Equatable, Sendable {
    static let button = WorldCoordinate(x: 2, y: 3)
    static let dust = (3...6).map { WorldCoordinate(x: $0, y: 3) }
    static let output = WorldCoordinate(x: 7, y: 3)
    static let pulseTicks = 20
    private(set) var remainingTicks = 0
    var isPowered: Bool { remainingTicks > 0 }

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
