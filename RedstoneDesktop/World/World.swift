/// Explicit terrain overrides plus an optional deterministic base.
/// Terrain and circuit identity are independent; runtime power lives in simulation.
struct World: Equatable, Codable, Sendable {
    var tiles: [WorldCoordinate: Tile] = [:]
    var circuit = CircuitWorld()
    var lighting: WorldLightingSettings? = nil
    var generation: WorldGenerationSettings? = nil
    var unspecifiedTiles: Set<WorldCoordinate> = []

    func tile(at coordinate: WorldCoordinate) -> Tile? {
        if let tile = tiles[coordinate] { return tile }
        guard !unspecifiedTiles.contains(coordinate), let generation,
              let generator = try? WorldGenerator(settings: generation) else { return nil }
        return generator.tile(at: coordinate)
    }
}
