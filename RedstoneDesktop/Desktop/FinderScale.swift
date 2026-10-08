import Foundation

/// An optional presentation transform; saved cameras and circuit coordinates never change.
struct FinderScale: Equatable, Codable, Sendable {
    var enabled = false
    var baselineIconSize: Int?

    func camera(saved: CameraState, current: FinderViewSettings?, frame: CGRect) -> CameraState? {
        guard enabled else { return saved }
        guard let baselineIconSize, baselineIconSize > 0, let current,
              let mapper = try? CoordinateMapper(canvasFrame: frame, camera: saved) else { return nil }
        let scale = min(128, max(16, saved.pointsPerTile * Double(current.iconSize) / Double(baselineIconSize)))
        return mapper.camera(zoomedTo: scale, aroundScreen: CGPoint(x: frame.midX, y: frame.midY))
    }
}
