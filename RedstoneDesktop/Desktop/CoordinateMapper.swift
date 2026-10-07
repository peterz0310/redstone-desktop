import Foundation

/// The only service for world, global-screen, and renderer-local conversions.
/// Screen/world Y both increase upward; Finder calibration belongs here later.
struct CoordinateMapper: Sendable {
    enum ValidationError: Error {
        case invalidCanvas
        case invalidCamera
    }

    let canvasFrame: CGRect
    let camera: CameraState

    init(canvasFrame: CGRect, camera: CameraState) throws {
        guard canvasFrame.origin.x.isFinite, canvasFrame.origin.y.isFinite,
              canvasFrame.width.isFinite, canvasFrame.height.isFinite,
              canvasFrame.width > 0, canvasFrame.height > 0,
              canvasFrame.maxX.isFinite, canvasFrame.maxY.isFinite else {
            throw ValidationError.invalidCanvas
        }
        guard camera.worldOrigin.x.isFinite, camera.worldOrigin.y.isFinite,
              camera.pointsPerTile.isFinite, camera.pointsPerTile > 0 else {
            throw ValidationError.invalidCamera
        }
        self.canvasFrame = canvasFrame
        self.camera = camera
    }

    func worldPoint(fromScreen point: CGPoint) -> WorldPoint {
        WorldPoint(
            x: camera.worldOrigin.x + Double(point.x - canvasFrame.minX) / camera.pointsPerTile,
            y: camera.worldOrigin.y + Double(point.y - canvasFrame.minY) / camera.pointsPerTile
        )
    }

    func screenPoint(fromWorld point: WorldPoint) -> CGPoint {
        CGPoint(
            x: Double(canvasFrame.minX) + (point.x - camera.worldOrigin.x) * camera.pointsPerTile,
            y: Double(canvasFrame.minY) + (point.y - camera.worldOrigin.y) * camera.pointsPerTile
        )
    }

    /// Floor, rather than truncate, so -0.1 belongs to tile -1.
    /// Invalid/unrepresentable input returns nil instead of trapping an Int conversion.
    func tile(containing point: WorldPoint) -> WorldCoordinate? {
        guard let x = Int(exactly: floor(point.x)), let y = Int(exactly: floor(point.y)) else {
            return nil
        }
        return WorldCoordinate(x: x, y: y)
    }

    func tile(atScreen point: CGPoint) -> WorldCoordinate? {
        tile(containing: worldPoint(fromScreen: point))
    }

    func screenRect(forTile coordinate: WorldCoordinate) -> CGRect {
        CGRect(
            origin: screenPoint(fromWorld: WorldPoint(x: Double(coordinate.x), y: Double(coordinate.y))),
            size: CGSize(width: camera.pointsPerTile, height: camera.pointsPerTile)
        )
    }

    func scenePoint(fromScreen point: CGPoint, on screen: ScreenDescriptor) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
    }

    func sceneRect(forTile coordinate: WorldCoordinate, on screen: ScreenDescriptor) -> CGRect {
        let rect = screenRect(forTile: coordinate)
        return CGRect(origin: scenePoint(fromScreen: rect.origin, on: screen), size: rect.size)
    }
}
