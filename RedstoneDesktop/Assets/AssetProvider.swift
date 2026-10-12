import SpriteKit
import Combine

@MainActor
protocol AssetProvider: AnyObject {
    var revision: UUID { get }
    var terrainResolution: Int { get }
    func texture(for id: TextureAssetID) -> SKTexture?
    func liquidAnimation(for terrain: TerrainID) -> AnimatedRaster
    func pixel(_ tile: Tile, x: Int, y: Int, appearance: DecorationAppearance?) -> (UInt8, UInt8, UInt8, UInt8)
}

extension AssetProvider {
    func liquidAnimation(for terrain: TerrainID) -> AnimatedRaster { OriginalLiquidAnimation.make(terrain) }

    func pixel(_ tile: Tile, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        pixel(tile, x: x, y: y, appearance: nil)
    }
}

@MainActor
final class BuiltInAssetProvider: AssetProvider {
    let revision = UUID()
    let terrainResolution = 8
    private var textures: [TextureAssetID: SKTexture] = [:]
    func texture(for id: TextureAssetID) -> SKTexture? {
        if let existing = textures[id] { return existing }
        let texture: SKTexture
        if id.isParticle { texture = SKTexture(image: WorldParticleRenderer.originalImage(for: id)) }
        else if let circuit = id.circuitID { texture = SKTexture(image: CircuitTextures.image(for: circuit)) }
        else {
            let terrain = TerrainID.allCases.first { TextureAssetID.terrain($0) == id }
            let appearance: DecorationAppearance? = id == .decorationTree ? .treeLeaves : id == .decorationPine ? .pineLeaves : id.decorationAppearance
            let decoration: DecorationID? = appearance.map { value in
                switch value {
                case .pineLeaves: .pineLeaves
                case .treeLeaves: .treeLeaves
                case .pine: .pine
                case .shrub: .shrub
                case .mushroom: .mushroom
                case .tree: .tree
                case .reed: .reed
                case .coal, .iron, .cactus: .rock
                default: .flower
                }
            }
            guard terrain != nil || decoration != nil || id == .decorationOakLog || id == .decorationSpruceLog else { return nil }
            var bytes: [UInt8] = []
            for y in (0..<8).reversed() {
                for x in 0..<8 {
                    let value = id == .decorationOakLog || id == .decorationSpruceLog
                        ? OriginalTerrainPixels.logPixel(x: x, y: y, pine: id == .decorationSpruceLog)
                        : OriginalTerrainPixels.pixel(Tile(terrain: terrain ?? .grass, decoration: decoration), x: x, y: y, appearance: appearance)
                    let plain = OriginalTerrainPixels.pixel(Tile(terrain: terrain ?? .grass), x: x, y: y)
                    bytes += decoration != nil && value == plain ? [0,0,0,0] : [value.0,value.1,value.2,value.3]
                }
            }
            guard let image = RasterAsset(width: 8, height: 8, pixels: bytes).cgImage else { return nil }
            texture = SKTexture(cgImage: image)
        }
        texture.filteringMode = .nearest
        textures[id] = texture
        return texture
    }
    func pixel(_ tile: Tile, x: Int, y: Int, appearance: DecorationAppearance?) -> (UInt8, UInt8, UInt8, UInt8) { OriginalTerrainPixels.pixel(tile, x: x, y: y, appearance: appearance) }
}

@MainActor
final class AssetLibrary: ObservableObject, AssetProvider {
    @Published private(set) var revision = UUID()
    @Published private(set) var name = "Built-in original assets"
    @Published private(set) var status = "Choose an optional pack; missing assets use built-in defaults."
    @Published private(set) var warnings: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var source: URL?
    private(set) var pack: LoadedPack?
    private let builtIn = BuiltInAssetProvider()
    private var textures: [TextureAssetID: SKTexture] = [:]
    private var generation = UUID()
    private var maintenanceSuspended = false
    private var activeImports = 0
    private let preferences: UserDefaults?
    let importCacheRoot: URL?
    @Published private(set) var installedVersions: [InstalledJavaVersion] = []
    @Published private(set) var discoveryStatus = ""
    @Published private(set) var importFolder: URL?
    @Published private(set) var importRecord: JavaImportRecord?
    private(set) var terrainResolution = 8
    var soundOverrides: [SoundID: [Float]] { pack?.sounds ?? [:] }

    init(preferences: UserDefaults? = nil, importCacheRoot: URL? = nil) {
        self.preferences = preferences; self.importCacheRoot = importCacheRoot
        if let root = importCacheRoot, let id = preferences?.string(forKey: "lastJavaImportID"), UUID(uuidString: id) != nil {
            let folder = root.resolvingSymlinksInPath().appendingPathComponent(id)
            if let record = try? JavaTextureImporter.record(in: folder, cacheRoot: root) { importFolder = folder; importRecord = record }
        }
    }

