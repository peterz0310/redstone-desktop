import Foundation

struct SavedArea: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    let worldID: UUID
    var camera: CameraState

    static let homeCamera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              camera.worldOrigin.x.isFinite, camera.worldOrigin.y.isFinite,
              camera.pointsPerTile.isFinite, (16...128).contains(camera.pointsPerTile),
              camera.worldOrigin.x > Double(Int.min), camera.worldOrigin.x < Double(Int.max),
              camera.worldOrigin.y > Double(Int.min), camera.worldOrigin.y < Double(Int.max) else {
            throw WorldStoreError.invalidDocument("Invalid saved area name or camera.")
        }
    }
}
