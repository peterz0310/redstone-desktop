import SpriteKit

struct TerrainRenderMetrics: Equatable {
    var retainedChunks = 0
    var chunkNodes = 0
    var generatedChunks = 0
    var textureBuilds = 0
    var tileRasterBuilds = 0
    var status = ""
}

/// Original eight-pixel placeholder tiles baked into one nearest-filtered sprite per chunk.
/// Terrain cache survives editor camera changes; circuit/power/occupancy never rebuild textures.
@MainActor
final class TerrainChunkRenderer {
    var assets: any AssetProvider = BuiltInAssetProvider()
    private var assetRevision: UUID?
    private var cache = ChunkCache()
    private var nodes: [ChunkCoordinate: SKSpriteNode] = [:]
    private var overrides: [WorldCoordinate: Tile] = [:]
    private var excluded: Set<WorldCoordinate> = []
    private var generation: WorldGenerationSettings?
    private struct TileRasterKey: Hashable {
        let terrain: TerrainID
        let decoration: DecorationID?
        let appearance: DecorationAppearance?
    }
    // Finite semantic combinations, scoped to the current asset revision, independent of map size.
    private var tileRasters: [TileRasterKey: [UInt8]] = [:]
    private(set) var metrics = TerrainRenderMetrics()

    func render(_ world: World, mapper: CoordinateMapper, screen: ScreenDescriptor, viewport: CGRect, into layer: SKNode) {
        guard let generation = world.generation else { return }
        let requested = mapper.visibleChunks(on: screen, viewport: viewport)
        if self.generation != generation || overrides != world.tiles || excluded != world.unspecifiedTiles || assetRevision != assets.revision {
            if assetRevision != assets.revision { tileRasters.removeAll() }
            assetRevision = assets.revision
            for node in nodes.values { node.removeFromParent() }
            nodes.removeAll()
            self.generation = generation; overrides = world.tiles; excluded = world.unspecifiedTiles
        }
        for (coordinate, node) in nodes where !requested.contains(coordinate) { node.removeFromParent() }
        nodes = nodes.filter { requested.contains($0.key) }
        do {
            try cache.update(requested, settings: generation)
            for coordinate in requested {
                guard let chunk = cache.chunks[coordinate], let rect = mapper.sceneRect(forChunk: coordinate, on: screen) else { continue }
                let node: SKSpriteNode
                if let cached = nodes[coordinate] { node = cached }
                else {
                    guard let texture = texture(for: chunk, world: world) else { continue }
                    node = SKSpriteNode(texture: texture)
                    node.anchorPoint = .zero
                    node.name = "chunk:\(coordinate.x),\(coordinate.y)"
                    nodes[coordinate] = node
                    metrics.textureBuilds += 1
                }
                node.position = rect.origin; node.size = rect.size
                if node.parent !== layer { node.removeFromParent(); layer.addChild(node) }
            }
            metrics.status = requested.isEmpty ? "Viewport outside supported render range." : ""
        } catch { metrics.status = "Terrain generation failed: \(error)" }
        metrics.retainedChunks = cache.chunks.count
        metrics.chunkNodes = nodes.count
        metrics.generatedChunks = cache.generatedCount
    }

