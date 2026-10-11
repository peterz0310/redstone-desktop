import CryptoKit
import XCTest
@testable import RedstoneDesktop

final class JavaAudioTests: XCTestCase {
    private var fixture: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SyntheticTone.ogg") }
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JavaAudioTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    private func png(_ root: URL) throws {
        let folder = root.appendingPathComponent("assets/minecraft/textures/block")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RasterAsset(width: 2, height: 2, pixels: [UInt8](repeating: 255, count: 16)).pngData().write(to: folder.appendingPathComponent("stone.png"))
    }
    func testNativeOggDecodeNormalizesResamplesAndCachedWavRoundTrips() throws {
        let data = try Data(contentsOf: fixture)
        let samples = try JavaAudioImporter.decode(data)
        XCTAssertGreaterThan(samples.count, 4000); XCTAssertLessThan(samples.count, 88201)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.11 })
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.01)
        XCTAssertEqual(try PackWAV.decode(JavaAudioImporter.wav(samples)), samples)
        XCTAssertThrowsError(try JavaAudioImporter.decode(Data("OggS".utf8)))
        XCTAssertThrowsError(try JavaAudioImporter.decode(Data(repeating: 255, count: 100)))
        XCTAssertThrowsError(try JavaAudioImporter.decode(Data(contentsOf: fixture.deletingLastPathComponent().appendingPathComponent("SyntheticLongTone.ogg"))))
        XCTAssertThrowsError(try JavaAudioImporter.wav([.infinity]))
        XCTAssertThrowsError(try JavaAudioImporter.wav([Float](repeating: 0, count: 88201)))
    }
    @MainActor func testImportedPcmPlaysThroughActualOfflineEngineAndMuteStillWorks() throws {
        let samples = try JavaAudioImporter.decode(Data(contentsOf: fixture))
        let engine = try AudioEngine(offline: true)
        defer { engine.stop() }
        engine.replaceSoundOverrides([.buttonPress: try PackWAV.decode(JavaAudioImporter.wav(samples))])
        engine.configure(AudioSettings(volume: 1))
        engine.play(.buttonPress)
        let rendered = try engine.renderOffline(frames: 2048)
        let values = Array(UnsafeBufferPointer(start: rendered.floatChannelData![0], count: Int(rendered.frameLength)))
        XCTAssertTrue(values.contains { abs($0) > 0.01 })
        XCTAssertTrue(values.allSatisfy { $0.isFinite && abs($0) <= 0.11 })
        engine.configure(AudioSettings(muted: true))
        engine.play(.buttonPress)
        let silent = try engine.renderOffline(frames: 2048)
        XCTAssertTrue(Array(UnsafeBufferPointer(start: silent.floatChannelData![0], count: Int(silent.frameLength))).allSatisfy { abs($0) < 0.0001 })
    }

    func testJavaPackImportsSupportedSoundsAsPcmAndNoSourceOggIntoCache() throws {
        let root = try temporary(), source = root.appendingPathComponent("pack"), cache = root.appendingPathComponent("cache")
        try png(source)
        let tone = try Data(contentsOf: fixture)
        for name in Set(JavaAudioImporter.mappings.flatMap { $0.1 }) {
            let url = source.appendingPathComponent("assets/minecraft/sounds/\(name).ogg")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try tone.write(to: url)
        }
        let imported = try JavaTextureImporter.importTextures(from: source, cacheRoot: cache)
        XCTAssertEqual(imported.pack.sounds.count, SoundID.allCases.count)
        XCTAssertEqual(imported.record.soundMappings?.count, SoundID.allCases.count)
        let reloaded = try ResourcePackLoader.load(imported.folder)
        XCTAssertEqual(reloaded.sounds, imported.pack.sounds)
        let names = try FileManager.default.contentsOfDirectory(atPath: imported.folder.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".ogg") }); XCTAssertEqual(names.filter { $0.hasSuffix(".wav") }.count, 10)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("assets/minecraft/sounds/random/click.ogg")), tone)
    }
    func testWrappedJavaZIPImportsParticlesAndAudioAndAudioOnlyFoldersWork() throws {
        let root = try temporary()
        let zip = fixture.deletingLastPathComponent().appendingPathComponent("SyntheticEffectsJava.zip")
        let before = try Data(contentsOf: zip)
        let imported = try JavaTextureImporter.importTextures(from: zip, cacheRoot: root.appendingPathComponent("cache"))
        XCTAssertEqual(imported.pack.sounds.count, 10)
        XCTAssertEqual(imported.pack.textures.count, 4)
        for id in [TextureAssetID.particleFlame, .particleSmoke, .particleLava, .particleDust] { XCTAssertNotNil(imported.pack.textures[id]) }
        XCTAssertEqual(try Data(contentsOf: zip), before)
        let folder = root.appendingPathComponent("only-audio/assets/minecraft/sounds/random")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(contentsOf: fixture).write(to: folder.appendingPathComponent("click.ogg"))
        let audioOnly = try JavaTextureImporter.importTextures(from: root.appendingPathComponent("only-audio"), cacheRoot: root.appendingPathComponent("cache2"))
        XCTAssertTrue(audioOnly.pack.textures.isEmpty); XCTAssertEqual(audioOnly.pack.sounds.count, 5)
    }

    func testChosenVersionIndexResolvesHashedAudioAndRejectsBadHashAndSize() throws {
        let root = try temporary(), installation = root.appendingPathComponent("minecraft")
        let source = installation.appendingPathComponent("versions/test"), jar = source.appendingPathComponent("test.jar")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["assetIndex": ["id": "fixture"]]).write(to: source.appendingPathComponent("test.json"))
        let data = try Data(contentsOf: fixture), hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let indexes = installation.appendingPathComponent("assets/indexes"), objects = installation.appendingPathComponent("assets/objects/\(hash.prefix(2))")
        try FileManager.default.createDirectory(at: indexes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        try data.write(to: objects.appendingPathComponent(hash))
        let indexURL = indexes.appendingPathComponent("fixture.json")
        func index(_ hash: String, _ size: Int) throws {
            try JSONSerialization.data(withJSONObject: ["objects": ["minecraft/sounds/random/click.ogg": ["hash": hash, "size": size]]]).write(to: indexURL)
        }
        try index(hash, data.count)
        let assets = try XCTUnwrap(JavaAudioImporter.installedAssets(for: jar))
        XCTAssertEqual(try JavaAudioImporter.readObject("random/click", assets: assets), data)
        try Data(contentsOf: JavaTextureImportTests.fixture).write(to: jar)
        let imported = try JavaTextureImporter.importTextures(from: jar, cacheRoot: root.appendingPathComponent("cache"))
        XCTAssertEqual(imported.pack.sounds.count, 5)
        XCTAssertEqual(imported.record.soundMappings?["buttonPress"], "launcher:minecraft/sounds/random/click.ogg")
        try index("../outside", data.count)
        XCTAssertThrowsError(try JavaAudioImporter.readObject("random/click", assets: XCTUnwrap(JavaAudioImporter.installedAssets(for: jar))))
        try index(hash, data.count + 1)
        XCTAssertThrowsError(try JavaAudioImporter.readObject("random/click", assets: XCTUnwrap(JavaAudioImporter.installedAssets(for: jar))))
        try index(hash, data.count)
        try Data(repeating: 0, count: data.count).write(to: objects.appendingPathComponent(hash))
        XCTAssertThrowsError(try JavaAudioImporter.readObject("random/click", assets: assets))
        try JSONSerialization.data(withJSONObject: ["assetIndex": ["id": "../outside"]]).write(to: source.appendingPathComponent("test.json"))
        XCTAssertThrowsError(try JavaAudioImporter.installedAssets(for: jar))
    }
    @MainActor func testAssetSelectionPublishesImportedAudioAndBuiltinClearsOverrides() async throws {
        let root = try temporary(), source = root.appendingPathComponent("source")
        try png(source)
        let sound = source.appendingPathComponent("assets/minecraft/sounds/random/click.ogg")
        try FileManager.default.createDirectory(at: sound.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: fixture).write(to: sound)
        let assets = AssetLibrary(importCacheRoot: root.appendingPathComponent("cache"))
        await assets.importJava(source)
        XCTAssertEqual(assets.soundOverrides.count, 5)
        XCTAssertTrue(assets.status.contains("5 sounds"))
        assets.useBuiltIn(); XCTAssertTrue(assets.soundOverrides.isEmpty)
    }
}
