import Foundation

/// Sparse configuration deltas, not full world snapshots or runtime power.
struct CircuitChange {
    let componentCoordinates: Set<WorldCoordinate>
    let terrainCoordinates: Set<WorldCoordinate>
    let terrainBefore: [WorldCoordinate: Tile], terrainAfter: [WorldCoordinate: Tile]
    let coordinates: Set<WorldCoordinate>
    let before: CircuitWorld, after: CircuitWorld
    let leversBefore: Set<WorldCoordinate>, leversAfter: Set<WorldCoordinate>
    init(before: CircuitWorld, after: CircuitWorld, leversBefore: Set<WorldCoordinate>, leversAfter: Set<WorldCoordinate>, terrainBefore: [WorldCoordinate: Tile] = [:], terrainAfter: [WorldCoordinate: Tile] = [:]) {
        let changed: Set<WorldCoordinate> = Set(before.components.keys).union(after.components.keys).filter { before.components[$0] != after.components[$0] }
        componentCoordinates = changed
        let terrainChanged = Set(terrainBefore.keys).union(terrainAfter.keys).filter { terrainBefore[$0] != terrainAfter[$0] }
        terrainCoordinates = terrainChanged
        self.terrainBefore = terrainBefore.filter { terrainChanged.contains($0.key) }
        self.terrainAfter = terrainAfter.filter { terrainChanged.contains($0.key) }
        coordinates = changed.union(terrainChanged)
        self.before = CircuitWorld(components: before.components.filter { changed.contains($0.key) })
        self.after = CircuitWorld(components: after.components.filter { changed.contains($0.key) })
        self.leversBefore = leversBefore.intersection(changed); self.leversAfter = leversAfter.intersection(changed)
    }
    func applying(to circuit: CircuitWorld, levers: Set<WorldCoordinate>, undo: Bool) throws -> (CircuitWorld, Set<WorldCoordinate>) {
        let expected = undo ? after : before, replacement = undo ? before : after
        guard componentCoordinates.allSatisfy({ circuit.components[$0] == expected.components[$0] }) else {
            throw BlueprintError("This circuit changed elsewhere. Nothing was undone.")
        }
        var result = circuit
        for point in componentCoordinates { result.components[point] = replacement.components[point] }
        return (result, levers.subtracting(componentCoordinates).union(undo ? leversBefore : leversAfter))
    }
    func applyingTerrain(to current: [WorldCoordinate: Tile], undo: Bool) throws -> [WorldCoordinate: Tile] {
        let expected = undo ? terrainAfter : terrainBefore, replacement = undo ? terrainBefore : terrainAfter
        guard terrainCoordinates.allSatisfy({ current[$0] == expected[$0] }) else { throw BlueprintError("Terrain changed elsewhere. Nothing was undone.") }
        var result = current
        for point in terrainCoordinates { result[point] = replacement[point] }
        return result
    }

}
struct CircuitEditHistory {
    private(set) var undo: [CircuitChange] = [], redo: [CircuitChange] = []
    mutating func record(_ change: CircuitChange) {
        guard !change.coordinates.isEmpty else { return }
        redo.removeAll(); undo.append(change)
        while undo.count > 100 || (undo.count > 1 && undo.reduce(0, { $0 + $1.coordinates.count }) > 50_000) { undo.removeFirst() }
    }
    mutating func didUndo() { if let change = undo.popLast() { redo.append(change) } }
    mutating func didRedo() { if let change = redo.popLast() { undo.append(change) } }
}
