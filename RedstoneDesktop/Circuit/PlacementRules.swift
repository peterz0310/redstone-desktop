enum PlacementFailureReason: Equatable, Sendable {
    case emptyComponent
    case reserved
    case noSolidSurface
    case liquid
    case unsupportedSurface
    case blockedByDecoration(DecorationID)
    case circuitOccupied

    var message: String {
        switch self {
        case .emptyComponent: return "Choose a component to place. Empty is not an erase tool."
        case .reserved: return "This tile is reserved for another use."
        case .noSolidSurface: return "This tile has no specified solid terrain."
        case .liquid: return "Circuit components cannot be placed on water."
        case .unsupportedSurface: return "This terrain does not support that component."
        case let .blockedByDecoration(decoration): return "Placement is blocked by \(decoration == .rock ? "ore deposit" : decoration.rawValue)."
        case .circuitOccupied: return "This tile already contains a circuit component."
        }
    }
}

enum PlacementResult: Equatable, Sendable {
    case allowed
    case rejected(PlacementFailureReason)

    var isAllowed: Bool { self == .allowed }
    var message: String {
        switch self {
        case .allowed: return "Placement allowed."
        case let .rejected(reason): return reason.message
        }
    }
}

protocol PlacementRuleEvaluating {
    func canPlace(component: CircuitComponent, at coordinate: WorldCoordinate, in world: World) -> PlacementResult
}

/// Shared by developer UI and future editor/build tools; no rendering or macOS dependencies.
struct PlacementRules: PlacementRuleEvaluating {
    var reservedCoordinates: Set<WorldCoordinate> = []

    func canPlace(component: CircuitComponent, at coordinate: WorldCoordinate, in world: World) -> PlacementResult {
        guard component.kind != .empty else { return .rejected(.emptyComponent) }
        guard !reservedCoordinates.contains(coordinate) else { return .rejected(.reserved) }
        guard let tile = world.tile(at: coordinate) else { return .rejected(.noSolidSurface) }
        let terrain = tile.terrain.definition
        guard !terrain.isLiquid else { return .rejected(.liquid) }
        guard terrain.isSolidSurface else { return .rejected(.noSolidSurface) }
        guard component.kind == .dust ? terrain.supportsCircuit : terrain.supportsHeavyComponent else {
            return .rejected(.unsupportedSurface)
        }
        // Decorations are preserved, including reeds, until a deliberate clearing tool exists.
        if let decoration = tile.decoration { return .rejected(.blockedByDecoration(decoration)) }
        if let existing = world.circuit.components[coordinate], existing.kind != .empty {
            return .rejected(.circuitOccupied)
        }
        return .allowed
    }
}

/// Evaluate and commit together. Rejection leaves the entire world unchanged.
struct CircuitPlacement {
    let rules: any PlacementRuleEvaluating

    init(rules: any PlacementRuleEvaluating = PlacementRules()) { self.rules = rules }

    @discardableResult
    func place(_ component: CircuitComponent, at coordinate: WorldCoordinate, in world: inout World) -> PlacementResult {
        let result = rules.canPlace(component: component, at: coordinate, in: world)
        guard result.isAllowed else { return result }
        world.circuit.components[coordinate] = component
        return .allowed
    }
}
