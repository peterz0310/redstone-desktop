/// Presentation policy only; saved overrides and generation-1 placement remain intact.
enum TerrainAppearance {
    static func tile(_ tile: Tile, generated: Bool) -> Tile {
        guard generated, tile.terrain == .dirt else { return tile }
        var result = tile
        result.terrain = .grass
        return result
    }
}
