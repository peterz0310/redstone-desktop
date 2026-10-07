struct CameraState: Equatable, Codable, Sendable {
    /// World position at the lower-left corner of the virtual desktop canvas.
    var worldOrigin: WorldPoint

    /// Tile size in macOS logical points, independent of Retina backing scale.
    var pointsPerTile: Double
}
