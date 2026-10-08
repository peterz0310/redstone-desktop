import SpriteKit
import Combine

@MainActor
protocol AssetProvider: AnyObject {
    var revision: UUID { get }
    var terrainResolution: Int { get }
    func texture(for id: TextureAssetID) -> SKTexture?
    func pixel(_ tile: Tile, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8)
}

@MainActor
final class BuiltInAssetProvider: AssetProvider {
    let revision = UUID()
    let terrainResolution = 8
    private var textures: [TextureAssetID: SKTexture] = [:]
    func texture(for id: TextureAssetID) -> SKTexture? {
        if let existing = textures[id] { return existing }
        let texture: SKTexture
        if let circuit = id.circuitID { texture = SKTexture(image: CircuitTextures.image(for: circuit)) }
        else {
            let terrain = TerrainID.allCases.first { TextureAssetID.terrain($0) == id }
            let decoration = DecorationID.allCases.first { TextureAssetID.decoration($0) == id }
            guard terrain != nil || decoration != nil else { return nil }
            var bytes: [UInt8] = []
            for y in (0..<8).reversed() {
                for x in 0..<8 {
                    let value = OriginalTerrainPixels.pixel(Tile(terrain: terrain ?? .grass, decoration: decoration), x: x, y: y)
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
    func pixel(_ tile: Tile, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) { OriginalTerrainPixels.pixel(tile, x: x, y: y) }
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
    private let preferences: UserDefaults?
    var terrainResolution: Int { pack?.textures.keys.contains(where: { $0.circuitID == nil }) == true ? 16 : 8 }
    var soundOverrides: [SoundID: [Float]] { pack?.sounds ?? [:] }

    init(preferences: UserDefaults? = nil) { self.preferences = preferences }
    func restoreSelection() async {
        guard let path = preferences?.string(forKey: "assetPackPath") else { return }
        await load(URL(fileURLWithPath: path))
    }
    func load(_ url: URL) async {
        generation = UUID(); let request = generation
        isLoading = true; status = "Loading \(url.lastPathComponent)…"
        let result = await Task.detached(priority: .userInitiated) { Result { try ResourcePackLoader.load(url) } }.value
        guard generation == request else { return }
        source = url
        switch result {
        case .success(let value):
            apply(value)
            status = "\(value.textures.count) textures · \(value.sounds.count) sounds · \(value.warnings.count) warnings"
            preferences?.set(url.path, forKey: "assetPackPath")
        case .failure(let error):
            apply(nil); status = "Pack refused: \(error.localizedDescription) Built-in assets active."
            preferences?.removeObject(forKey: "assetPackPath")
        }
        isLoading = false
    }
    func useBuiltIn() {
        generation = UUID(); isLoading = false; source = nil
        apply(nil); status = "Built-in original assets active."
        preferences?.removeObject(forKey: "assetPackPath")
    }
    func apply(_ value: LoadedPack?) {
        pack = value; textures = [:]; name = value?.manifest.name ?? "Built-in original assets"
        warnings = value?.warnings ?? []; revision = UUID()
    }
    func texture(for id: TextureAssetID) -> SKTexture? {
        if let value = textures[id] { return value }
        guard let raster = pack?.textures[id], let image = raster.cgImage else { return builtIn.texture(for: id) }
        let value = SKTexture(cgImage: image); value.filteringMode = .nearest; value.usesMipmaps = false
        textures[id] = value
        return value
    }
    func pixel(_ tile: Tile, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let resolution = terrainResolution
        let original = OriginalTerrainPixels.pixel(tile, x: x * 8 / resolution, y: y * 8 / resolution)
        let plain = OriginalTerrainPixels.pixel(Tile(terrain: tile.terrain), x: x * 8 / resolution, y: y * 8 / resolution)
        var base = pack?.textures[.terrain(tile.terrain)]?.sample(x: x, y: y, resolution: resolution) ?? plain
        if let decoration = tile.decoration {
            if let raster = pack?.textures[.decoration(decoration)] {
                let overlay = raster.sample(x: x, y: y, resolution: resolution)
                let inverse = 255 - Int(overlay.3)
                base = (UInt8(min(255, Int(overlay.0) + Int(base.0) * inverse / 255)),
                        UInt8(min(255, Int(overlay.1) + Int(base.1) * inverse / 255)),
                        UInt8(min(255, Int(overlay.2) + Int(base.2) * inverse / 255)),
                        UInt8(min(255, Int(overlay.3) + Int(base.3) * inverse / 255)))
            } else if original != plain { base = original }
        }
        return base
    }
}
