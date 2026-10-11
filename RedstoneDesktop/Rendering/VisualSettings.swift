/// App-wide presentation preferences. Never affect world data or simulation.
struct VisualSettings: Codable, Equatable, Sendable {
    var liquidAnimations = true
    var sceneryAnimations = true
    var particles = true
}
