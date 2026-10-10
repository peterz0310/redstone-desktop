/// Rare, small, jagged pools. No neighboring terrain queries or coordinate overflow.
enum LavaPool {
    static func contains(_ tile: WorldCoordinate, seed: UInt64) -> Bool {
        let x = SeededNoise.floorDivision(tile.x, by: 64), y = SeededNoise.floorDivision(tile.y, by: 64)
        let roll = SeededNoise.hash(seed: seed, x: x.quotient, y: y.quotient, channel: 0x1A7A)
        guard roll % 6 == 0 else { return false }
        let cx = 12 + Int((roll >> 8) % 40), cy = 12 + Int((roll >> 16) % 40)
        let dx = x.remainder - cx, dy = y.remainder - cy
        let radius = 2 + Int((roll >> 24) % 3)
        guard abs(dx) <= radius, abs(dy) <= radius else { return false }
        let edge = Int(SeededNoise.hash(seed: seed, x: tile.x, y: tile.y, channel: 0x1A7B) % 3) - 1
        return dx * dx + dy * dy <= radius * radius + edge
    }
}
