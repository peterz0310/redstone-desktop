/// Explicit test terrain to the right of the proven circuits, not generated terrain.
enum DeveloperPlacementFixture {
    struct Target: Identifiable {
        let name: String
        let coordinate: WorldCoordinate
        let tile: Tile?
        var id: WorldCoordinate { coordinate }
    }

    static let targets: [Target] = TerrainID.allCases.enumerated().map { index, terrain in
        Target(name: terrain.rawValue, coordinate: WorldCoordinate(x: 10 + index, y: 3), tile: Tile(terrain: terrain))
    } + DecorationID.allCases.enumerated().map { index, decoration in
        Target(name: decoration.rawValue, coordinate: WorldCoordinate(x: 10 + index, y: 5),
               tile: Tile(terrain: .grass, decoration: decoration))
    } + [Target(name: "unspecified", coordinate: WorldCoordinate(x: 14, y: 5), tile: nil)]

    static func makeWorld() -> World {
        var world = DemoCircuit.makeWorld()
        for target in targets { world.tiles[target.coordinate] = target.tile }
        return world
    }
}
