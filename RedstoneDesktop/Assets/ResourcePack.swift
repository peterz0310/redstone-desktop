import Foundation
import ImageIO
import CoreGraphics

struct RasterAsset: Sendable {
    let width: Int
    let height: Int
    /// Premultiplied RGBA, rows top to bottom.
    var pixels: [UInt8]

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "public.png", CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              (1...1024).contains(width), (1...1024).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PackError("Expected a valid single-frame PNG, dimensions 1–1024.") }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw PackError("PNG raster decode failed.") }
        return Self(width: width, height: height, pixels: pixels)
    }
    /// Source pixels are premultiplied; an opaque backing prevents the world grid showing through water.
    func backedByOpaqueColor(_ color: (UInt8, UInt8, UInt8, UInt8)) -> Self {
        var result = self
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let inverse = 255 - Int(pixels[index + 3])
            result.pixels[index] = UInt8(min(255, Int(pixels[index]) + Int(color.0) * inverse / 255))
            result.pixels[index + 1] = UInt8(min(255, Int(pixels[index + 1]) + Int(color.1) * inverse / 255))
            result.pixels[index + 2] = UInt8(min(255, Int(pixels[index + 2]) + Int(color.2) * inverse / 255))
            result.pixels[index + 3] = 255
        }
        return result
    }
    var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    func sample(x: Int, y: Int, resolution: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let column = min(width - 1, x * width / resolution)
        let row = height - 1 - min(height - 1, y * height / resolution)
        let i = (row * width + column) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }
    func pngData() throws -> Data {
        let data = NSMutableData()
        guard let image = cgImage, let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw PackError("Could not encode PNG.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PackError("PNG encoding failed.") }
        return data as Data
    }
}

struct LoadedPack: Sendable {
    let manifest: PackManifest
    let textures: [TextureAssetID: RasterAsset]
    let sounds: [SoundID: [Float]]
    let warnings: [String]
}

/// Deliberately restricted WAV decoder: little-endian PCM16 or float32, mono/stereo, <=2 s.
enum PackWAV {
    static func decode(_ data: Data) throws -> [Float] {
        func number(_ offset: Int, _ bytes: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - bytes else { throw PackError("Truncated WAV.") }
            return (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        guard data.count >= 44, data.count <= 8 * 1024 * 1024,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE",
              try number(4, 4) + 8 == data.count else { throw PackError("Invalid RIFF/WAV.") }
        var offset = 12, format: (Int, Int, Int, Int, Int)?, audio: Range<Int>?
        while offset < data.count {
            let size = try number(offset + 4, 4), start = offset + 8
            guard start + size <= data.count else { throw PackError("Truncated WAV chunk.") }
            let tag = String(data: data[offset..<(offset + 4)], encoding: .ascii)
            if tag == "fmt " {
                guard format == nil, size >= 16 else { throw PackError("Invalid WAV format chunk.") }
                format = (try number(start, 2), try number(start + 2, 2), try number(start + 4, 4), try number(start + 12, 2), try number(start + 14, 2))
            }
            if tag == "data" { guard audio == nil else { throw PackError("Repeated WAV data.") }; audio = start..<(start + size) }
            offset = start + size + size % 2
        }
        guard let (code, channels, rate, align, bits) = format, let audio,
              channels == 1 || channels == 2, (8000...96000).contains(rate),
              (code == 1 && bits == 16) || (code == 3 && bits == 32), align == channels * bits / 8,
              !audio.isEmpty, audio.count % align == 0, audio.count / align <= rate * 2 else { throw PackError("WAV must be mono/stereo PCM16 or float32, 8–96 kHz, <=2 seconds.") }
        let count = audio.count / align
        var mono: [Float] = []
        for frame in 0..<count {
            var sum: Float = 0
            for channel in 0..<channels {
                let value = try number(audio.lowerBound + frame * align + channel * bits / 8, bits / 8)
                let sample = code == 1 ? Float(Int16(bitPattern: UInt16(value))) / 32768 : Float(bitPattern: UInt32(value))
                guard sample.isFinite else { throw PackError("Nonfinite WAV samples.") }
                sum += min(1, max(-1, sample)) / Float(channels)
            }
            mono.append(sum)
        }
        let peak = mono.map { abs($0) }.max() ?? 0
        let gain: Float = peak > 0.11 ? 0.11 / peak : 1
        let outputCount = max(1, Int(Double(count) * BuiltInSounds.sampleRate / Double(rate)))
        return (0..<outputCount).map { frame in
            let source = Double(frame) * Double(rate) / BuiltInSounds.sampleRate
            let a = min(count - 1, Int(source)), b = min(count - 1, a + 1)
            return (mono[a] + (mono[b] - mono[a]) * Float(source - Double(a))) * gain
        }
    }
}

struct PackSource: Sendable {
    let root: URL?
    let archive: SafeZIP?
    let prefix: String

    init(url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            root = url.resolvingSymlinksInPath().standardizedFileURL; archive = nil; prefix = ""
        } else {
            let zip = try SafeZIP(url: url)
            let manifests = zip.entries.keys.filter { $0 == "pack.json" || $0.hasSuffix("/pack.json") }
            guard manifests.count == 1, let manifest = manifests.first, manifest.split(separator: "/").count <= 2 else { throw PackError("ZIP needs exactly one pack.json, at root or within one wrapper folder.") }
            root = nil; archive = zip; prefix = String(manifest.dropLast("pack.json".count))
        }
    }
    func read(_ path: String, limit: Int) throws -> Data {
        try PackFiles.validatePath(path)
        if let archive { return try archive.read(prefix + path, limit: limit) }
        guard let root else { throw PackError("No pack source.") }
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), file.resolvingSymlinksInPath().path == file.path else { throw PackError("Pack asset escapes root or uses a symlink.") }
        return try PackFiles.read(file, limit: limit)
    }
}

enum ResourcePackLoader {
    static func load(_ url: URL) throws -> LoadedPack {
        let source = try PackSource(url: url)
        let data = try source.read("pack.json", limit: 64 * 1024)
        let manifest: PackManifest
        do { manifest = try JSONDecoder().decode(PackManifest.self, from: data) }
        catch { throw PackError("pack.json does not match format 1: \(error.localizedDescription)") }
        guard manifest.formatVersion == 1, !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 128, (manifest.author?.count ?? 0) <= 256, manifest.assets.count <= 64 else { throw PackError("Unsupported format, missing/long name, or too many assets.") }
        var textures: [TextureAssetID: RasterAsset] = [:], sounds: [SoundID: [Float]] = [:], warnings: [String] = []
        for (id, path) in manifest.assets.sorted(by: { $0.key < $1.key }) {
            try PackFiles.validatePath(path) // Even ignored/unknown IDs may not declare escaping paths.
            do {
                if let texture = TextureAssetID(rawValue: id) {
                    guard URL(fileURLWithPath: path).pathExtension.lowercased() == "png" else { throw PackError("Textures require PNG.") }
                    textures[texture] = try RasterAsset.decode(source.read(path, limit: 4 * 1024 * 1024))
                } else if let sound = SoundID(rawValue: id) {
                    guard URL(fileURLWithPath: path).pathExtension.lowercased() == "wav" else { throw PackError("Sounds require WAV.") }
                    sounds[sound] = try PackWAV.decode(source.read(path, limit: 8 * 1024 * 1024))
                } else { warnings.append("Unknown asset ID \(id); ignored.") }
            } catch { warnings.append("\(id): \(error.localizedDescription) Built-in fallback.") }
        }
        return LoadedPack(manifest: manifest, textures: textures, sounds: sounds, warnings: warnings)
    }
}
