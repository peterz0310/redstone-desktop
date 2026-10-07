struct CircuitWorld: Equatable, Codable, Sendable {
    var components: [WorldCoordinate: CircuitComponent] = [:]

    /// Geometric neighbors in a fixed order; signal connection rules belong to the simulator.
    /// Checked arithmetic keeps even extreme domain coordinates safe.
    func occupiedCardinalNeighbors(at coordinate: WorldCoordinate) -> [WorldCoordinate] {
        Direction.allCases.compactMap { direction in
            guard let neighbor = direction.neighbor(of: coordinate) else { return nil }
            guard let component = components[neighbor], component.kind != .empty else { return nil }
            return neighbor
        }
    }
}
