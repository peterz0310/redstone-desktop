/// A varied canopy fits inside its six-tile planting cell. The cross is always
/// present, corners are optional, and one arm occasionally extends a block.
/// Global cells keep trees coherent across chunk boundaries without neighbor loads.
enum TreeCanopy {
    static func center(near tile: WorldCoordinate, seed: UInt64) -> WorldCoordinate? {
        let x = SeededNoise.floorDivision(tile.x, by: 6), y = SeededNoise.floorDivision(tile.y, by: 6)
        let roll = SeededNoise.hash(seed: seed, x: x.quotient, y: y.quotient, channel: 0x7EEE)
        let dx = 2 + Int(roll & 1) - x.remainder
        let dy = 2 + Int((roll >> 1) & 1) - y.remainder
        let core = abs(dx) <= 1 && abs(dy) <= 1
        let arm = abs(dx) + abs(dy) == 2 && (dx == 0 || dy == 0)
        guard core || arm else { return nil }
        let cx = tile.x.addingReportingOverflow(dx), cy = tile.y.addingReportingOverflow(dy)
        guard !cx.overflow, !cy.overflow else { return nil }
        let center = WorldCoordinate(x: cx.partialValue, y: cy.partialValue)
        if arm {
            let extensionRoll = SeededNoise.hash(seed: seed, x: center.x, y: center.y, channel: 0xE87A)
            // One extra leaf on a quarter of trees; direction is independent of corners.
            guard extensionRoll % 100 < 25 else { return nil }
            let direction = Int((extensionRoll >> 8) & 3)
            let offsets = [(-2, 0), (2, 0), (0, -2), (0, 2)]
            guard dx == offsets[direction].0, dy == offsets[direction].1 else { return nil }
        } else if abs(dx) + abs(dy) == 2 {
            let corner = (dx < 0 ? 0 : 1) + (dy < 0 ? 0 : 2)
            let mask = SeededNoise.hash(seed: seed, x: center.x, y: center.y, channel: 0xC0A0)
            guard mask & (UInt64(1) << corner) != 0 else { return nil }
        }
        return center
    }
}
