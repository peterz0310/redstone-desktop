import AVFoundation
import CryptoKit

/// Local data only. Native decoding runs in the import worker, never on a simulation tick.
enum JavaAudioImporter {
    static let mappings: [(SoundID, [String])] = [
        (.buttonPress, ["random/click", "random/wood_click"]),
        (.buttonRelease, ["random/click", "random/wood_click"]),
        (.leverToggleOn, ["random/click"]), (.leverToggleOff, ["random/click"]),
        (.repeaterTick, ["random/wood_click", "random/click"]),
        (.torchToggle, ["fire/ignite"]),
        (.placeCircuit, ["dig/stone1"]), (.removeCircuit, ["dig/stone2", "dig/stone1"]),
        (.invalidPlacement, ["note/bass"]), (.outputActivate, ["note/pling"])
    ]
    struct Index: Decodable {
        struct Object: Decodable { let hash: String; let size: Int }
        let objects: [String: Object]
    }
    struct Version: Decodable {
        struct AssetIndex: Decodable { let id: String }
        let assetIndex: AssetIndex?
        let assets: String?
    }
    /// Only the chosen version's declared asset index is used; no cache guessing or downloads.
    static func installedAssets(for jar: URL) throws -> (PackSource, Index)? {
        guard jar.pathExtension.lowercased() == "jar", jar.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "versions" else { return nil }
        let root = jar.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try PackSource(url: root)
        let versionPath = "versions/\(jar.deletingLastPathComponent().lastPathComponent)/\(jar.deletingPathExtension().lastPathComponent).json"
        let version = try JSONDecoder().decode(Version.self, from: source.read(versionPath, limit: 2 * 1024 * 1024))
        guard let id = version.assetIndex?.id ?? version.assets, id.utf8.count <= 128,
              !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }), id != ".", id != ".." else { throw PackError("Invalid Minecraft audio asset index.") }
        let index = try JSONDecoder().decode(Index.self, from: source.read("assets/indexes/\(id).json", limit: 16 * 1024 * 1024))
        guard index.objects.count <= 250_000 else { throw PackError("Minecraft audio index is too large.") }
        return (source, index)
    }
    static func readObject(_ name: String, assets: (PackSource, Index)) throws -> Data {
        guard let object = assets.1.objects["minecraft/sounds/\(name).ogg"],
              object.hash.count == 40, object.hash.allSatisfy({ "0123456789abcdef".contains($0) }),
              (1...2 * 1024 * 1024).contains(object.size) else { throw PackError("Sound is absent or invalid in the Minecraft asset index.") }
        let data = try assets.0.read("assets/objects/\(object.hash.prefix(2))/\(object.hash)", limit: 2 * 1024 * 1024)
        let hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == object.size, hash == object.hash else { throw PackError("Minecraft sound object content does not match its index.") }
        return data
    }
    static func decode(_ data: Data) throws -> [Float] {
        guard data.count >= 64, data.count <= 2 * 1024 * 1024, data.prefix(4) == Data("OggS".utf8) else { throw PackError("Expected a bounded Ogg sound.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RedstoneAudio-\(UUID()).ogg")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat, channels = Int(format.channelCount), rate = format.sampleRate
        guard (1...2).contains(channels), rate.isFinite, (8000...96000).contains(rate), file.length > 0, file.length <= Int64(rate * 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { throw PackError("Java sound must be mono/stereo, 8–96 kHz, and at most two seconds.") }
        try file.read(into: buffer)
        guard buffer.frameLength > 0, let samples = buffer.floatChannelData else { throw PackError("Java sound has no decoded audio.") }
        let count = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channels { for i in 0..<count {
            let sample = samples[channel][i]
            guard sample.isFinite else { throw PackError("Nonfinite Java audio sample.") }
            mono[i] += min(1, max(-1, sample)) / Float(channels)
        } }
        let peak = mono.map { abs($0) }.max() ?? 0, gain: Float = peak > 0.11 ? 0.11 / peak : 1
        let length = min(88200, max(1, Int(Double(count) * BuiltInSounds.sampleRate / rate)))
        return (0..<length).map { i in
            let position = Double(i) * rate / BuiltInSounds.sampleRate
            let a = min(count - 1, Int(position)), b = min(count - 1, a + 1)
            return min(0.11, max(-0.11, (mono[a] + (mono[b] - mono[a]) * Float(position - Double(a))) * gain))
        }
    }
    /// Store portable PCM rather than making playback depend on an Ogg codec.
    static func wav(_ samples: [Float]) throws -> Data {
        guard !samples.isEmpty, samples.count <= 88200, samples.allSatisfy({ $0.isFinite && abs($0) <= 0.11 }) else { throw PackError("Invalid normalized sound.") }
        var bytes = Data()
        func number(_ value: Int, _ count: Int) { for i in 0..<count { bytes.append(UInt8((value >> (8 * i)) & 255)) } }
        bytes.append(Data("RIFF".utf8)); number(36 + samples.count * 4, 4); bytes.append(Data("WAVEfmt ".utf8))
        number(16, 4); number(3, 2); number(1, 2); number(44100, 4); number(44100 * 4, 4); number(4, 2); number(32, 2)
        bytes.append(Data("data".utf8)); number(samples.count * 4, 4)
        for sample in samples { number(Int(sample.bitPattern), 4) }
        return bytes
    }
}
