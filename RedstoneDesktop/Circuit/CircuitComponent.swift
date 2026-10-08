enum OutputActionMode: String, CaseIterable, Codable, Sendable {
    case openOccupant, executeOccupant, none
}

enum CircuitComponentKind: String, CaseIterable, Codable, Sendable {
    case empty, dust, button, lever, repeater, output, torch
}

/// Component configuration only. Runtime simulation and actions are separate layers.
struct CircuitComponent: Equatable, Codable, Sendable {
    var kind: CircuitComponentKind
    var direction: Direction
    var outputAction: OutputActionMode
    var repeaterDelay: RepeaterDelay

    init(kind: CircuitComponentKind, direction: Direction = .north, repeaterDelay: RepeaterDelay = .one, outputAction: OutputActionMode = .openOccupant) {
        self.outputAction = outputAction
        self.kind = kind
        self.direction = direction
        self.repeaterDelay = repeaterDelay
    }

    /// Shared domain port table for simulation and presentation.
    func emitsPower(from source: WorldCoordinate, to target: WorldCoordinate, receiver: CircuitComponent? = nil) -> Bool {
        guard Direction.allCases.contains(where: { $0.neighbor(of: source) == target }) else { return false }
        switch kind {
        case .button, .lever, .dust: return true
        case .repeater: return direction.neighbor(of: source) == target
        case .torch: return direction.opposite.neighbor(of: source) != target
        case .output:
            // Only a directed repeater rear can pick up a powered Output block.
            return receiver?.kind == .repeater && receiver?.direction.opposite.neighbor(of: target) == source
        case .empty: return false
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, direction, repeaterDelay, outputAction }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        outputAction = values.contains(.outputAction) ? try values.decode(OutputActionMode.self, forKey: .outputAction) : .openOccupant
        kind = try values.decode(CircuitComponentKind.self, forKey: .kind)
        direction = try values.decode(Direction.self, forKey: .direction)
        // Models encoded before Slice 12 did not include delay configuration.
        if values.contains(.repeaterDelay) {
            repeaterDelay = try values.decode(RepeaterDelay.self, forKey: .repeaterDelay)
        } else { repeaterDelay = .one }
    }
}
