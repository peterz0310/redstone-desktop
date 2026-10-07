/// World orientation; north follows the positive world Y axis.
enum Direction: String, CaseIterable, Codable, Sendable {
    case north, east, south, west
}
