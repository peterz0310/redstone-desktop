/// Version 1 integer hash/value noise. No Swift Hasher, random state, or floating point.
enum SeededNoise {
    static func hash(seed: UInt64, x: Int, y: Int, channel: UInt64) -> UInt64 {
        var value = mix(seed ^ channel)
        value = mix(value ^ (UInt64(truncatingIfNeeded: x) &* 0x9E3779B185EBCA87))
        return mix(value ^ (UInt64(truncatingIfNeeded: y) &* 0xC2B2AE3D27D4EB4F))
    }

    private static func mix(_ input: UInt64) -> UInt64 {
        var value = input
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    /// Floor division without negating Int.min or multiplying a negative origin.
    static func floorDivision(_ value: Int, by divisor: Int) -> (quotient: Int, remainder: Int) {
        precondition(divisor > 0)
        let quotient = value / divisor, remainder = value % divisor
        return remainder < 0 ? (quotient - 1, remainder + divisor) : (quotient, remainder)
    }

    /// Smooth global lattice interpolation in Q16 units (0...65535).
    /// Scale is at least 2, so lattice + 1 is representable even at Int limits.
    static func value(seed: UInt64, at coordinate: WorldCoordinate, scale: Int, channel: UInt64) -> Int {
        precondition(scale >= 2 && scale <= 4096)
        let x = floorDivision(coordinate.x, by: scale), y = floorDivision(coordinate.y, by: scale)
        func corner(_ x: Int, _ y: Int) -> Int64 { Int64(hash(seed: seed, x: x, y: y, channel: channel) & 0xFFFF) }
        func smooth(_ remainder: Int) -> Int64 {
            let t = Int64(remainder) * 65536 / Int64(scale)
            return t * t * (3 * 65536 - 2 * t) / (65536 * 65536)
        }
        func interpolate(_ a: Int64, _ b: Int64, _ t: Int64) -> Int64 { a + (b - a) * t / 65536 }
        let tx = smooth(x.remainder), ty = smooth(y.remainder)
        let lower = interpolate(corner(x.quotient, y.quotient), corner(x.quotient + 1, y.quotient), tx)
        let upper = interpolate(corner(x.quotient, y.quotient + 1), corner(x.quotient + 1, y.quotient + 1), tx)
        return Int(interpolate(lower, upper, ty))
    }
}