    private func texture(for chunk: TerrainChunk, world: World) -> SKTexture? {
        let resolution = assets.terrainResolution
        let dimension = 32 * resolution
        guard let origin = chunk.coordinate.worldOrigin,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: dimension, pixelsHigh: dimension,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: dimension * 4, bitsPerPixel: 32),
              let bytes = bitmap.bitmapData else { return nil }
        for y in 0..<32 {
            for x in 0..<32 {
                let coordinate = WorldCoordinate(x: origin.x + x, y: origin.y + y)
                let stored = world.tiles[coordinate] ?? (world.unspecifiedTiles.contains(coordinate) ? nil : chunk.tiles[coordinate])
                let tile = stored.map { TerrainAppearance.tile($0, generated: world.tiles[coordinate] == nil) }
                let appearance = tile?.decoration.map { DecorationAppearance.choose($0, at: coordinate, seed: world.generation?.seed ?? 0, terrain: tile?.terrain) }
                let raster = tile.map { tileRaster($0, appearance: appearance, resolution: resolution) }
                    ?? [UInt8](repeating: 0, count: resolution * resolution * 4)
                raster.withUnsafeBufferPointer { source in
                    for py in 0..<resolution {
                        // Raster rows increase downward; world/scene conversion remains in mapper.
                        let offset = ((dimension - 1 - (y * resolution + py)) * dimension + x * resolution) * 4
                        bytes.advanced(by: offset).update(from: source.baseAddress!.advanced(by: py * resolution * 4), count: resolution * 4)
                    }
                }
            }
        }
        guard let image = bitmap.cgImage else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        return texture
    }

    private func tileRaster(_ tile: Tile, appearance: DecorationAppearance?, resolution: Int) -> [UInt8] {
        let key = TileRasterKey(terrain: tile.terrain, decoration: tile.decoration, appearance: appearance)
        if let raster = tileRasters[key] { return raster }
        var raster: [UInt8] = []
        raster.reserveCapacity(resolution * resolution * 4)
        for y in 0..<resolution { for x in 0..<resolution {
            let color = assets.pixel(tile, x: x, y: y, appearance: appearance)
            raster.append(contentsOf: [color.0, color.1, color.2, color.3])
        } }
        tileRasters[key] = raster
        metrics.tileRasterBuilds += 1
        return raster
    }
}

/// Semantic, project-owned placeholder art; no files/assets from another game.
enum OriginalTerrainPixels {
    static func pixel(_ tile: Tile, x: Int, y: Int, appearance: DecorationAppearance? = nil) -> (UInt8, UInt8, UInt8, UInt8) {
        let base: (UInt8, UInt8, UInt8)
        switch tile.terrain {
        case .grass: base = (77, 128, 77)
        case .dirt: base = (135, 95, 59)
        case .stone: base = (139, 148, 154)
        case .sand: base = (214, 197, 132)
        case .shallowWater: base = (85, 177, 196)
        case .deepWater: base = (43, 97, 143)
        }
        if let decoration = tile.decoration {
            let style = appearance ?? DecorationAppearance.choose(decoration, at: WorldCoordinate(x: 0, y: 0), seed: 0, terrain: tile.terrain)
            switch style {
            case .tree:
                if x == 4 && (1...5).contains(y) { return (95, 61, 35, 255) }
                if (2...6).contains(x) && (3...6).contains(y) { return (31, 77, 38, 255) }
            case .poppy, .dandelion, .blueOrchid, .allium, .oxeyeDaisy:
                if x == 4 && (1...3).contains(y) { return (43, 100, 42, 255) }
                if x == 4 && y == 5 { return (242, 213, 66, 255) }
                if abs(x - 4) + abs(y - 5) == 1 {
                    switch style {
                    case .poppy: return (225, 40, 54, 255)
                    case .dandelion: return (247, 205, 48, 255)
                    case .blueOrchid: return (86, 179, 238, 255)
                    case .allium: return (190, 120, 216, 255)
                    default: return (236, 237, 226, 255)
                    }
                }
            case .coal, .iron:
                if (1...6).contains(x) && (1...6).contains(y) {
                    if (x * 3 + y * 5) % 7 < 2 { return style == .coal ? (32, 34, 39, 255) : (205, 160, 126, 255) }
                    return (128, 135, 142, 255)
                }
            case .reed:
                if (x == 2 || x == 4 || x == 6) && (2...5).contains(y) { return (71, 116, 48, 255) }
            case .cactus:
                if (2...5).contains(x) && (2...5).contains(y) {
                    return (x + y) % 3 == 0 ? (26, 82, 30, 255) : (57, 137, 52, 255)
                }
            }
        }
        let shade: UInt8 = (x + y) % 5 == 0 ? 8 : 0
        return (base.0 - shade, base.1 - shade, base.2 - shade, 255)
    }
}
