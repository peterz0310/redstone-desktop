import Foundation

/// Fixed, bounded 2D recipes over validated pixels, never a Java model/code interpreter.
enum JavaCircuitArt: Sendable {
    case button(Bool), lever(Bool), repeater(Bool), dust(Bool), cactus, output(Bool)

    func render(_ source: RasterAsset) -> RasterAsset {
        if case let .dust(on) = self {
            var result = source
            let color = on ? [255, 24, 32] : [106, 12, 18]
            for i in stride(from: 0, to: result.pixels.count, by: 4) {
                let alpha = Int(source.pixels[i + 3])
                let light = alpha == 0 ? 0 : min(255, Int(source.pixels[i]) * 255 / alpha)
                // Keep a continuous opaque material: transparent source-dot corners must not cut wires.
                let strength = 184 + light * 71 / 255
                for c in 0..<3 { result.pixels[i + c] = UInt8(color[c] * strength / 255) }
                result.pixels[i + 3] = 255
            }
            return result
        }
        var result = RasterAsset(width: 16, height: 16, pixels: [UInt8](repeating: 0, count: 16 * 16 * 4))
        func sample(_ x: Int, _ y: Int) -> [UInt8] {
            let i = ((min(15, max(0, y)) * source.height / 16) * source.width + min(15, max(0, x)) * source.width / 16) * 4
            return Array(source.pixels[i..<i + 4])
        }
        func put(_ x: Int, _ y: Int, _ color: [UInt8]) {
            guard (0..<16).contains(x), (0..<16).contains(y) else { return }
            let i = (y * 16 + x) * 4
            result.pixels.replaceSubrange(i..<i + 4, with: color)
        }
        switch self {
        case let .button(down):
            for y in 5..<12 {
                for x in 3..<13 {
                    let face = sample(x, y)
                    let shade = y >= (down ? 10 : 9) ? 130 : (down ? 205 : 255)
                    put(x, y + (down ? 1 : 0), [UInt8(Int(face[0]) * shade / 255), UInt8(Int(face[1]) * shade / 255), UInt8(Int(face[2]) * shade / 255), face[3]])
                }
            }
        case let .lever(on):
            for y in 10..<15 { for x in 3..<13 { put(x, y, [115, 119, 123, 255]) } }
            // Known vanilla handle UV region [7,6]–[9,16]; slope distinguishes durable states.
            for step in 0..<9 {
                let x = 8 + (on ? 1 : -1) * step / 3
                for width in 0..<2 { put(x + width - 1, 11 - step, sample(7 + width, 15 - step)) }
            }
        case let .repeater(on):
            // Java's top texture faces north; semantic repeater icons face east before scene rotation.
            for y in 0..<16 { for x in 0..<16 { put(x, y, sample(y, 15 - x)) } }
            let pin: [UInt8] = on ? [255, 24, 32, 255] : [100, 18, 22, 255]
            for x in [4, 11] { for y in 7..<9 { put(x, y, pin); put(x + 1, y, pin) } }
        case .cactus:
            for y in 3..<13 { for x in 3..<13 { put(x, y, sample((x - 3) * 16 / 10, (y - 3) * 16 / 10)) } }
        case let .output(on):
            for y in 0..<16 { for x in 0..<16 { put(x, y, sample(x, y)) } }
            if on { for y in 12..<15 { for x in 12..<15 { put(x, y, [255, 24, 32, 255]) } } }
        case .dust: break
        }
        return result
    }
}
