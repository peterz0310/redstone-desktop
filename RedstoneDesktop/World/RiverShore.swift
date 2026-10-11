/// A bounded tile-distance shoreline, independent of noise slope or chunk boundaries.
enum RiverShore {
    static func isShallow(at coordinate: WorldCoordinate, width: Int, isWater: (WorldCoordinate) -> Bool) -> Bool {
        precondition(width == 1 || width == 2)
        for dy in -width...width { for dx in -width...width {
            guard dx != 0 || dy != 0 else { continue }
            let (x, ox) = coordinate.x.addingReportingOverflow(dx)
            let (y, oy) = coordinate.y.addingReportingOverflow(dy)
            guard !ox, !oy else { continue }
            if !isWater(WorldCoordinate(x: x, y: y)) { return true }
        } }
        return false
    }
}
