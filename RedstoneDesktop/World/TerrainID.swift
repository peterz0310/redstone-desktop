/// Semantic terrain identity; generation remains a later slice; capabilities are defined separately.
enum TerrainID: String, CaseIterable, Codable, Sendable {
    case grass, dirt, stone, sand, shallowWater, deepWater
}
