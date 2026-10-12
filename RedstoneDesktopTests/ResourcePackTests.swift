import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class ResourcePackTests: XCTestCase {
    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("examples")
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RedstonePackTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func manifest(_ root: URL, assets: [String: String], version: Int = 1) throws {
        try JSONEncoder().encode(PackManifest(formatVersion: version, name: "Fixture", assets: assets)).write(to: root.appendingPathComponent("pack.json"))
    }
    func png() throws -> Data { try Data(contentsOf: Self.examples.appendingPathComponent("GrassOnly/textures/grass.png")) }
    func testFolderAndRealDeflatedZIPProduceSameOverrides() throws {
        let folder = try ResourcePackLoader.load(Self.examples.appendingPathComponent("GrassOnly"))
        let zip = try ResourcePackLoader.load(Self.examples.appendingPathComponent("GrassOnly.zip"))
        XCTAssertEqual(folder.manifest, zip.manifest)
        XCTAssertEqual(folder.textures[.terrainGrass]?.pixels, zip.textures[.terrainGrass]?.pixels)
        XCTAssertEqual(folder.textures.count, 1); XCTAssertTrue(folder.sounds.isEmpty); XCTAssertTrue(zip.warnings.isEmpty)
    }
    func testUnsafePathsAndManifestVersionsAreRefused() throws {
        let root = try temporary()
        for path in ["../outside.png", "/tmp/a.png", "textures\\a.png", "textures//a.png", "./a.png", "C:/a.png"] {
            try manifest(root, assets: ["terrainGrass": path])
            XCTAssertThrowsError(try ResourcePackLoader.load(root))
        }
        try manifest(root, assets: [:], version: 2)
        XCTAssertThrowsError(try ResourcePackLoader.load(root))
        try Data("{}".utf8).write(to: root.appendingPathComponent("pack.json"))
        XCTAssertThrowsError(try ResourcePackLoader.load(root))
    }
    func testMissingMalformedUnknownAndUnsupportedAssetsFallBackIndividually() throws {
        let root = try temporary()
        try Data("not PNG".utf8).write(to: root.appendingPathComponent("bad.png"))
        try manifest(root, assets: ["terrainGrass":"missing.png", "terrainStone":"bad.png", "terrainSand":"file.exe", "futureTexture":"ignored.png"])
        let pack = try ResourcePackLoader.load(root)
        XCTAssertTrue(pack.textures.isEmpty); XCTAssertEqual(pack.warnings.count, 4)
    }
    func testFolderSymlinkCannotReadOutsideRoot() throws {
        let root = try temporary(), outside = try temporary().appendingPathComponent("outside.png")
        try png().write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: outside)
        try manifest(root, assets: ["terrainGrass":"link.png"])
        let pack = try ResourcePackLoader.load(root)
        XCTAssertTrue(pack.textures.isEmpty)
        XCTAssertTrue(pack.warnings.first?.contains("symlink") == true)
    }
    func testImageHeaderBoundsAndPixelOrientationRoundTrip() throws {
        let raster = RasterAsset(width: 1, height: 2, pixels: [255,0,0,255, 0,0,255,255])
        let decoded = try RasterAsset.decode(raster.pngData())
        XCTAssertEqual(decoded.pixels, raster.pixels)
        XCTAssertEqual(decoded.sample(x: 0, y: 0, resolution: 2).2, 255)
        let large = RasterAsset(width: 1025, height: 1, pixels: [UInt8](repeating: 255, count: 1025 * 4))
        XCTAssertThrowsError(try RasterAsset.decode(large.pngData()))
        XCTAssertThrowsError(try RasterAsset.decode(Data(repeating: 0, count: 4 * 1024 * 1024 + 1)))
    }
    func testZIPRejectsEncryptionSymlinksInvalidCentralAndBadCRC() throws {
        let original = try Data(contentsOf: Self.examples.appendingPathComponent("GrassOnly.zip"))
        let signature: [UInt8] = [0x50,0x4b,0x01,0x02]
        let central = try XCTUnwrap((0..<(original.count - 4)).first { Array(original[$0..<($0 + 4)]) == signature })
        for field in [8, 38, 16, 46] {
            var data = original
            if field == 8 { data[central + 8] |= 1 }
            if field == 38 { data[central + 41] = 0xa0 }
            if field == 16 { data[central + 16] ^= 0xff }
            if field == 46 { data.replaceSubrange((central + 46)..<(central + 49), with: Array("../".utf8)) }
            if field == 16 {
                let zip = try SafeZIP(data: data)
                XCTAssertThrowsError(try zip.read("GrassOnly/pack.json", limit: 65536))
            } else { XCTAssertThrowsError(try SafeZIP(data: data)) }
        }
        XCTAssertThrowsError(try SafeZIP(data: Data(original.dropLast(3))))
        let zip = try SafeZIP(data: original)
        XCTAssertThrowsError(try zip.read("GrassOnly/textures/grass.png", limit: 1))
    }
    func testWAVResamplingPeakLimitAndInvalidInput() throws {
        func u16(_ x: Int) -> [UInt8] { [UInt8(x & 255), UInt8((x >> 8) & 255)] }
        func u32(_ x: Int) -> [UInt8] { u16(x & 65535) + u16(x >> 16) }
        let payload = Array(repeating: u16(30000), count: 800).flatMap { $0 }
        let fmt = u16(1) + u16(1) + u32(8000) + u32(16000) + u16(2) + u16(16)
        let bytes = Array("RIFF".utf8) + u32(36 + payload.count) + Array("WAVEfmt ".utf8) + u32(16) + fmt + Array("data".utf8) + u32(payload.count) + payload
        let samples = try PackWAV.decode(Data(bytes))
        XCTAssertEqual(samples.count, 4410)
        XCTAssertTrue(samples.allSatisfy { abs($0) <= 0.11001 })
        XCTAssertThrowsError(try PackWAV.decode(Data(bytes.dropLast())))
        XCTAssertThrowsError(try PackWAV.decode(Data()))
    }
    @MainActor
    func testTransparentWaterHasOpaqueBackingForChunksAndFiniteTiles() throws {
        let library = AssetLibrary()
        for terrain in [TerrainID.shallowWater, .deepWater] {
            for alpha in [UInt8(0), 128, 255] {
                let rgba: [UInt8] = alpha == 0 ? [0, 0, 0, 0] : [10, 20, 30, alpha]
                let raster = RasterAsset(width: 1, height: 1, pixels: rgba)
                library.apply(LoadedPack(manifest: PackManifest(name: "Water", assets: [:]),
                    textures: [.terrain(terrain): raster], sounds: [:], warnings: []))
                let base = OriginalTerrainPixels.pixel(Tile(terrain: terrain), x: 1, y: 0)
                let pixel = library.pixel(Tile(terrain: terrain), x: 1, y: 0)
                let display = terrain == .shallowWater ? [Int(rgba[0]) * 70 / 100, Int(rgba[1]) * 70 / 100, Int(rgba[2]) * 88 / 100] : rgba.prefix(3).map(Int.init)
                XCTAssertEqual(pixel.0, UInt8(display[0] + Int(base.0) * (255 - Int(alpha)) / 255))
                XCTAssertEqual(pixel.1, UInt8(display[1] + Int(base.1) * (255 - Int(alpha)) / 255))
                XCTAssertEqual(pixel.2, UInt8(display[2] + Int(base.2) * (255 - Int(alpha)) / 255))
                XCTAssertEqual(pixel.3, 255)
                let image = try XCTUnwrap(library.texture(for: .terrain(terrain)))
                let bitmap = NSBitmapImageRep(cgImage: image.cgImage())
                XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 1, accuracy: 0.001)
                XCTAssertEqual(raster.pixels, rgba, "Source/cache pixels remain unchanged")
            }
        }
        let decoration = RasterAsset(width: 1, height: 1, pixels: [0, 0, 0, 0])
        library.apply(LoadedPack(manifest: PackManifest(name: "Decoration", assets: [:]), textures: [.decorationTree: decoration], sounds: [:], warnings: []))
        let image = try XCTUnwrap(library.texture(for: .decorationTree))
        XCTAssertEqual(try XCTUnwrap(NSBitmapImageRep(cgImage: image.cgImage()).colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.001)
    }

    @MainActor
    func testProviderPartialFallbackAndRevisionInvalidatesCircuitCache() throws {
        let library = AssetLibrary(), textures = CircuitTextures()
        textures.assets = library
        let old = textures.texture(for: .buttonUp)
        let raster = try RasterAsset.decode(png())
        library.apply(LoadedPack(manifest: PackManifest(name: "Fixture", assets: [:]), textures: [.terrainGrass:raster, .redstoneButtonUp:raster], sounds: [:], warnings: []))
        XCTAssertEqual(library.terrainResolution, 16)
        XCTAssertFalse(textures.texture(for: .buttonUp) === old)
        XCTAssertEqual(textures.texture(for: .buttonUp).filteringMode, .nearest)
        let stone = library.pixel(Tile(terrain: .stone), x: 0, y: 0)
        let builtIn = OriginalTerrainPixels.pixel(Tile(terrain: .stone), x: 0, y: 0)
        XCTAssertEqual(stone.0, builtIn.0)
        library.useBuiltIn()
        XCTAssertEqual(library.terrainResolution, 8)
        XCTAssertTrue(textures.texture(for: .buttonUp) === old)
    }
    @MainActor
    func testLivePackSwapPreservesLibrarySimulatorAndCameraAndRebuildsOnlyAppearance() async throws {
        let library = AssetLibrary(), screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 2)
        let model = FinderDiagnosticsModel(provider: ResourceItemProvider())
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), finderDiagnostics: model,
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: FixtureItemOpener(), assets: library)
        defer { app.shutdown() }
        await model.readItems(); app.toggleDesktopWorld()
        app.handleCircuitClick(DemoCircuit.lever); await app.activationTask?.value
        app.advanceCircuitTick(); await app.activationTask?.value
        XCTAssertGreaterThan(app.simulator.power(at: DemoCircuit.leverOutput), .off)
        let saved = app.library, simulation = app.simulator, camera = app.desktopCamera, controller = app.desktopController
        await library.load(Self.examples.appendingPathComponent("GrassOnly.zip"))
        await Task.yield()
        XCTAssertEqual(app.library, saved); XCTAssertEqual(app.simulator, simulation); XCTAssertEqual(app.desktopCamera, camera)
        XCTAssertTrue(app.desktopController === controller)
        XCTAssertEqual(library.pack?.textures.count, 1)
        let renderer = EditorCanvasRenderer(), editor = EditorSession()
        let scene = try XCTUnwrap(renderer.update(appState: app, editor: editor, size: CGSize(width: 800, height: 600)))
        let before = scene.terrainMetrics
        library.useBuiltIn(); await Task.yield()
        renderer.update(appState: app, editor: editor, size: CGSize(width: 800, height: 600))
        XCTAssertGreaterThan(scene.terrainMetrics.textureBuilds, before.textureBuilds)
        await library.load(URL(fileURLWithPath: "/nonexistent/pack.zip"))
        XCTAssertNil(library.pack); XCTAssertTrue(library.status.contains("refused"))
    }
    @MainActor
    func testRefusedReplacementPreservesTexturesSoundsSourceRevisionAndSavedChoice() async throws {
        let suite = "RedstoneDesktopTests.pack-stability.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let library = AssetLibrary(preferences: preferences)
        let source = Self.examples.appendingPathComponent("GrassOnly")
        await library.load(source)
        // A working pack may also have imported effects. Failure must not reset them.
        let original = try XCTUnwrap(library.pack)
        let pack = LoadedPack(manifest: original.manifest, textures: original.textures, sounds: [.buttonPress: BuiltInSounds.samples(for: .buttonPress)], warnings: original.warnings)
        library.apply(pack)
        let revision = library.revision, name = library.name, warnings = library.warnings
        let texture = try XCTUnwrap(library.texture(for: .terrainGrass))
        await library.load(URL(fileURLWithPath: "/nonexistent/refused-pack.zip"))
        XCTAssertEqual(library.revision, revision)
        XCTAssertEqual(library.name, name); XCTAssertEqual(library.warnings, warnings)
        XCTAssertEqual(library.source, source)
        XCTAssertTrue(library.texture(for: .terrainGrass) === texture)
        XCTAssertEqual(library.soundOverrides, pack.sounds)
        XCTAssertEqual(preferences.string(forKey: "assetPackPath"), source.path)
        XCTAssertTrue(library.status.contains("unchanged")); XCTAssertFalse(library.isLoading)
    }

    @MainActor
    func testReloadAndPreferenceRestoreRevalidateSourceAndUseBuiltInClearsChoice() async throws {
        let root = try temporary()
        try png().write(to: root.appendingPathComponent("grass.png"))
        try manifest(root, assets: ["terrainGrass":"grass.png"])
        let suite = "RedstonePackTests.\(UUID())"
        // A unique suite only; never use the owner's standard app preferences.
        let isolated = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolated.removePersistentDomain(forName: suite) }
        let library = AssetLibrary(preferences: isolated)
        await library.load(root)
        XCTAssertEqual(library.pack?.textures.count, 1)
        let restored = AssetLibrary(preferences: isolated)
        await restored.restoreSelection()
        XCTAssertEqual(restored.pack?.textures.count, 1)
        try FileManager.default.removeItem(at: root.appendingPathComponent("grass.png"))
        await restored.load(root)
        XCTAssertEqual(restored.pack?.textures.count, 0)
        XCTAssertEqual(restored.warnings.count, 1)
        restored.useBuiltIn()
        XCTAssertNil(isolated.string(forKey: "assetPackPath"))
    }

    @MainActor
    func testActualOfflineAudioOverrideAndFallback() throws {
        let engine = try AudioEngine(offline: true)
        defer { engine.stop() }
        engine.replaceSoundOverrides([.buttonPress: [Float](repeating: 0, count: 4096)])
        engine.play(.buttonPress)
        let silent = try engine.renderOffline(frames: 2048)
        XCTAssertTrue((0..<Int(silent.frameLength)).allSatisfy { abs(silent.floatChannelData![0][$0]) < 0.0001 })
        engine.replaceSoundOverrides([:]); engine.play(.buttonPress)
        let sound = try engine.renderOffline(frames: 2048)
        XCTAssertTrue((0..<Int(sound.frameLength)).contains { abs(sound.floatChannelData![0][$0]) > 0.001 })
    }
}

@MainActor
private final class ResourceItemProvider: DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem] { [] }
}
