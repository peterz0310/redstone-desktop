/// Semantic terrain identity; generation and placement rules are later slices.
enum TerrainID: String, CaseIterable, Codable, Sendable {
    case grass, dirt, stone, sand, shallowWater, deepWater
}
