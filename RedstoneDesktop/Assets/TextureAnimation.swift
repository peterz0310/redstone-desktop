import Foundation
import CoreFoundation

/// Bounded data only. No expressions, shaders, scripts or resource-pack code.
struct TextureAnimationSpec: Codable, Equatable, Sendable {
    var frames: [Int]
    var durations: [Double]
    var interpolate = false

    func validate(frameCount: Int) throws {
        guard (1...64).contains(frameCount), (1...256).contains(frames.count), frames.count == durations.count,
              frames.allSatisfy({ (0..<frameCount).contains($0) }),
              durations.allSatisfy({ $0.isFinite && (0.05...10).contains($0) }) else {
            throw PackError("Animation requires 1–64 square frames, up to 256 steps, valid indices and 0.05–10 second durations.")
        }
    }

    func phase(at time: Double) -> (frame: Int, next: Int, blend: Float) {
        let total = durations.reduce(0, +)
        guard time.isFinite, time >= 0, total > 0, !frames.isEmpty else { return (frames.first ?? 0, frames.first ?? 0, 0) }
        var remaining = time.truncatingRemainder(dividingBy: total)
        for index in frames.indices {
            if remaining < durations[index] {
                return (frames[index], frames[(index + 1) % frames.count], interpolate ? Float(remaining / durations[index]) : 0)
            }
            remaining -= durations[index]
        }
        return (frames[0], frames[0], 0)
    }

    static func java(metadata: Data?, frameCount: Int) throws -> Self {
        guard (1...64).contains(frameCount) else { throw PackError("Animation requires 1–64 frames.") }
        var result = Self(frames: Array(0..<frameCount), durations: [Double](repeating: 0.05, count: frameCount))
        if let metadata {
            guard metadata.count <= 64 * 1024,
                  let root = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
                  let animation = root["animation"] as? [String: Any] else { throw PackError("Invalid Java animation metadata.") }
            func ticks(_ value: Any?) throws -> Double {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.rounded() == number.doubleValue, (1...200).contains(number.doubleValue) else {
                    throw PackError("Java frame times must be integer ticks from 1–200.")
                }
                return number.doubleValue * 0.05
            }
            let duration = try ticks(animation["frametime"] ?? 1)
            result.durations = [Double](repeating: duration, count: frameCount)
            result.interpolate = animation["interpolate"] as? Bool ?? false
            if let entries = animation["frames"] {
                guard let entries = entries as? [Any], (1...256).contains(entries.count) else { throw PackError("Invalid Java frame sequence.") }
                result.frames = []; result.durations = []
                for entry in entries {
                    let object = entry as? [String: Any]
                    let value = object?["index"] ?? entry
                    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                          number.doubleValue.rounded() == number.doubleValue, (0..<Double(frameCount)).contains(number.doubleValue) else { throw PackError("Invalid Java frame index.") }
                    result.frames.append(number.intValue)
                    result.durations.append(try object?["time"].map { try ticks($0) } ?? duration)
                }
            }
        }
        try result.validate(frameCount: frameCount)
        return result
    }
}

struct AnimatedRaster: Sendable {
    let strip: RasterAsset
    let spec: TextureAnimationSpec
    var frameCount: Int { strip.height / strip.width }
    init(strip: RasterAsset, spec: TextureAnimationSpec) throws {
        guard (1...1024).contains(strip.width), (1...1024).contains(strip.height),
              strip.height % strip.width == 0, strip.pixels.count == strip.width * strip.height * 4 else { throw PackError("Animation requires a vertical square-frame PNG strip.") }
        try spec.validate(frameCount: strip.height / strip.width)
        self.strip = strip; self.spec = spec
    }
    func frame(_ index: Int) -> RasterAsset {
        let size = strip.width * strip.width * 4, start = index * size
        return RasterAsset(width: strip.width, height: strip.width, pixels: Array(strip.pixels[start..<start + size]))
    }
}
