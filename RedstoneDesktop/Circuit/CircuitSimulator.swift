enum CircuitEvent: Equatable, Sendable {
    case outputActivated(WorldCoordinate)
}

/// Pure two-phase simulation. Repeater semantics arrive in Slice 12.
struct CircuitSimulator: Equatable, Sendable {
    static let buttonPulseTicks = 20
    let world: CircuitWorld
    private(set) var power: [WorldCoordinate: PowerLevel] = [:]
    private(set) var activeLevers: Set<WorldCoordinate> = []
    private var buttonTicks: [WorldCoordinate: Int] = [:]

    var poweredTiles: Set<WorldCoordinate> { Set(power.keys) }
    func power(at coordinate: WorldCoordinate) -> PowerLevel { power[coordinate] ?? .off }

    @discardableResult
    mutating func pressButton(at coordinate: WorldCoordinate) -> Bool {
        guard world.components[coordinate]?.kind == .button else { return false }
        buttonTicks[coordinate] = Self.buttonPulseTicks
        return true
    }

    @discardableResult
    mutating func toggleLever(at coordinate: WorldCoordinate) -> Bool {
        guard world.components[coordinate]?.kind == .lever else { return false }
        if !activeLevers.insert(coordinate).inserted { activeLevers.remove(coordinate) }
        return true
    }

    /// Inputs apply on the next tick. A press powers exactly 20 tick snapshots;
    /// the 21st is off unless repressed or another source still supplies power.
    mutating func advanceTick() -> [CircuitEvent] {
        let coordinates = world.components.keys.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        var next: [WorldCoordinate: PowerLevel] = [:]
        var queue: [WorldCoordinate] = []
        for coordinate in coordinates {
            let kind = world.components[coordinate]?.kind
            if (kind == .button && (buttonTicks[coordinate] ?? 0) > 0)
                || (kind == .lever && activeLevers.contains(coordinate)) {
                next[coordinate] = .full
                queue.append(coordinate)
            }
        }
        // Each queued dust coordinate strictly increases from 0 toward at most 15.
        // Thus at most 15 updates per dust tile, plus one per source; no recursion.
        var head = 0
        while head < queue.count {
            let coordinate = queue[head]
            head += 1
            let incoming = Int(next[coordinate]?.rawValue ?? 0)
            let outgoing = world.components[coordinate]?.kind == .dust ? incoming - 1 : incoming
            guard outgoing > 0 else { continue }
            for neighbor in world.occupiedCardinalNeighbors(at: coordinate)
                where world.components[neighbor]?.kind == .dust {
                if outgoing > Int(next[neighbor]?.rawValue ?? 0) {
                    next[neighbor] = PowerLevel(outgoing)
                    queue.append(neighbor)
                }
            }
        }
        var events: [CircuitEvent] = []
        for coordinate in coordinates where world.components[coordinate]?.kind == .output {
            // Outputs sense adjacent sources/dust and never enqueue or relay power.
            let strength = world.occupiedCardinalNeighbors(at: coordinate).reduce(PowerLevel.off) { level, neighbor in
                guard let kind = world.components[neighbor]?.kind,
                      kind == .dust || kind == .button || kind == .lever else { return level }
                return max(level, next[neighbor] ?? .off)
            }
            if strength > .off {
                next[coordinate] = strength
                if power(at: coordinate) == .off { events.append(.outputActivated(coordinate)) }
            }
        }
        // Commit only after the whole network and its rising edges are computed.
        power = next
        for coordinate in Array(buttonTicks.keys) {
            if let remaining = buttonTicks[coordinate], remaining > 1 {
                buttonTicks[coordinate] = remaining - 1
            } else {
                buttonTicks.removeValue(forKey: coordinate)
            }
        }
        return events
    }
}
