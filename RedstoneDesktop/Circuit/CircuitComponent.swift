enum CircuitComponentKind: String, CaseIterable, Codable, Sendable {
    case empty, dust, button, lever, repeater, output
}

/// Component configuration only. Runtime simulation and actions are separate layers.
struct CircuitComponent: Equatable, Codable, Sendable {
    var kind: CircuitComponentKind
    var direction: Direction
    var repeaterDelay: RepeaterDelay

    init(kind: CircuitComponentKind, direction: Direction = .north, repeaterDelay: RepeaterDelay = .one) {
        self.kind = kind
        self.direction = direction
        self.repeaterDelay = repeaterDelay
    }

    private enum CodingKeys: String, CodingKey { case kind, direction, repeaterDelay }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(CircuitComponentKind.self, forKey: .kind)
        direction = try values.decode(Direction.self, forKey: .direction)
        // Models encoded before Slice 12 did not include delay configuration.
        if values.contains(.repeaterDelay) {
            repeaterDelay = try values.decode(RepeaterDelay.self, forKey: .repeaterDelay)
        } else { repeaterDelay = .one }
    }
}
