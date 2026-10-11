import Foundation

struct InstalledJavaVersion: Identifiable, Sendable {
    var id: URL { url }
    let name: String
    let url: URL
}

enum JavaInstallation {
    static var defaultVersionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/minecraft/versions")
    }
    static func discover(in directory: URL = defaultVersionsDirectory) throws -> [InstalledJavaVersion] {
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(512).compactMap { folder in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let jar = folder.appendingPathComponent(folder.lastPathComponent + ".jar")
            guard let values = try? jar.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size >= 22, size <= 256 * 1024 * 1024 else { return nil }
            return InstalledJavaVersion(name: folder.lastPathComponent, url: jar)
        }.sorted {
            if $0.name.hasPrefix("1.") != $1.name.hasPrefix("1.") { return $0.name.hasPrefix("1.") }
            return $0.name.compare($1.name, options: .numeric) == .orderedDescending
        }
    }
}

struct JavaImportRecord: Codable, Sendable {
    var formatVersion = 1
    let id: UUID
    let sourcePath: String
    let importedAt: Date
    let mappings: [String: String]
    let warnings: [String]
}

struct JavaImportResult: Sendable {
    let folder: URL
    let record: JavaImportRecord
    let pack: LoadedPack
}

struct JavaTextureMapping: Sendable {
    let id: TextureAssetID
    let paths: [String]
    let tint: [Int]?
    let art: JavaCircuitArt?
}

