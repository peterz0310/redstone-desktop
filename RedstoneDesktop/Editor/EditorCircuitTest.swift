import Foundation

/// An action-free copy. Output events are counted locally and never reach a file executor.
struct EditorCircuitTest: Equatable, Sendable {
    let id = UUID()
    let worldID: UUID
    let source: CircuitWorld
    let initialLevers: Set<WorldCoordinate>
    private(set) var simulator: CircuitSimulator
    var isPlaying = true
    private(set) var tick = 0
    private(set) var outputPulses: [WorldCoordinate: Int] = [:]
    private(set) var lastOutputs: [WorldCoordinate] = []

    init(worldID: UUID, circuit: CircuitWorld, levers: Set<WorldCoordinate>) {
        self.worldID = worldID; source = circuit; initialLevers = levers
        simulator = CircuitSimulator(world: circuit)
        for lever in levers { simulator.toggleLever(at: lever) }
    }
    mutating func click(_ tile: WorldCoordinate) -> Bool {
        switch source.components[tile]?.kind {
        case .button: return simulator.pressButton(at: tile)
        case .lever: return simulator.toggleLever(at: tile)
        case .pressurePlate, .fileSensor:
            var active = simulator.activeDesktopSensors
            if !active.insert(tile).inserted { active.remove(tile) }
            simulator.setDesktopSensors(active)
            return true
        default: return false
        }
    }
    mutating func advance() {
        tick += 1
        lastOutputs = simulator.advanceTick().map { event in
            switch event { case .outputActivated(let tile): return tile }
        }
        for tile in lastOutputs { outputPulses[tile, default: 0] += 1 }
    }
}
