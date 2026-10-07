/// Finite, explicit grass for editor authoring. These overrides protect existing circuits when a generated base is enabled.
enum EditorConstructionArea {
    static func makeWorld() -> World {
        var world = DeveloperPlacementFixture.makeWorld()
        for y in 7...11 {
            for x in 10...25 { world.tiles[WorldCoordinate(x: x, y: y)] = Tile(terrain: .grass) }
        }
        world.unspecifiedTiles.insert(WorldCoordinate(x: 14, y: 5))
        return world
    }
}
