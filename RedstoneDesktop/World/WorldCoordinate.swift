/// An integer tile address in the persistent world, independent of screen geometry.
struct WorldCoordinate: Hashable, Codable, Sendable {
    var x: Int
    var y: Int
}
