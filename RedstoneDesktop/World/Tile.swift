struct Tile: Equatable, Codable, Sendable {
    var terrain: TerrainID
    var decoration: DecorationID? = nil
}
