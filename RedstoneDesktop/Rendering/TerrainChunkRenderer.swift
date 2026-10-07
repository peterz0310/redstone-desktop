import SpriteKit

struct TerrainRenderMetrics: Equatable {
    var retainedChunks = 0
    var chunkNodes = 0
    var generatedChunks = 0
    var textureBuilds = 0
    var status = ""
}

/// Original eight-pixel placeholder tiles baked into one nearest-filtered sprite per chunk.
/// Terrain cache survives editor camera changes; circuit/power/occupancy never rebuild textures.
@MainActor
final class TerrainChunkRenderer {
    private var cache = ChunkCache()
    private var nodes: [ChunkCoordinate: SKSpriteNode] = [:]
    private var overrides: [WorldCoordinate: Tile] = [:]
    private var excluded: Set<WorldCoordinate> = []
    private var generation: WorldGenerationSettings?
    private(set) var metrics = TerrainRenderMetrics()

    func render(_ world: World, mapper: CoordinateMapper, screen: ScreenDescriptor, viewport: CGRect, into layer: SKNode) {
        guard let generation = world.generation else { return }
        let requested = mapper.visibleChunks(on: screen, viewport: viewport)
        if self.generation != generation || overrides != world.tiles || excluded != world.unspecifiedTiles {
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
        let dimension = 256
        guard let origin = chunk.coordinate.worldOrigin,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: dimension, pixelsHigh: dimension,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: dimension * 4, bitsPerPixel: 32),
              let bytes = bitmap.bitmapData else { return nil }
        for y in 0..<32 {
            for x in 0..<32 {
                let coordinate = WorldCoordinate(x: origin.x + x, y: origin.y + y)
                let tile = world.tiles[coordinate] ?? (world.unspecifiedTiles.contains(coordinate) ? nil : chunk.tiles[coordinate])
                for py in 0..<8 {
                    for px in 0..<8 {
                        let color = tile.map { OriginalTerrainPixels.pixel($0, x: px, y: py) } ?? (0, 0, 0, 0)
                        // Raster rows increase downward; global/scene conversion remains in mapper.
                        let offset = ((255 - (y * 8 + py)) * dimension + x * 8 + px) * 4
                        bytes[offset] = color.0; bytes[offset + 1] = color.1
                        bytes[offset + 2] = color.2; bytes[offset + 3] = color.3
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
}

/// Semantic, project-owned placeholder art; no files/assets from another game.
enum OriginalTerrainPixels {
    static func pixel(_ tile: Tile, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
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
            switch decoration {
            case .tree:
                if x == 4 && (1...5).contains(y) { return (95, 61, 35, 255) }
                if (2...6).contains(x) && (3...6).contains(y) { return (31, 77, 38, 255) }
            case .flower:
                if x == 4 && y == 3 { return (242, 213, 66, 255) }
                if abs(x - 4) + abs(y - 3) == 1 { return (212, 88, 123, 255) }
            case .rock:
                if (2...5).contains(x) && (2...4).contains(y) { return (83, 88, 96, 255) }
            case .reed:
                if (x == 2 || x == 4 || x == 6) && (2...5).contains(y) { return (71, 116, 48, 255) }
            }
        }
        let shade: UInt8 = (x + y) % 5 == 0 ? 8 : 0
        return (base.0 - shade, base.1 - shade, base.2 - shade, 255)
    }
}
