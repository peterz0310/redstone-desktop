import Foundation

enum AudioPanning {
    static func pan(screenPoint: CGPoint, canvas: CGRect) -> Float? {
        guard screenPoint.x.isFinite, screenPoint.y.isFinite,
              canvas.minX.isFinite, canvas.maxX.isFinite, canvas.width.isFinite, canvas.width > 0 else { return nil }
        let position = (screenPoint.x - canvas.minX) / canvas.width
        guard position.isFinite else { return nil }
        return Float(min(1, max(-1, 2 * position - 1)))
    }

    /// A spatial event outside the current canvas is discarded, never queued for later.
    static func pan(tile: WorldCoordinate, mapper: CoordinateMapper) -> Float? {
        let rect = mapper.screenRect(forTile: tile)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard mapper.canvasFrame.contains(center) else { return nil }
        return pan(screenPoint: center, canvas: mapper.canvasFrame)
    }
}
