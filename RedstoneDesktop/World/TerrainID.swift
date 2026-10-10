/// Semantic terrain identity; generation and capabilities are defined separately.
enum TerrainID: String, CaseIterable, Codable, Sendable {
    case grass, dirt, stone, sand, shallowWater, deepWater, dryGrass, snow, gravel, lava
}
