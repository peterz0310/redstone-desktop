import SpriteKit

struct TerrainRenderMetrics: Equatable {
    var retainedChunks = 0
    var chunkNodes = 0
    var generatedChunks = 0
    var textureBuilds = 0
    var tileRasterBuilds = 0
    var status = ""
}

/// Terrain baked into one nearest-filtered sprite per chunk, with optional ambience masks.
/// Terrain cache survives editor camera changes; circuit/power/occupancy never rebuild textures.
@MainActor
final class TerrainChunkRenderer {
    var assets: any AssetProvider = BuiltInAssetProvider()
    private var assetRevision: UUID?
    private var ambience: TerrainAmbience?
    private var cache = ChunkCache()
    private var lavaByChunk: [ChunkCoordinate: Set<WorldCoordinate>] = [:]
    var lavaTiles: Set<WorldCoordinate> { Set(lavaByChunk.values.flatMap { $0 }) }
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
    private struct TileRaster {
        let pixels: [UInt8]
        let mask: [UInt8]
        let animated: Bool
    }
    private var tileRasters: [TileRasterKey: TileRaster] = [:]
    private(set) var metrics = TerrainRenderMetrics()

    func render(_ world: World, mapper: CoordinateMapper, screen: ScreenDescriptor, viewport: CGRect, into layer: SKNode) {
        guard let generation = world.generation else { return }
        let requested = mapper.visibleChunks(on: screen, viewport: viewport)
        if self.generation != generation || assetRevision != assets.revision {
            if assetRevision != assets.revision { tileRasters.removeAll(); ambience = TerrainAmbience(assets: assets) }
            for node in nodes.values { node.removeFromParent() }
            nodes.removeAll(); lavaByChunk.removeAll()
        } else if overrides != world.tiles || excluded != world.unspecifiedTiles {
            let changed = Set(overrides.keys).union(world.tiles.keys).filter { overrides[$0] != world.tiles[$0] }
                .union(excluded.symmetricDifference(world.unspecifiedTiles))
            let chunks = Set(changed.map(ChunkCoordinate.containing))
            for coordinate in chunks { nodes.removeValue(forKey: coordinate)?.removeFromParent(); lavaByChunk.removeValue(forKey: coordinate) }
        }
        assetRevision = assets.revision
        self.generation = generation; overrides = world.tiles; excluded = world.unspecifiedTiles
        for (coordinate, node) in nodes where !requested.contains(coordinate) { node.removeFromParent() }
        nodes = nodes.filter { requested.contains($0.key) }
        lavaByChunk = lavaByChunk.filter { requested.contains($0.key) }
        do {
            try cache.update(requested, settings: generation)
            for coordinate in requested {
                guard let chunk = cache.chunks[coordinate], let rect = mapper.sceneRect(forChunk: coordinate, on: screen) else { continue }
                let node: SKSpriteNode
                if let cached = nodes[coordinate] { node = cached }
                else {
                    guard let baked = texture(for: chunk, world: world) else { continue }
                    node = SKSpriteNode(texture: baked.texture)
                    if let mask = baked.mask { node.shader = ambience?.shader(mask: mask, textureSize: baked.texture.size()) }
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

    func advanceAnimation(at time: Double, reducedMotion: Bool, sceneryAnimations: Bool? = nil) {
        ambience?.advance(at: time, reducedMotion: reducedMotion, sceneryAnimations: sceneryAnimations)
    }

    private func texture(for chunk: TerrainChunk, world: World) -> (texture: SKTexture, mask: SKTexture?)? {
        let resolution = assets.terrainResolution
        let dimension = 32 * resolution
        guard let origin = chunk.coordinate.worldOrigin,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: dimension, pixelsHigh: dimension,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: dimension * 4, bitsPerPixel: 32),
              let bytes = bitmap.bitmapData else { return nil }
        var maskPixels = [UInt8](repeating: 0, count: dimension * dimension * 4)
        var hasAnimation = false
        var lava: Set<WorldCoordinate> = []
        let emptyPixels = [UInt8](repeating: 0, count: resolution * resolution * 4)
        let empty = TileRaster(pixels: emptyPixels, mask: emptyPixels, animated: false)
        maskPixels.withUnsafeMutableBufferPointer { destination in
            for y in 0..<32 { for x in 0..<32 {
                let coordinate = WorldCoordinate(x: origin.x + x, y: origin.y + y)
                let stored = world.tiles[coordinate] ?? (world.unspecifiedTiles.contains(coordinate) ? nil : chunk.tiles[coordinate])
                let tile = stored.map { TerrainAppearance.tile($0, generated: world.tiles[coordinate] == nil) }
                if tile?.terrain == .lava { lava.insert(coordinate) }
                let appearance = tile?.decoration.map { DecorationAppearance.choose($0, at: coordinate, seed: world.generation?.seed ?? 0, terrain: tile?.terrain) }
                let raster = tile.map { tileRaster($0, appearance: appearance, resolution: resolution) } ?? empty
                hasAnimation = hasAnimation || raster.animated
                raster.pixels.withUnsafeBufferPointer { source in
                    raster.mask.withUnsafeBufferPointer { mask in
                        for py in 0..<resolution {
                            // Raster rows increase downward; world/scene conversion remains in mapper.
                            let offset = ((dimension - 1 - (y * resolution + py)) * dimension + x * resolution) * 4
                            let sourceOffset = py * resolution * 4
                            bytes.advanced(by: offset).update(from: source.baseAddress!.advanced(by: sourceOffset), count: resolution * 4)
                            destination.baseAddress!.advanced(by: offset).update(from: mask.baseAddress!.advanced(by: sourceOffset), count: resolution * 4)
                        }
                    }
                }
            } }
        }
        lavaByChunk[chunk.coordinate] = lava
        guard let image = bitmap.cgImage else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        let mask: SKTexture?
        if hasAnimation, let image = RasterAsset(width: dimension, height: dimension, pixels: maskPixels).cgImage {
            let value = SKTexture(cgImage: image); value.filteringMode = .nearest; value.usesMipmaps = false; mask = value
        } else { mask = nil }
        return (texture, mask)
    }

    private func tileRaster(_ tile: Tile, appearance: DecorationAppearance?, resolution: Int) -> TileRaster {
        let key = TileRasterKey(terrain: tile.terrain, decoration: tile.decoration, appearance: appearance)
        if let raster = tileRasters[key] { return raster }
        var pixels: [UInt8] = [], mask: [UInt8] = []
        pixels.reserveCapacity(resolution * resolution * 4); mask.reserveCapacity(resolution * resolution * 4)
        let liquidCode: UInt8 = tile.terrain == .shallowWater ? 85 : tile.terrain == .deepWater ? 170 : tile.terrain == .lava ? 255 : 0
        var animated = false
        let plain = tile.decoration == nil ? nil : tileRaster(Tile(terrain: tile.terrain), appearance: nil, resolution: resolution).pixels
        for y in 0..<resolution { for x in 0..<resolution {
            let color = assets.pixel(tile, x: x, y: y, appearance: appearance)
            let index = (y * resolution + x) * 4
            let decorated = plain.map { color.0 != $0[index] || color.1 != $0[index + 1] || color.2 != $0[index + 2] || color.3 != $0[index + 3] } ?? false
            let ambient = tile.decoration != nil && tile.decoration != .rock && decorated
            pixels.append(contentsOf: [color.0, color.1, color.2, color.3])
            mask.append(contentsOf: [decorated ? 0 : liquidCode, ambient ? 255 : 0, 0, 255])
            animated = animated || liquidCode != 0 || ambient
        } }
        let raster = TileRaster(pixels: pixels, mask: mask, animated: animated)
        tileRasters[key] = raster
        metrics.tileRasterBuilds += 1
        return raster
    }
}
