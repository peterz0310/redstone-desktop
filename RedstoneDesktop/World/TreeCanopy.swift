/// A five-block canopy fits entirely inside its six-tile planting cell.
/// Global cells keep trees coherent across chunk boundaries without neighbor loads.
enum TreeCanopy {
    static func center(near tile: WorldCoordinate, seed: UInt64) -> WorldCoordinate? {
        let x = SeededNoise.floorDivision(tile.x, by: 6), y = SeededNoise.floorDivision(tile.y, by: 6)
        let roll = SeededNoise.hash(seed: seed, x: x.quotient, y: y.quotient, channel: 0x7EEE)
        let dx = 2 + Int(roll & 1) - x.remainder
        let dy = 2 + Int((roll >> 1) & 1) - y.remainder
        guard abs(dx) + abs(dy) <= 1 else { return nil }
        let cx = tile.x.addingReportingOverflow(dx), cy = tile.y.addingReportingOverflow(dy)
        guard !cx.overflow, !cy.overflow else { return nil }
        return WorldCoordinate(x: cx.partialValue, y: cy.partialValue)
    }
}
