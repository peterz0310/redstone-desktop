import AppKit
import XCTest
@testable import RedstoneDesktop

final class JavaTextureImportTests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SyntheticJava.zip")
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RedstoneJavaTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testDiscoveryUsesVersionFoldersAndNumericOrderingWithoutImporting() throws {
        let root = try temporary(), bytes = try Data(contentsOf: Self.fixture)
        for version in ["1.9", "1.21.8", "20w19a"] {
            let folder = root.appendingPathComponent(version)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent(version + ".jar"))
        }
        let versions = try JavaInstallation.discover(in: root)
        XCTAssertEqual(versions.map(\.name), ["1.21.8", "1.9", "20w19a"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 3)
        XCTAssertThrowsError(try JavaInstallation.discover(in: root.appendingPathComponent("missing")))
    }
    func testSyntheticDeflatedJavaArchiveImportsOnlyPNGAndPreservesSourceBytes() throws {
        let root = try temporary(), sourceBefore = try Data(contentsOf: Self.fixture)
        let result = try JavaTextureImporter.importTextures(from: Self.fixture, cacheRoot: root)
        XCTAssertEqual(result.pack.textures.count, 39)
        XCTAssertTrue(result.pack.sounds.isEmpty)
        XCTAssertEqual(result.record.warnings.count, 10, "Older fixture lacks wood plates, lamps, torch, particles and audio; originals supply these.")
        XCTAssertEqual(result.record.mappings["terrainGrass"], "assets/minecraft/textures/block/grass_block_top.png")
        XCTAssertEqual(try Data(contentsOf: Self.fixture), sourceBefore)
        let files = try FileManager.default.contentsOfDirectory(atPath: result.folder.path)
        XCTAssertEqual(files.count, 41)
        XCTAssertTrue(files.allSatisfy { $0.hasSuffix(".png") || $0 == "pack.json" || $0 == "import.json" })
        XCTAssertEqual(try JavaTextureImporter.record(in: result.folder, cacheRoot: root).id, result.record.id)
        XCTAssertEqual(try ResourcePackLoader.load(result.folder).textures.count, 39)
    }
    func testFirstFrameAndFixedTintsAreExplicitNotGrayUntintedTextures() throws {
        let root = try temporary(), result = try JavaTextureImporter.importTextures(from: Self.fixture, cacheRoot: root)
        let grass = try XCTUnwrap(result.pack.textures[.terrainGrass])
        XCTAssertEqual(Array(grass.pixels.prefix(4)), [108,160,62,255])
        XCTAssertEqual(Array(try XCTUnwrap(result.pack.textures[.terrainDryGrass]).pixels.prefix(4)), [181,168,69,255])
        for id in [TextureAssetID.terrainSnow, .terrainGravel, .decorationPine, .decorationShrub, .decorationMushroom] {
            XCTAssertNotNil(result.pack.textures[id], id.rawValue)
        }
        let water = try XCTUnwrap(result.pack.textures[.waterShallow])
        XCTAssertEqual(water.width, 16); XCTAssertEqual(water.height, 16)
        XCTAssertEqual(Array(water.pixels.prefix(4)), [80,180,220,255])
        XCTAssertNotEqual(water.pixels, result.pack.textures[.waterDeep]?.pixels)
        let animation = try XCTUnwrap(result.pack.animations[.waterShallow])
        XCTAssertEqual(animation.frameCount, 2)
        XCTAssertEqual(animation.spec.durations, [0.1, 0.2])
        XCTAssertTrue(animation.spec.interpolate)
        XCTAssertNotEqual(animation.frame(0).pixels, animation.frame(1).pixels)
        XCTAssertEqual(result.pack.animations[.lavaStill]?.frameCount, 2)
        XCTAssertEqual(try ResourcePackLoader.load(result.folder).animations[.waterShallow]?.spec, animation.spec)
        XCTAssertNotNil(result.pack.textures[.redstoneRepeaterOn])
        XCTAssertNotNil(result.pack.textures[.redstoneTorchOn])
        XCTAssertNotNil(result.pack.textures[.redstoneTorchOff])
    }
    func testNativeFolderAndLegacyAliasHavePartialBuiltinFallback() throws {
        let source = try temporary(), cache = try temporary()
        let folder = source.appendingPathComponent("assets/minecraft/textures/blocks")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = RasterAsset(width: 2, height: 2, pixels: [UInt8](repeating: 255, count: 16))
        try image.pngData().write(to: folder.appendingPathComponent("grass_top.png"))
        let result = try JavaTextureImporter.importTextures(from: source, cacheRoot: cache)
        XCTAssertEqual(result.pack.textures.count, 2)
        XCTAssertEqual(result.record.warnings.count, 47)
        XCTAssertEqual(result.record.mappings["terrainGrass"], "assets/minecraft/textures/blocks/grass_top.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("grass_top.png").path))
    }
    func testEmptyInvalidAndNonsquareJavaSourcesProduceNoCache() throws {
        let source = try temporary(), cache = source.appendingPathComponent("cache")
        XCTAssertThrowsError(try JavaTextureImporter.importTextures(from: source, cacheRoot: cache))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        let folder = source.appendingPathComponent("assets/minecraft/textures/block")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RasterAsset(width: 3, height: 2, pixels: [UInt8](repeating: 255, count: 24)).pngData().write(to: folder.appendingPathComponent("stone.png"))
        XCTAssertThrowsError(try JavaTextureImporter.importTextures(from: source, cacheRoot: cache))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertThrowsError(try JavaTextureImporter.importTextures(from: ResourcePackTests.examples.appendingPathComponent("GrassOnly.zip"), cacheRoot: cache))
    }
    func testRemovalOnlyTouchesValidatedManagedUUIDDirectory() throws {
        let root = try temporary(), result = try JavaTextureImporter.importTextures(from: Self.fixture, cacheRoot: root)
        let external = try temporary()
        try JSONEncoder().encode(result.record).write(to: external.appendingPathComponent("import.json"))
        XCTAssertThrowsError(try JavaTextureImporter.remove(external, cacheRoot: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        let link = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertThrowsError(try JavaTextureImporter.remove(link, cacheRoot: root))
        try JavaTextureImporter.remove(result.folder, cacheRoot: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Self.fixture.path))
    }
    @MainActor
    func testReimportPreferenceRestoreAndRemoveNeverTouchSourceOrWorlds() async throws {
        let root = try temporary(), suite = "RedstoneJavaTests.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = AssetLibrary(preferences: defaults, importCacheRoot: root)
        await library.importJava(Self.fixture)
        let first = try XCTUnwrap(library.importFolder)
        XCTAssertEqual(library.pack?.textures.count, 39)
        library.useBuiltIn()
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertNotNil(library.importRecord)
        await library.reimportJava()
        let second = try XCTUnwrap(library.importFolder)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        let restored = AssetLibrary(preferences: defaults, importCacheRoot: root)
        await restored.restoreSelection()
        XCTAssertEqual(restored.importRecord?.sourcePath, Self.fixture.path)
        XCTAssertEqual(restored.pack?.textures.count, 39)
        restored.removeImportedAssets()
        XCTAssertNil(restored.pack); XCTAssertNil(restored.importRecord)
        XCTAssertNil(defaults.string(forKey: "assetPackPath")); XCTAssertNil(defaults.string(forKey: "lastJavaImportID"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Self.fixture.path))
    }
    @MainActor
    func testFailedImportPreservesPreviouslySelectedPackAndCache() async throws {
        let root = try temporary(), library = AssetLibrary(importCacheRoot: root)
        await library.importJava(Self.fixture)
        let revision = library.revision, folder = library.importFolder
        await library.importJava(root.appendingPathComponent("missing.jar"))
        XCTAssertEqual(library.revision, revision); XCTAssertEqual(library.importFolder, folder)
        XCTAssertEqual(library.pack?.textures.count, 39)
        XCTAssertTrue(library.status.contains("refused"))
    }
    @MainActor
    func testRemovingInactiveImportPreservesExternalCustomPack() async throws {
        let library = AssetLibrary(importCacheRoot: try temporary())
        await library.importJava(Self.fixture)
        await library.load(ResourcePackTests.examples.appendingPathComponent("GrassOnly"))
        let source = library.source, revision = library.revision
        library.removeImportedAssets()
        XCTAssertEqual(library.source, source); XCTAssertEqual(library.revision, revision)
        XCTAssertEqual(library.pack?.manifest.name, "Original Grass Checker")
    }
    func testCacheWriteFailureDoesNotPublishOrAlterSource() throws {
        let root = try temporary(), file = root.appendingPathComponent("not-directory")
        try Data("fixture".utf8).write(to: file)
        let before = try Data(contentsOf: Self.fixture)
        XCTAssertThrowsError(try JavaTextureImporter.importTextures(from: Self.fixture, cacheRoot: file))
        XCTAssertEqual(try Data(contentsOf: Self.fixture), before)
        XCTAssertEqual(try Data(contentsOf: file), Data("fixture".utf8))
    }
}
