struct CircuitWorld: Equatable, Codable, Sendable {
    var components: [WorldCoordinate: CircuitComponent] = [:]

    /// Geometric neighbors in a fixed order; signal connection rules belong to the later simulator.
    /// Checked arithmetic keeps even extreme domain coordinates safe.
    func occupiedCardinalNeighbors(at coordinate: WorldCoordinate) -> [WorldCoordinate] {
        [(0, 1), (1, 0), (0, -1), (-1, 0)].compactMap { dx, dy in
            let (x, overflowX) = coordinate.x.addingReportingOverflow(dx)
            let (y, overflowY) = coordinate.y.addingReportingOverflow(dy)
            guard !overflowX, !overflowY else { return nil }
            let neighbor = WorldCoordinate(x: x, y: y)
            guard let component = components[neighbor], component.kind != .empty else { return nil }
            return neighbor
        }
    }
}
