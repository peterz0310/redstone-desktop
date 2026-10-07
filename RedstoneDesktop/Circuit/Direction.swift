/// World orientation; north follows the positive world Y axis.
enum Direction: String, CaseIterable, Codable, Sendable {
    case north, east, south, west

    var opposite: Direction {
        switch self {
        case .north: return .south
        case .east: return .west
        case .south: return .north
        case .west: return .east
        }
    }

    /// Domain adjacency, with checked arithmetic at the limits of world coordinates.
    func neighbor(of coordinate: WorldCoordinate) -> WorldCoordinate? {
        let dx: Int, dy: Int
        switch self {
        case .north: (dx, dy) = (0, 1)
        case .east: (dx, dy) = (1, 0)
        case .south: (dx, dy) = (0, -1)
        case .west: (dx, dy) = (-1, 0)
        }
        let (x, overflowX) = coordinate.x.addingReportingOverflow(dx)
        let (y, overflowY) = coordinate.y.addingReportingOverflow(dy)
        guard !overflowX, !overflowY else { return nil }
        return WorldCoordinate(x: x, y: y)
    }
}
