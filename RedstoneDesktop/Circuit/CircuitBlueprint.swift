import Foundation

struct CircuitBlueprint: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var circuit: CircuitWorld
    var activeLevers: Set<WorldCoordinate>
    static let maximumComponents = 4096

    static func capture(name: String, components: [WorldCoordinate: CircuitComponent], levers: Set<WorldCoordinate> = []) throws -> Self {
        guard let minX = components.keys.map(\.x).min(), let minY = components.keys.map(\.y).min() else {
            throw BlueprintError("Select at least one component first.")
        }
        var cells: [WorldCoordinate: CircuitComponent] = [:]
        var savedLevers: Set<WorldCoordinate> = []
        for (point, component) in components {
            let (x, ox) = point.x.subtractingReportingOverflow(minX), (y, oy) = point.y.subtractingReportingOverflow(minY)
            guard !ox, !oy else { throw BlueprintError("This selection is too spread out.") }
            let relative = WorldCoordinate(x: x, y: y)
            cells[relative] = component
            if levers.contains(point) { savedLevers.insert(relative) }
        }
        let result = Self(name: name.trimmingCharacters(in: .whitespacesAndNewlines), circuit: CircuitWorld(components: cells), activeLevers: savedLevers)
        try result.validate(); return result
    }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 128,
              !circuit.components.isEmpty, circuit.components.count <= Self.maximumComponents,
              circuit.components.allSatisfy({ (0..<256).contains($0.key.x) && (0..<256).contains($0.key.y) && $0.value.kind != .empty && $0.value.sensorFilter.isValid }),
              activeLevers.allSatisfy({ circuit.components[$0]?.kind == .lever }) else {
            throw BlueprintError("A blueprint needs a name and 1–4096 components inside a 256×256 area.")
        }
    }
    var width: Int { (circuit.components.keys.map(\.x).max() ?? 0) + 1 }
    var height: Int { (circuit.components.keys.map(\.y).max() ?? 0) + 1 }
    func rotatedClockwise() throws -> Self {
        try validate()
        var result = self
        result.circuit.components = Dictionary(uniqueKeysWithValues: circuit.components.map { point, original in
            var component = original; component.direction = original.direction.clockwise
            return (WorldCoordinate(x: point.y, y: width - 1 - point.x), component)
        })
        result.activeLevers = Set(activeLevers.map { WorldCoordinate(x: $0.y, y: width - 1 - $0.x) })
        try result.validate(); return result
    }
    func positioned(at anchor: WorldCoordinate) throws -> (CircuitWorld, Set<WorldCoordinate>) {
        try validate()
        var cells: [WorldCoordinate: CircuitComponent] = [:], levers: Set<WorldCoordinate> = []
        for (point, component) in circuit.components {
            let (x, ox) = anchor.x.addingReportingOverflow(point.x), (y, oy) = anchor.y.addingReportingOverflow(point.y)
            guard !ox, !oy else { throw BlueprintError("That position is outside the supported map.") }
            let target = WorldCoordinate(x: x, y: y); cells[target] = component
            if activeLevers.contains(point) { levers.insert(target) }
        }
        return (CircuitWorld(components: cells), levers)
    }
}

struct BlueprintError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }

/// All destinations are validated before publishing. Terrain and unselected components survive.
enum BlueprintPlacement {
    static func applying(_ blueprint: CircuitBlueprint, at anchor: WorldCoordinate, to world: World,
                         removing: Set<WorldCoordinate> = []) throws -> World {
        let (circuit, _) = try blueprint.positioned(at: anchor)
        var result = world
        for coordinate in removing { result.circuit.components.removeValue(forKey: coordinate) }
        for (coordinate, component) in circuit.components.sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            let placement = CircuitPlacement().place(component, at: coordinate, in: &result)
            guard placement.isAllowed else { throw BlueprintError("At (\(coordinate.x), \(coordinate.y)): \(placement.message)") }
        }
        return result
    }
}

extension Direction {
    var clockwise: Self {
        switch self { case .north: .east; case .east: .south; case .south: .west; case .west: .north }
    }
}
