import Foundation

/// Sparse configuration deltas, not full world snapshots or runtime power.
struct CircuitChange {
    let coordinates: Set<WorldCoordinate>
    let before: CircuitWorld, after: CircuitWorld
    let leversBefore: Set<WorldCoordinate>, leversAfter: Set<WorldCoordinate>
    init(before: CircuitWorld, after: CircuitWorld, leversBefore: Set<WorldCoordinate>, leversAfter: Set<WorldCoordinate>) {
        let changed: Set<WorldCoordinate> = Set(before.components.keys).union(after.components.keys).filter { before.components[$0] != after.components[$0] }
        coordinates = changed
        self.before = CircuitWorld(components: before.components.filter { changed.contains($0.key) })
        self.after = CircuitWorld(components: after.components.filter { changed.contains($0.key) })
        self.leversBefore = leversBefore.intersection(coordinates); self.leversAfter = leversAfter.intersection(coordinates)
    }
    func applying(to circuit: CircuitWorld, levers: Set<WorldCoordinate>, undo: Bool) throws -> (CircuitWorld, Set<WorldCoordinate>) {
        let expected = undo ? after : before, replacement = undo ? before : after
        guard coordinates.allSatisfy({ circuit.components[$0] == expected.components[$0] }) else {
            throw BlueprintError("This circuit changed elsewhere. Nothing was undone.")
        }
        var result = circuit
        for point in coordinates { result.components[point] = replacement.components[point] }
        return (result, levers.subtracting(coordinates).union(undo ? leversBefore : leversAfter))
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