    func discoverJava(in directory: URL? = nil) async {
        guard !maintenanceSuspended else { return }
        let request = generation
        guard importCacheRoot != nil || directory != nil else { return } // Isolated test hosts never scan the owner's installation.
        let result = await Task.detached { Result { try JavaInstallation.discover(in: directory ?? JavaInstallation.defaultVersionsDirectory) } }.value
        guard !maintenanceSuspended, generation == request else { return }
        switch result {
        case .success(let versions):
            installedVersions = versions
            discoveryStatus = versions.isEmpty ? "No installed version JARs found. Choose a local JAR/Java pack manually." : "\(versions.count) local Java versions found. Choose one to import."
        case .failure:
            installedVersions = []
            discoveryStatus = "Minecraft's usual versions folder was not found/readable. Choose a local JAR/Java pack manually."
        }
    }

    func importJava(_ url: URL) async {
        guard !maintenanceSuspended else { return }
        activeImports += 1
        defer { activeImports -= 1 }
        guard let root = importCacheRoot else { status = "Local import cache is unavailable."; return }
        generation = UUID(); let request = generation
        isLoading = true; status = "Importing Minecraft textures and sounds…"
        let result = await Task.detached(priority: .userInitiated) { Result { try JavaTextureImporter.importTextures(from: url, cacheRoot: root) } }.value
        guard generation == request else {
            if case let .success(value) = result { try? JavaTextureImporter.remove(value.folder, cacheRoot: root) }
            return
        }
        switch result {
        case .success(let value):
            let previous = importFolder
            importFolder = value.folder; importRecord = value.record; source = value.folder
            apply(value.pack); warnings += value.record.warnings
            status = "Imported \(value.pack.textures.count) textures and \(value.pack.sounds.count) sounds. Missing assets use originals."
            preferences?.set(value.folder.path, forKey: "assetPackPath")
            preferences?.set(value.record.id.uuidString, forKey: "lastJavaImportID")
            if let previous, previous != value.folder {
                do { try JavaTextureImporter.remove(previous, cacheRoot: root) }
                catch { warnings.append("Previous import cache retained: \(error.localizedDescription)") }
            }
        case .failure(let error): status = "Import refused: \(error.localizedDescription) Previous appearance preserved."
        }
        isLoading = false
    }

    func reimportJava() async {
        guard let importRecord else { return }
        await importJava(URL(fileURLWithPath: importRecord.sourcePath))
    }

