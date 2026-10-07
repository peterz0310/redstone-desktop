enum CircuitEvent: Equatable, Sendable {
    case outputActivated(WorldCoordinate)
}

/// Pure two-phase simulation with bounded dust propagation and delayed repeaters.
struct CircuitSimulator: Equatable, Sendable {
    static let buttonPulseTicks = 20
    let world: CircuitWorld
    private(set) var power: [WorldCoordinate: PowerLevel] = [:]
    private(set) var activeLevers: Set<WorldCoordinate> = []
    private var repeaterHistory: [WorldCoordinate: [Bool]] = [:]
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
        // Mature every repeater from its previous bounded input history before
        // solving dust. A sample at tick T appears at T + delay, on both edges.
        var histories = repeaterHistory
        for coordinate in coordinates where world.components[coordinate]?.kind == .repeater {
            let delay = world.components[coordinate]!.repeaterDelay.simulationTicks
            var history = histories[coordinate] ?? Array(repeating: false, count: delay)
            if history.removeFirst() {
                next[coordinate] = .full
                queue.append(coordinate)
            }
            histories[coordinate] = history
        }
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
            let neighbors: [WorldCoordinate]
            if let component = world.components[coordinate], component.kind == .repeater {
                neighbors = component.direction.neighbor(of: coordinate).map { [$0] } ?? []
            } else {
                neighbors = world.occupiedCardinalNeighbors(at: coordinate)
            }
            for neighbor in neighbors where world.components[neighbor]?.kind == .dust {
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
                max(level, deliveredPower(from: neighbor, to: coordinate, snapshot: next))
            }
            if strength > .off {
                next[coordinate] = strength
                if power(at: coordinate) == .off { events.append(.outputActivated(coordinate)) }
            }
        }
        // Sample all rear inputs from the completed snapshot. No repeater can
        // read another's partially updated history, including in chains/loops.
        for coordinate in coordinates where world.components[coordinate]?.kind == .repeater {
            let rear = world.components[coordinate]!.direction.opposite.neighbor(of: coordinate)
            let input = rear.map { deliveredPower(from: $0, to: coordinate, snapshot: next) > .off } ?? false
            histories[coordinate]!.append(input)
        }
        repeaterHistory = histories
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

    /// Outputs never supply power; repeaters supply only to their front tile.
    private func deliveredPower(from source: WorldCoordinate, to target: WorldCoordinate,
                                snapshot: [WorldCoordinate: PowerLevel]) -> PowerLevel {
        guard let component = world.components[source] else { return .off }
        switch component.kind {
        case .button, .lever, .dust: return snapshot[source] ?? .off
        case .repeater:
            return component.direction.neighbor(of: source) == target ? snapshot[source] ?? .off : .off
        case .empty, .output: return .off
        }
    }
}
