/// Finite, explicit grass for editor authoring. Seeded generation remains Slice 17.
enum EditorConstructionArea {
    static func makeWorld() -> World {
        var world = DeveloperPlacementFixture.makeWorld()
        for y in 7...11 {
            for x in 10...25 { world.tiles[WorldCoordinate(x: x, y: y)] = Tile(terrain: .grass) }
        }
        return world
    }
}