    func removeImportedAssets() {
        guard !maintenanceSuspended else { return }
        guard let folder = importFolder, let root = importCacheRoot else { return }
        generation = UUID(); isLoading = false
        do {
            try JavaTextureImporter.remove(folder, cacheRoot: root)
            if source == folder { useBuiltIn() }
            importFolder = nil; importRecord = nil
            preferences?.removeObject(forKey: "lastJavaImportID")
            status = "Imported cache removed. Original source JAR/pack was not changed."
        } catch { status = "Import cache removal failed: \(error.localizedDescription)" }
    }
    func restoreSelection() async {
        guard let path = preferences?.string(forKey: "assetPackPath") else { return }
        await load(URL(fileURLWithPath: path))
    }
    func load(_ url: URL) async {
        guard !maintenanceSuspended else { return }
        generation = UUID(); let request = generation
        isLoading = true; status = "Loading \(url.lastPathComponent)…"
        let result = await Task.detached(priority: .userInitiated) { Result { try ResourcePackLoader.load(url) } }.value
        guard generation == request else { return }
        switch result {
        case .success(let value):
            source = url
            apply(value)
            status = "\(value.textures.count) textures · \(value.sounds.count) sounds · \(value.warnings.count) warnings"
            preferences?.set(url.path, forKey: "assetPackPath")
        case .failure(let error):
            status = "Pack refused: \(error.localizedDescription) Your current appearance and sounds are unchanged."
        }
        isLoading = false
    }
    func useBuiltIn() {
        guard !maintenanceSuspended else { return }
        generation = UUID(); isLoading = false; source = nil
        apply(nil); status = "Built-in original assets active."
        preferences?.removeObject(forKey: "assetPackPath")
    }
    /// Invalidate publication, then wait for cache-writing workers to finish before a reset rename.
    func suspendForMaintenance() async {
        maintenanceSuspended = true; generation = UUID(); isLoading = false
        while activeImports > 0 {
            // Cancellation cannot turn this quiescence wait into a busy main-actor loop.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { continuation.resume() }
            }
        }
    }
    func resumeAfterMaintenance() { maintenanceSuspended = false }

    func apply(_ value: LoadedPack?) {
        pack = value; textures = [:]; name = value?.manifest.name ?? "Built-in original assets"
        terrainResolution = value?.textures.keys.contains(where: { $0.circuitID == nil }) == true ? 16 : 8
        warnings = value?.warnings ?? []; revision = UUID()
    }
    func liquidAnimation(for terrain: TerrainID) -> AnimatedRaster {
        let id = TextureAssetID.terrain(terrain)
        if let animation = pack?.animations[id] { return softened(animation, terrain: terrain) }
        if let raster = pack?.textures[id], raster.width == raster.height {
            return softened(try! AnimatedRaster(strip: raster, spec: TextureAnimationSpec(frames: [0], durations: [1])), terrain: terrain)
        }
        return OriginalLiquidAnimation.make(terrain)
    }
    private func softened(_ animation: AnimatedRaster, terrain: TerrainID) -> AnimatedRaster {
        guard terrain == .shallowWater else { return animation }
        return try! AnimatedRaster(strip: softened(animation.strip), spec: animation.spec)
    }
    private func softened(_ raster: RasterAsset) -> RasterAsset {
        var pixels = raster.pixels
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let color = OriginalTerrainPixels.softenedShallow((pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]))
            pixels[i] = color.0; pixels[i + 1] = color.1; pixels[i + 2] = color.2
        }
        return RasterAsset(width: raster.width, height: raster.height, pixels: pixels)
    }
    func texture(for id: TextureAssetID) -> SKTexture? {
        if let value = textures[id] { return value }
        guard var raster = pack?.textures[id] ?? id.decorationFallback.flatMap({ pack?.textures[$0] }) else { return builtIn.texture(for: id) }
        if id == .waterShallow { raster = softened(raster) }
        if let terrain = TerrainID.allCases.first(where: { TextureAssetID.terrain($0) == id && $0.definition.isLiquid }) {
            raster = raster.backedByOpaqueColor(OriginalTerrainPixels.pixel(Tile(terrain: terrain), x: 1, y: 0))
        }
        guard let image = raster.cgImage else { return builtIn.texture(for: id) }
        let value = SKTexture(cgImage: image); value.filteringMode = .nearest; value.usesMipmaps = false
        textures[id] = value
        return value
    }
    func pixel(_ tile: Tile, x: Int, y: Int, appearance: DecorationAppearance?) -> (UInt8, UInt8, UInt8, UInt8) {
        let resolution = terrainResolution
        let original = OriginalTerrainPixels.pixel(tile, x: x * 8 / resolution, y: y * 8 / resolution, appearance: appearance)
        let plain = OriginalTerrainPixels.pixel(Tile(terrain: tile.terrain), x: x * 8 / resolution, y: y * 8 / resolution)
        var base = pack?.textures[.terrain(tile.terrain)]?.sample(x: x, y: y, resolution: resolution) ?? plain
        if tile.terrain == .shallowWater, pack?.textures[.waterShallow] != nil {
            base = OriginalTerrainPixels.softenedShallow(base)
        }
        if tile.terrain.definition.isLiquid {
            let backing = OriginalTerrainPixels.pixel(Tile(terrain: tile.terrain), x: 1, y: 0)
            let inverse = 255 - Int(base.3)
            base = (UInt8(min(255, Int(base.0) + Int(backing.0) * inverse / 255)),
                    UInt8(min(255, Int(base.1) + Int(backing.1) * inverse / 255)),
                    UInt8(min(255, Int(base.2) + Int(backing.2) * inverse / 255)), 255)
        }
        if tile.decoration == .tree || tile.decoration == .pine {
            let pine = tile.decoration == .pine
            base = pack?.textures[pine ? .decorationSpruceLog : .decorationOakLog]?.sample(x: x, y: y, resolution: resolution)
                ?? OriginalTerrainPixels.logPixel(x: x * 8 / resolution, y: y * 8 / resolution, pine: pine)
            // A log is a solid block even if an optional custom texture has holes.
            let backing = OriginalTerrainPixels.logPixel(x: x * 8 / resolution, y: y * 8 / resolution, pine: pine)
            let inverse = 255 - Int(base.3)
            base = (UInt8(min(255, Int(base.0) + Int(backing.0) * inverse / 255)),
                    UInt8(min(255, Int(base.1) + Int(backing.1) * inverse / 255)),
                    UInt8(min(255, Int(base.2) + Int(backing.2) * inverse / 255)), 255)
        }
        if let decoration = tile.decoration {
            let id = appearance.map { TextureAssetID.decoration($0) } ?? TextureAssetID.decoration(decoration)
            if let raster = pack?.textures[id] ?? id.decorationFallback.flatMap({ pack?.textures[$0] }) {
                let overlay = raster.sample(x: x, y: y, resolution: resolution)
                let inverse = 255 - Int(overlay.3)
                base = (UInt8(min(255, Int(overlay.0) + Int(base.0) * inverse / 255)),
                        UInt8(min(255, Int(overlay.1) + Int(base.1) * inverse / 255)),
                        UInt8(min(255, Int(overlay.2) + Int(base.2) * inverse / 255)),
                        UInt8(min(255, Int(overlay.3) + Int(base.3) * inverse / 255)))
            } else if [.tree, .treeLeaves, .pine, .pineLeaves].contains(decoration) {
                let pine = decoration == .pine || decoration == .pineLeaves
                if let leaf = OriginalTerrainPixels.leafPixel(x: x * 8 / resolution, y: y * 8 / resolution, pine: pine) { base = leaf }
            } else if original != plain { base = original }
        }
        return base
    }
}
