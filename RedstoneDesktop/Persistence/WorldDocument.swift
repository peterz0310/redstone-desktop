import Foundation

/// Durable configuration only: no Finder paths, power snapshots, or pending actions.
struct WorldDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    var formatVersion = currentFormatVersion
    var fixtureVersion = 1
    var id = UUID()
    var name = "My Desktop"
    var camera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    var circuit = EditorConstructionArea.makeWorld().circuit
    var activeLevers: Set<WorldCoordinate> = []

    func restoredWorld() throws -> World {
        guard formatVersion == Self.currentFormatVersion else { throw WorldStoreError.unsupportedVersion(formatVersion) }
        guard fixtureVersion == 1 else { throw WorldStoreError.invalidDocument("Unsupported terrain fixture version.") }
        guard camera.worldOrigin.x.isFinite, camera.worldOrigin.y.isFinite,
              camera.pointsPerTile.isFinite, (16...128).contains(camera.pointsPerTile),
              camera.worldOrigin.x > Double(Int.min), camera.worldOrigin.x < Double(Int.max),
              camera.worldOrigin.y > Double(Int.min), camera.worldOrigin.y < Double(Int.max) else {
            throw WorldStoreError.invalidDocument("Invalid desktop camera.")
        }
        var world = EditorConstructionArea.makeWorld()
        world.circuit = CircuitWorld()
        for (coordinate, component) in circuit.components {
            guard PlacementRules().canPlace(component: component, at: coordinate, in: world).isAllowed else {
                throw WorldStoreError.invalidDocument("Circuit component is on an invalid tile.")
            }
            world.circuit.components[coordinate] = component
        }
        guard activeLevers.allSatisfy({ circuit.components[$0]?.kind == .lever }) else {
            throw WorldStoreError.invalidDocument("Saved lever position is not a lever.")
        }
        return world
    }
}
