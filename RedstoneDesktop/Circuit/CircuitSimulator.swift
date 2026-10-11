enum CircuitEvent: Equatable, Sendable {
    case outputActivated(WorldCoordinate)
}

/// Pure two-phase simulation with bounded dust propagation and delayed repeaters and torch inversion.
struct CircuitSimulator: Equatable, Sendable {
    static let buttonPulseTicks = 20
    static let torchDelayTicks = 2
    let world: CircuitWorld
    private(set) var power: [WorldCoordinate: PowerLevel] = [:]
    private(set) var activeLevers: Set<WorldCoordinate> = []
    private var delayedHistory: [WorldCoordinate: [Bool]] = [:]
    private(set) var activeDesktopSensors: Set<WorldCoordinate> = []
    mutating func setDesktopSensors(_ active: Set<WorldCoordinate>) {
        activeDesktopSensors = active.filter { world.components[$0]?.kind.isDesktopSensor == true }
    }
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
        // Mature every delayed component from its previous bounded history before
        // solving dust. A sample at tick T appears at T + delay, on both edges.
        var histories = delayedHistory
        for coordinate in coordinates where [.repeater, .torch].contains(world.components[coordinate]!.kind) {
            let component = world.components[coordinate]!
            let delay = component.kind == .torch ? Self.torchDelayTicks : component.repeaterDelay.simulationTicks
            var history = histories[coordinate] ?? Array(repeating: component.kind == .torch, count: delay)
            if history.removeFirst() {
                next[coordinate] = .full
                queue.append(coordinate)
            }
            histories[coordinate] = history
        }
        for coordinate in coordinates {
            let kind = world.components[coordinate]?.kind
            if (kind == .button && (buttonTicks[coordinate] ?? 0) > 0)
                || (kind == .lever && activeLevers.contains(coordinate))
                || (kind?.isDesktopSensor == true && activeDesktopSensors.contains(coordinate)) {
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
            neighbors = world.occupiedCardinalNeighbors(at: coordinate).filter {
                world.components[coordinate]!.emitsPower(from: coordinate, to: $0)
            }
            for neighbor in neighbors where world.components[neighbor]?.kind == .dust {
                if outgoing > Int(next[neighbor]?.rawValue ?? 0) {
                    next[neighbor] = PowerLevel(outgoing)
                    queue.append(neighbor)
                }
            }
        }
        var events: [CircuitEvent] = []
        for coordinate in coordinates where [.output, .lamp].contains(world.components[coordinate]!.kind) {
            // Outputs sense emitting neighbors without enqueueing dust or feeding other Outputs.
            let strength = world.occupiedCardinalNeighbors(at: coordinate).reduce(PowerLevel.off) { level, neighbor in
                max(level, deliveredPower(from: neighbor, to: coordinate, snapshot: next))
            }
            if strength > .off {
                next[coordinate] = strength
                if world.components[coordinate]?.kind == .output && power(at: coordinate) == .off { events.append(.outputActivated(coordinate)) }
            }
        }
        // Sample all repeater/torch rear inputs from the completed snapshot. No delayed component can
        // read another's partially updated history, including in chains/loops.
        for coordinate in coordinates where [.repeater, .torch].contains(world.components[coordinate]!.kind) {
            let rear = world.components[coordinate]!.direction.opposite.neighbor(of: coordinate)
            let input = rear.map { deliveredPower(from: $0, to: coordinate, snapshot: next) > .off } ?? false
            histories[coordinate]!.append(world.components[coordinate]!.kind == .torch ? !input : input)
        }
        delayedHistory = histories
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

    /// Output pickup is restricted to a receiver repeater rear; all inputs use the completed snapshot.
    private func deliveredPower(from source: WorldCoordinate, to target: WorldCoordinate,
                                snapshot: [WorldCoordinate: PowerLevel]) -> PowerLevel {
        guard let component = world.components[source], component.emitsPower(from: source, to: target, receiver: world.components[target]) else { return .off }
        return snapshot[source] ?? .off
    }
}
