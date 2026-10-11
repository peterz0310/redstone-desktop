import Foundation

/// Original procedural artwork, independent of Minecraft and resource packs.
enum OriginalLiquidAnimation {
    static func make(_ terrain: TerrainID) -> AnimatedRaster {
        var pixels: [UInt8] = []
        for frame in 0..<8 { for y in 0..<16 { for x in 0..<16 {
            let wave = sin(Double(x + frame * 2) * .pi / 8) * cos(Double(y - frame) * .pi / 8)
            let ripple = sin(Double(x + y - frame * 2) * .pi / 4)
            let base: (Double, Double, Double) = terrain == .lava ? (225, 91, 16)
                : terrain == .deepWater ? (34, 85, 143) : (45, 108, 166)
            let light = terrain == .lava ? wave * 24 + ripple * 12 : wave * 8 + ripple * 4
            pixels += [UInt8(max(0, min(255, base.0 + light))), UInt8(max(0, min(255, base.1 + light))), UInt8(max(0, min(255, base.2 + light))), 255]
        } } }
        return try! AnimatedRaster(strip: RasterAsset(width: 16, height: 128, pixels: pixels),
            spec: TextureAnimationSpec(frames: Array(0..<8), durations: Array(repeating: 0.15, count: 8), interpolate: true))
    }
}
