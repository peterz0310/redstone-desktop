/// Jittered planting sites can share foliage across cells and chunk boundaries.
/// The required cross, optional corners and occasional extra leaf remain coherent.
enum TreeCanopy {
    static func plantingCenter(cellX: Int, cellY: Int, seed: UInt64) -> WorldCoordinate? {
        let roll = SeededNoise.hash(seed: seed, x: cellX, y: cellY, channel: 0x7EEE)
        let x = cellX.multipliedReportingOverflow(by: 6), y = cellY.multipliedReportingOverflow(by: 6)
        guard !x.overflow, !y.overflow else { return nil }
        let cx = x.partialValue.addingReportingOverflow(Int(roll % 6))
        let cy = y.partialValue.addingReportingOverflow(Int((roll >> 16) % 6))
        guard !cx.overflow, !cy.overflow else { return nil }
        return WorldCoordinate(x: cx.partialValue, y: cy.partialValue)
    }

    static func contains(_ tile: WorldCoordinate, center: WorldCoordinate, seed: UInt64) -> Bool {
        let x = tile.x.subtractingReportingOverflow(center.x), y = tile.y.subtractingReportingOverflow(center.y)
        guard !x.overflow, !y.overflow, (-2...2).contains(x.partialValue), (-2...2).contains(y.partialValue) else { return false }
        let dx = x.partialValue, dy = y.partialValue
        if abs(dx) + abs(dy) <= 1 { return true }
        if abs(dx) == 1 && abs(dy) == 1 {
            let corner = (dx < 0 ? 0 : 1) + (dy < 0 ? 0 : 2)
            return SeededNoise.hash(seed: seed, x: center.x, y: center.y, channel: 0xC0A0) & (UInt64(1) << corner) != 0
        }
        let roll = SeededNoise.hash(seed: seed, x: center.x, y: center.y, channel: 0xE87A)
        let offsets = [(-2, 0), (2, 0), (0, -2), (0, 2)]
        let offset = offsets[Int((roll >> 8) & 3)]
        return roll % 100 < 25 && dx == offset.0 && dy == offset.1
    }

    /// Check adjacent cells because jittered canopies can cross their planting cell.
    /// Actual trunks win over overlapping leaves; other overlaps use stable cell order.
    static func centers(near tile: WorldCoordinate, seed: UInt64) -> [WorldCoordinate] {
        let x = SeededNoise.floorDivision(tile.x, by: 6)
        let y = SeededNoise.floorDivision(tile.y, by: 6)
        var centers: [WorldCoordinate] = []
        for dy in -1...1 { for dx in -1...1 {
            // Only edge tiles can reach foliage from an adjacent planting cell.
            if (dx == -1 && x.remainder > 1) || (dx == 1 && x.remainder < 4)
                || (dy == -1 && y.remainder > 1) || (dy == 1 && y.remainder < 4) { continue }
            guard let center = plantingCenter(cellX: x.quotient + dx, cellY: y.quotient + dy, seed: seed),
                  contains(tile, center: center, seed: seed) else { continue }
            if center == tile { centers.insert(center, at: 0) } else { centers.append(center) }
        } }
        return centers
    }
}
