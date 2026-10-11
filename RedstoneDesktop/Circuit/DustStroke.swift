import Foundation

/// Pure, bounded placement preview. Diagonal movement includes an elbow so dust connects.
struct DustStroke {
    let document: WorldDocument
    private(set) var tiles: Set<WorldCoordinate> = []
    private(set) var last: WorldCoordinate?
    private(set) var world: World?
    private(set) var placed = 0
    private(set) var blocked = 0

    mutating func extend(to tile: WorldCoordinate) throws {
        var candidate = tiles
        let line = try TerrainEditing.line(from: last ?? tile, to: tile)
        for (index, point) in line.enumerated() {
            if index > 0, line[index - 1].x != point.x, line[index - 1].y != point.y {
                let previous = line[index - 1]
                candidate.insert(WorldCoordinate(x: point.y > previous.y ? point.x : previous.x, y: min(point.y, previous.y)))
            }
            candidate.insert(point)
        }
        guard candidate.count <= TerrainEditing.maximumStrokeTiles else { throw BlueprintError("Dust path is too long. Release and draw another path.") }
        var next = try document.restoredWorld()
        var placed = 0, blocked = 0
        for coordinate in candidate {
            if next.circuit.components[coordinate]?.kind == .dust { continue }
            if CircuitPlacement().place(CircuitComponent(kind: .dust), at: coordinate, in: &next).isAllowed { placed += 1 }
            else { blocked += 1 }
        }
        tiles = candidate; last = tile; world = next; self.placed = placed; self.blocked = blocked
    }
}
