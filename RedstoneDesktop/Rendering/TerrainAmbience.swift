import SpriteKit

/// One shared atlas per asset revision. Animation changes uniforms, never terrain textures/nodes.
@MainActor
final class TerrainAmbience {
    private let animations: [AnimatedRaster]
    private let atlas: SKUniform
    private let phases: [SKUniform]
    private let time = SKUniform(name: "u_ambienceTime", float: 0)
    private let motion = SKUniform(name: "u_motion", float: 1)
    private var lastTime: Double?
    private var lastReduced: Bool?
    private var lastScenery: Bool?

    init(assets: any AssetProvider) {
        let terrains: [TerrainID] = [.shallowWater, .deepWater, .lava]
        animations = terrains.map { assets.liquidAnimation(for: $0) }
        var pixels = [UInt8](repeating: 0, count: 48 * 1024 * 4)
        for (column, animation) in animations.enumerated() {
            for frame in 0..<animation.frameCount {
                let raster = animation.frame(frame).backedByOpaqueColor(OriginalTerrainPixels.pixel(Tile(terrain: terrains[column]), x: 1, y: 0))
                for y in 0..<16 { for x in 0..<16 {
                    let color = raster.sample(x: x, y: 15 - y, resolution: 16)
                    let offset = ((frame * 16 + y) * 48 + column * 16 + x) * 4
                    pixels.replaceSubrange(offset..<offset + 4, with: [color.0, color.1, color.2, color.3])
                } }
            }
        }
        let texture = SKTexture(cgImage: RasterAsset(width: 48, height: 1024, pixels: pixels).cgImage!)
        texture.filteringMode = .nearest; texture.usesMipmaps = false
        atlas = SKUniform(name: "u_liquidAtlas", texture: texture)
        phases = ["u_shallowPhase", "u_deepPhase", "u_lavaPhase"].map { SKUniform(name: $0, vectorFloat3: .zero) }
        advance(at: 0, reducedMotion: false)
    }

    func advance(at currentTime: Double, reducedMotion: Bool, sceneryAnimations: Bool? = nil) {
        guard currentTime.isFinite else { return }
        if lastReduced == reducedMotion, lastScenery == (sceneryAnimations ?? !reducedMotion), let lastTime, currentTime >= lastTime, currentTime - lastTime < 0.05 { return }
        lastTime = currentTime; lastReduced = reducedMotion; lastScenery = sceneryAnimations ?? !reducedMotion
        motion.floatValue = (sceneryAnimations ?? !reducedMotion) ? 1 : 0
        // Bounded time avoids float precision loss during long-running desktop sessions.
        time.floatValue = (sceneryAnimations ?? !reducedMotion) ? Float(currentTime.truncatingRemainder(dividingBy: 120)) : 0
        for (index, animation) in animations.enumerated() {
            let phase = animation.spec.phase(at: reducedMotion ? 0 : currentTime)
            phases[index].vectorFloat3Value = SIMD3(Float(phase.frame), Float(phase.next), phase.blend)
        }
    }

    func shader(mask: SKTexture, textureSize: CGSize = CGSize(width: 1, height: 1)) -> SKShader {
        let shader = SKShader(source: Self.source)
        shader.uniforms = [atlas, time, motion] + phases + [
            SKUniform(name: "u_liquidMap", texture: mask),
            SKUniform(name: "u_terrainSize", vectorFloat2: SIMD2(Float(textureSize.width), Float(textureSize.height)))
        ]
        return shader
    }

    static let source = """
    void main() {
        // Shader samplers can interpolate despite SKTexture.filteringMode. Sample
        // exact texel centers for the baked terrain AND its semantic mask.
        vec2 center = (floor(v_tex_coord * u_terrainSize) + 0.5) / u_terrainSize;
        vec4 color = texture2D(u_texture, center);
        vec2 mask = texture2D(u_liquidMap, center).rg;
        if (mask.r > 0.1) {
            float kind = floor(mask.r * 3.0 + 0.5) - 1.0;
            vec3 phase = kind < 0.5 ? u_shallowPhase : (kind < 1.5 ? u_deepPhase : u_lavaPhase);
            vec2 pixel = (floor(fract(v_tex_coord * 32.0) * 16.0) + 0.5) / 16.0;
            vec2 first = vec2((kind + pixel.x) / 3.0, (63.0 - phase.x + pixel.y) / 64.0);
            vec2 next = vec2(first.x, (63.0 - phase.y + pixel.y) / 64.0);
            color = mix(texture2D(u_liquidAtlas, first), texture2D(u_liquidAtlas, next), phase.z);
        }
        if (mask.g > 0.5) {
            float glint = sin(u_ambienceTime * 1.4 + v_tex_coord.x * 87.0 + v_tex_coord.y * 53.0);
            color.rgb *= 1.0 + glint * 0.035 * u_motion;
        }
        gl_FragColor = color * v_color_mix;
    }
    """
}
