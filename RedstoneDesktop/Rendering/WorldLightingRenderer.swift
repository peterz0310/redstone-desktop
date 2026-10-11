import SpriteKit

/// A small smooth light map per visible chunk shades terrain and circuits together.
/// Camera/time updates reuse masks; only changed emitters rebuild them.
@MainActor final class WorldLightingRenderer {
    private let white = SKTexture(cgImage: RasterAsset(width: 1, height: 1, pixels: [255, 255, 255, 255]).cgImage!)
    private let ambient = SKUniform(name: "u_daylight", float: 1)
    private var nodes: [ChunkCoordinate: SKSpriteNode] = [:]
    private var lastSources: [WorldCoordinate: Double] = [:]
    private var lastEnabled = true
    private var lastTime: Double?
    private(set) var textureBuilds = 0

    func advance(settings: WorldLightingSettings, time: Double) {
        guard lastTime == nil || abs(time - lastTime!) >= 0.1 else { return }
        lastTime = time
        ambient.floatValue = Float(settings.daylight(at: time))
    }
    func render(world: World, lava: Set<WorldCoordinate>, power: [WorldCoordinate: PowerLevel],
                mapper: CoordinateMapper, screen: ScreenDescriptor, into layer: SKNode, time: Double) {
        let settings = world.lighting ?? WorldLightingSettings()
        lastTime = nil; advance(settings: settings, time: time)
        layer.isHidden = settings.mode == .day
        if layer.isHidden { return }
        var sources: [WorldCoordinate: Double] = [:]
        if settings.localLights {
            for tile in lava { sources[tile] = 1 }
            for (tile, component) in world.circuit.components where component.kind == .lightTorch { sources[tile] = 1 }
            for (tile, level) in power where level > .off && world.circuit.components[tile] != nil {
                sources[tile] = max(sources[tile] ?? 0, Double(level.rawValue) / 15)
            }
        }
        let changed = lastSources != sources || lastEnabled != settings.localLights
        lastSources = sources; lastEnabled = settings.localLights
        // Terrain requests include a margin, supplying offscreen lava at chunk seams.
        let requested = mapper.visibleChunks(on: screen, viewport: CGRect(origin: .zero, size: screen.frame.size), margin: 0)
        for (chunk, node) in nodes where !requested.contains(chunk) { node.removeFromParent() }
        nodes = nodes.filter { requested.contains($0.key) }
        for chunk in requested {
            guard let origin = chunk.worldOrigin, let rect = mapper.sceneRect(forChunk: chunk, on: screen) else { continue }
            let node: SKSpriteNode
            if let existing = nodes[chunk] { node = existing }
            else {
                node = SKSpriteNode(texture: white); node.size = rect.size; node.anchorPoint = .zero
                node.name = "lighting:\(chunk.x),\(chunk.y)"
                nodes[chunk] = node; layer.addChild(node)
            }
            if changed || node.shader == nil {
                // One tile of padding keeps filtered illumination continuous at seams.
                var values = [Double](repeating: 0, count: 34 * 34)
                for (source, strength) in sources {
                    let dx = source.x.subtractingReportingOverflow(origin.x), dy = source.y.subtractingReportingOverflow(origin.y)
                    guard !dx.overflow, !dy.overflow, (-6...37).contains(dx.partialValue), (-6...37).contains(dy.partialValue) else { continue }
                    let sx = dx.partialValue, sy = dy.partialValue
                    for y in max(-1, sy - 5)...min(32, sy + 5) {
                        for x in max(-1, sx - 5)...min(32, sx + 5) {
                            let index = (32 - y) * 34 + x + 1
                            values[index] = max(values[index], WorldLightFalloff.intensity(dx: x - sx, dy: y - sy, radius: 5, strength: strength))
                        }
                    }
                }
                let pixels = values.flatMap { value -> [UInt8] in let v = UInt8(min(255, max(0, value * 255))); return [v, v, v, 255] }
                guard let image = RasterAsset(width: 34, height: 34, pixels: pixels).cgImage else { continue }
                let texture = SKTexture(cgImage: image); texture.filteringMode = .linear; texture.usesMipmaps = false
                node.texture = texture
                let shader = SKShader(source: """
                void main() {
                    float glow = texture2D(u_texture, (v_tex_coord * 32.0 + 1.0) / 34.0).r;
                    float darkness = (1.0 - u_daylight) * (1.0 - glow);
                    gl_FragColor = vec4(0.012, 0.025, 0.075, darkness) * v_color_mix;
                }
                """)
                shader.uniforms = [ambient]
                node.shader = shader; textureBuilds += 1
            }
            node.position = rect.origin; node.size = rect.size
        }
    }
}
