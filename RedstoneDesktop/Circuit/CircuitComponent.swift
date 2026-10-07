enum CircuitComponentKind: String, CaseIterable, Codable, Sendable {
    case empty, dust, button, lever, repeater, output
}

/// Component identity and orientation only. Simulation and actions are separate layers.
struct CircuitComponent: Equatable, Codable, Sendable {
    var kind: CircuitComponentKind
    var direction: Direction = .north
}
