/// Explicit tiles only for this slice. Missing tiles are unspecified, not generated.
/// Terrain and circuit identity are independent; runtime power lives in simulation.
struct World: Equatable, Codable, Sendable {
    var tiles: [WorldCoordinate: Tile] = [:]
    var circuit = CircuitWorld()
}