enum JavaTextureImporter {
    static var applicationCacheRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RedstoneDesktop/ImportedTextures", isDirectory: true)
    }
    static let mappings: [JavaTextureMapping] = [
        mapping(.terrainGrass, "grass_block_top", old: "grass_top", tint: [108,160,62]),
        mapping(.terrainDryGrass, "grass_block_top", old: "grass_top", tint: [181,168,69]),
        mapping(.terrainSnow, "snow"), mapping(.terrainGravel, "gravel"),
        mapping(.decorationOakLog, "oak_log_top", old: "log_oak_top"),
        mapping(.decorationSpruceLog, "spruce_log_top", old: "log_spruce_top"),
        mapping(.decorationPine, "spruce_leaves", old: "leaves_spruce", tint: [55,100,75]),
        mapping(.decorationShrub, "acacia_leaves", old: "leaves_acacia", tint: [140,145,55]),
        mapping(.decorationMushroom, "red_mushroom", old: "mushroom_red"),
        mapping(.terrainDirt, "dirt"), mapping(.terrainStone, "stone"), mapping(.terrainSand, "sand"),
        mapping(.lavaStill, "lava_still"),
        mapping(.waterShallow, "water_still", tint: [80,180,220]), mapping(.waterDeep, "water_still", tint: [45,95,180]),
        mapping(.decorationTree, "oak_leaves", old: "leaves_oak", tint: [70,145,50]),
        mapping(.decorationFlower, "poppy", old: "flower_rose"), mapping(.decorationReed, "sugar_cane", old: "reeds"),
        mapping(.decorationDandelion, "dandelion", old: "flower_dandelion"),
        mapping(.decorationBlueOrchid, "blue_orchid", old: "flower_blue_orchid"),
        mapping(.decorationAllium, "allium", old: "flower_allium"),
        mapping(.decorationOxeyeDaisy, "oxeye_daisy", old: "flower_oxeye_daisy"),
        mapping(.decorationCoal, "coal_ore"), mapping(.decorationIron, "iron_ore"),
        mapping(.decorationCactus, "cactus_top", art: .cactus),
        mapping(.redstoneOutputOff, "command_block_front", art: .output(false)),
        mapping(.redstoneOutputOn, "command_block_front", art: .output(true)),
        mapping(.redstoneButtonUp, "stone", art: .button(false)), mapping(.redstoneButtonDown, "stone", art: .button(true)),
        mapping(.redstoneLeverOff, "lever", art: .lever(false)), mapping(.redstoneLeverOn, "lever", art: .lever(true)),
        mapping(.redstoneRepeaterOff, "repeater", old: "repeater_off", art: .repeater(false)),
        mapping(.redstoneRepeaterOn, "repeater_on", art: .repeater(true)),
        mapping(.redstonePlateOff, "oak_planks", old: "planks_oak", art: .plate(false)),
        mapping(.redstonePlateOn, "oak_planks", old: "planks_oak", art: .plate(true)),
        mapping(.redstoneSensorOff, "stone", art: .plate(false)),
        mapping(.redstoneSensorOn, "stone", art: .plate(true)),
        mapping(.redstoneLampOff, "redstone_lamp", old: "redstone_lamp_off"),
        mapping(.redstoneLampOn, "redstone_lamp_on"),
        mapping(.lightTorch, "torch", old: "torch_on"),
        mapping(.redstoneTorchOff, "redstone_torch_off"),
        mapping(.redstoneTorchOn, "redstone_torch", old: "redstone_torch_on"),
        mapping(.redstoneDustOff, "redstone_dust_dot", art: .dust(false)),
        mapping(.redstoneDustOn, "redstone_dust_dot", art: .dust(true))
    ]
    private static func mapping(_ id: TextureAssetID, _ name: String, old: String? = nil, tint: [Int]? = nil, art: JavaCircuitArt? = nil) -> JavaTextureMapping {
        JavaTextureMapping(id: id, paths: ["assets/minecraft/textures/block/\(name).png", "assets/minecraft/textures/blocks/\(old ?? name).png"], tint: tint, art: art)
    }
    static func importTextures(from sourceURL: URL, cacheRoot: URL) throws -> JavaImportResult {
        let source: PackSource?
        let archive: SafeZIP?
        let prefix: String
        if (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            source = try PackSource(url: sourceURL); archive = nil; prefix = ""
        } else {
            let zip = try SafeZIP(url: sourceURL)
            let candidates = Set(mappings.flatMap(\.paths).flatMap { path in
                zip.entries.keys.filter { $0.hasSuffix(path) }.map { String($0.dropLast(path.count)) }
            })
            guard candidates.count == 1, let found = candidates.first else { throw PackError("No supported Minecraft Java textures, or ambiguous archive roots. Choose a vanilla version JAR or Java texture pack.") }
            source = nil; archive = zip; prefix = found
        }
        var images: [TextureAssetID: RasterAsset] = [:], used: [String: String] = [:], warnings: [String] = []
        var animations: [TextureAssetID: AnimatedRaster] = [:]
        for mapping in mappings {
            var accepted = false
            for path in mapping.paths {
                do {
                    let data: Data
                    if let archive { data = try archive.read(prefix + path, limit: 4 * 1024 * 1024) }
                    else { data = try source!.read(path, limit: 4 * 1024 * 1024) }
                    var raster = try RasterAsset.decode(data)
                    // Retain bounded liquid strips; other Java animation strips still use frame zero.
                    guard raster.height == raster.width || (raster.height > raster.width && raster.height % raster.width == 0) else { throw PackError("Unsupported nonsquare Java texture.") }
                    let frameCount = raster.height / raster.width
                    if !mapping.id.isAnimatedLiquid && frameCount > 1 {
                        raster = RasterAsset(width: raster.width, height: raster.width, pixels: Array(raster.pixels.prefix(raster.width * raster.width * 4)))
                    }
                    if let tint = mapping.tint {
                        for pixel in stride(from: 0, to: raster.pixels.count, by: 4) {
                            for channel in 0..<3 { raster.pixels[pixel + channel] = UInt8(Int(raster.pixels[pixel + channel]) * tint[channel] / 255) }
                        }
                    }
                    if let art = mapping.art { raster = art.render(raster) }
                    if mapping.id.isAnimatedLiquid && frameCount > 1 {
                        let metadata: Data?
                        if let archive { metadata = try? archive.read(prefix + path + ".mcmeta", limit: 64 * 1024) }
                        else { metadata = try? source!.read(path + ".mcmeta", limit: 64 * 1024) }
                        let spec: TextureAnimationSpec
                        do { spec = try TextureAnimationSpec.java(metadata: metadata, frameCount: frameCount) }
                        catch {
                            warnings.append("\(mapping.id.rawValue): invalid animation metadata; default frame timing used.")
                            spec = try TextureAnimationSpec.java(metadata: nil, frameCount: frameCount)
                        }
                        animations[mapping.id] = try AnimatedRaster(strip: raster, spec: spec)
                    }
                    images[mapping.id] = raster; used[mapping.id.rawValue] = prefix + path
                    accepted = true; break
                } catch {
                    // Missing alternatives are common across versions. Summarize once per semantic ID.
                }
            }
            if !accepted { warnings.append("\(mapping.id.rawValue): no valid supported source texture; built-in fallback.") }
        }
        guard !images.isEmpty else { throw PackError("No supported valid Java PNG textures were found. Previous pack preserved.") }
        let id = UUID(), record = JavaImportRecord(id: id, sourcePath: sourceURL.path, importedAt: Date(), mappings: used, warnings: warnings)
        let root = cacheRoot.resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".staging-\(id.uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        var assets: [String: String] = [:]
        for (id, image) in images {
            let filename = id.rawValue + ".png"
            try image.pngData().write(to: staging.appendingPathComponent(filename), options: .atomic)
            assets[id.rawValue] = filename
        }
        let manifest = PackManifest(name: "Java textures · \(String(sourceURL.deletingPathExtension().lastPathComponent.prefix(100)))", author: "Local import; original source rights apply", assets: assets, animations: animations.isEmpty ? nil : Dictionary(uniqueKeysWithValues: animations.map { ($0.key.rawValue, $0.value.spec) }))
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("pack.json"), options: .atomic)
        try JSONEncoder().encode(record).write(to: staging.appendingPathComponent("import.json"), options: .atomic)
        let validated = try ResourcePackLoader.load(staging) // Validate the generated format-1 pack before publishing its directory.
        try FileManager.default.moveItem(at: staging, to: folder)
        return JavaImportResult(folder: folder, record: record, pack: validated)
    }
    static func record(in folder: URL, cacheRoot: URL) throws -> JavaImportRecord {
        let root = cacheRoot.resolvingSymlinksInPath().standardizedFileURL
        let canonical = folder.standardizedFileURL
        guard canonical.deletingLastPathComponent() == root, canonical.resolvingSymlinksInPath() == canonical,
              let id = UUID(uuidString: canonical.lastPathComponent) else { throw PackError("Not a managed import directory.") }
        let data = try PackFiles.read(canonical.appendingPathComponent("import.json"), limit: 64 * 1024)
        let record = try JSONDecoder().decode(JavaImportRecord.self, from: data)
        guard record.formatVersion == 1, record.id == id, record.sourcePath.hasPrefix("/") else { throw PackError("Invalid managed import record.") }
        return record
    }
    static func remove(_ folder: URL, cacheRoot: URL) throws {
        _ = try record(in: folder, cacheRoot: cacheRoot)
        try FileManager.default.removeItem(at: folder)
    }
}
