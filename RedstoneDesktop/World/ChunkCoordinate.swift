struct ChunkCoordinate: Hashable, Codable, Sendable {
    static let size = 32
    var x: Int
    var y: Int

    static func containing(_ coordinate: WorldCoordinate) -> ChunkCoordinate {
        ChunkCoordinate(x: SeededNoise.floorDivision(coordinate.x, by: size).quotient,
                        y: SeededNoise.floorDivision(coordinate.y, by: size).quotient)
    }

    var worldOrigin: WorldCoordinate? {
        let x = x.multipliedReportingOverflow(by: Self.size)
        let y = y.multipliedReportingOverflow(by: Self.size)
        guard !x.overflow, !y.overflow else { return nil }
        return WorldCoordinate(x: x.partialValue, y: y.partialValue)
    }
}

struct TerrainChunk: Equatable, Sendable {
    let coordinate: ChunkCoordinate
    let tiles: [WorldCoordinate: Tile]
}
